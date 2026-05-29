#!/usr/bin/env python3
"""
Ground-truth accuracy scorer for the HighNotes harness.

Where index.md / Comparator measure Apple-vs-Claude *agreement* (only a proxy —
chasing it can pull Apple toward Claude's errors), this scores EACH side against
hand-authored ground truth in `tests/fixtures/ground-truth.json`, keyed by the
fixture image FILENAME (cannabis labels have no folder-slug ground truth like
wine appellations, so each must be read off the label by a human once).

The scorer:
  - skips "_"-prefixed keys (_conventions, and per-entry _template / _comment),
  - only scores a field the entry ASSERTS (present + non-null),
  - applies the tolerances in _conventions (cannabinoids +/-0.5, terpenes +/-0.1,
    productType exact enum, strainName/cultivator contains-match, dates ISO exact,
    netWeight digits+unit),
  - reports Apple-correct% vs Claude-correct% per field,
  - `dominantTerpene` is a TRUTH-ONLY convenience field (the single highest-%
    terpene on the label) scored against whichever terpene the model reports
    highest — it is NOT a CannabisLabel field the model emits.

Usage:
  python3 score.py results/<run>/run.json [more/run.json ...]
  python3 score.py results/<run>/run.json --emit        # also write accuracy.md
  python3 score.py results/<run>/run.json --golden       # regression gate
  python3 score.py results/<run>/run.json --filter 0774  # subset by image name
"""
import json, sys, os, unicodedata, re

GT_PATH = os.path.join(os.path.dirname(__file__), "../fixtures/ground-truth.json")

CANNABINOID_FIELDS = ["totalThc", "totalCbd", "thca", "delta9thc", "cbd", "cbg", "totalCannabinoids"]
TERPENE_FIELDS = ["myrcene", "limonene", "linalool", "betaCaryophyllene", "pinene", "humulene", "totalTerpenes"]
STRING_CONTAINS_FIELDS = ["strainName", "cultivator"]
DATE_FIELDS = ["harvestDate", "expirationDate"]
CANNABINOID_TOL = 0.5
TERPENE_TOL = 0.1

# Field display order in the report.
FIELDS_OUT = (["strainName", "cultivator", "productType", "netWeight"]
              + CANNABINOID_FIELDS + TERPENE_FIELDS + DATE_FIELDS + ["dominantTerpene"])


def norm(s):
    if s is None: return ""
    s = unicodedata.normalize("NFKD", str(s)).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9 ]", " ", s.lower())


def fold_ws(s):
    return re.sub(r"\s+", " ", norm(s)).strip()


def contains_correct(extracted, truth):
    # truth is contained in the model value (handles trailing brand/weight noise)
    e, t = fold_ws(extracted), fold_ws(truth)
    if not e or not t: return False
    return t in e or e in t


def exact_correct(extracted, truth):
    return fold_ws(extracted) == fold_ws(truth) and fold_ws(truth) != ""


def numeric_correct(extracted, truth, tol):
    try:
        if extracted is None: return False
        return abs(float(extracted) - float(truth)) <= tol
    except (TypeError, ValueError):
        return False


def weight_correct(extracted, truth):
    # compare digits + unit, ignoring spaces ("3.5g" == "3.5 G")
    def w(s):
        s = (str(s) if s is not None else "").lower().replace(" ", "")
        m = re.search(r"([0-9]*\.?[0-9]+)\s*(g|mg|oz|ml)", s)
        return (m.group(1), m.group(2)) if m else (None, None)
    we, wt = w(extracted), w(truth)
    return we[0] is not None and we == wt


def date_correct(extracted, truth):
    # ISO YYYY-MM-DD exact
    def d(s):
        m = re.search(r"\d{4}-\d{2}-\d{2}", str(s) if s is not None else "")
        return m.group(0) if m else None
    return d(truth) is not None and d(extracted) == d(truth)


def dominant_terpene_of(label):
    """The terpene field with the highest value on a model label (excludes total)."""
    best, best_v = None, -1.0
    for f in TERPENE_FIELDS:
        if f == "totalTerpenes": continue
        v = label.get(f)
        try:
            fv = float(v)
        except (TypeError, ValueError):
            continue
        if fv > best_v:
            best, best_v = f, fv
    return best


def field_correct(field, label, truth_val):
    if field in STRING_CONTAINS_FIELDS:
        return contains_correct(label.get(field), truth_val)
    if field == "productType":
        return exact_correct(label.get(field), truth_val)
    if field == "netWeight":
        return weight_correct(label.get(field), truth_val)
    if field in DATE_FIELDS:
        return date_correct(label.get(field), truth_val)
    if field in CANNABINOID_FIELDS:
        return numeric_correct(label.get(field), truth_val, CANNABINOID_TOL)
    if field in TERPENE_FIELDS:
        return numeric_correct(label.get(field), truth_val, TERPENE_TOL)
    if field == "dominantTerpene":
        # score against whichever terpene the model reports highest
        dom = dominant_terpene_of(label)
        return dom is not None and fold_ws(dom) == fold_ws(truth_val)
    return False


def score(labels, gt, filt):
    tally = {f: {"n": 0, "apple": 0, "claude": 0} for f in FIELDS_OUT}
    for L in labels:
        name = L.get("image", "")
        if filt and filt not in name: continue
        g = gt.get(name)
        if not g: continue
        a = (L.get("apple", {}) or {}).get("label") or {}
        c = (L.get("claude", {}) or {}).get("label") or {}
        for f in FIELDS_OUT:
            tv = g.get(f)
            if tv is None or tv == "": continue  # only score asserted (present, non-empty) fields
            tally[f]["n"] += 1
            if field_correct(f, a, tv): tally[f]["apple"] += 1
            if field_correct(f, c, tv): tally[f]["claude"] += 1
    return tally


def pct(x, n): return f"{100*x/n:5.1f}%" if n else "   n/a"


def render_md(tally, tag):
    out = [f"# Ground-truth accuracy — {tag}", "",
           "Apple/Claude scored against hand-authored `ground-truth.json` "
           "(keyed by fixture filename). Both sides are **post-pipeline** — i.e. "
           "what the app actually produces after deterministic cleanup. Only "
           "fields a ground-truth entry asserts are counted. Tolerances: "
           "cannabinoids +/-0.5, terpenes +/-0.1; productType/dates exact; "
           "strainName/cultivator contains-match.", "",
           "Agreement (index.md) is a proxy; THIS is correctness.", "",
           "| Field | Scored | Apple correct | Claude correct |",
           "|---|---:|---:|---:|"]
    for f in FIELDS_OUT:
        n = tally[f]["n"]
        if n == 0: continue
        out.append(f"| {f} | {n} | {pct(tally[f]['apple'], n).strip()} | {pct(tally[f]['claude'], n).strip()} |")
    out.append("")
    return "\n".join(out)


def load_run(path): return json.load(open(path))


def main():
    args = sys.argv[1:]
    filt, emit, golden = "", False, False
    if "--filter" in args:
        i = args.index("--filter"); filt = args[i+1]; del args[i:i+2]
    if "--emit" in args:
        emit = True; args.remove("--emit")
    if "--golden" in args:
        golden = True; args.remove("--golden")
    if not args:
        print(__doc__); return
    gt = {k: v for k, v in json.load(open(GT_PATH)).items() if not k.startswith("_")}

    if golden:
        # Regression gate: score ONLY the golden labels; exit non-zero if Apple's
        # mean asserted-field accuracy falls below the floor. A forward tripwire
        # against a stochastic model, not a brittle single-run hard floor.
        gpath = os.path.join(os.path.dirname(__file__), "golden.json")
        gdoc = json.load(open(gpath))
        gset = set(gdoc["labels"]); floor = gdoc.get("accuracy_floor", 0.75)
        labels = [L for L in load_run(args[0]) if L.get("image") in gset]
        t = score(labels, gt, "")
        tot_n = sum(t[f]["n"] for f in FIELDS_OUT)
        apple_ok = sum(t[f]["apple"] for f in FIELDS_OUT)
        acc = apple_ok / tot_n if tot_n else 0.0
        print(f"GOLDEN: {len(labels)}/{len(gset)} golden labels present; "
              f"Apple mean field accuracy {acc*100:.1f}% (floor {floor*100:.0f}%) over {tot_n} asserted fields")
        if len(labels) < len(gset):
            missing = gset - {L.get('image') for L in labels}
            print(f"  WARNING: {len(missing)} golden labels not in this run: {sorted(missing)}")
        if tot_n and acc < floor:
            print(f"  FAIL: accuracy {acc*100:.1f}% below floor {floor*100:.0f}%")
            sys.exit(1)
        print("  PASS")
        return

    for path in args:
        labels = load_run(path)
        t = score(labels, gt, filt)
        tag = os.path.basename(os.path.dirname(path)) or path
        print(f"\n=== {tag}  (filter={filt or 'none'}) ===")
        print(f"{'field':18} {'scored':>6} {'Apple':>8} {'Claude':>8}")
        for f in FIELDS_OUT:
            n = t[f]["n"]
            if n == 0: continue
            print(f"{f:18} {n:>6} {pct(t[f]['apple'], n):>8} {pct(t[f]['claude'], n):>8}")
        if emit:
            md_path = os.path.join(os.path.dirname(path), "accuracy.md")
            open(md_path, "w").write(render_md(t, tag))
            print(f"  wrote {md_path}")


if __name__ == "__main__":
    main()
