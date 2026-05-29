#!/usr/bin/env python3
"""
Deterministic synthetic NJ-CRC cannabis label generator for the HighNotes harness.

We KNOW the ground truth because we author the values, so no Claude proxy is
needed — the harness scores Apple Foundation Models extraction directly against
truth (see docs/NJ-CRC-LABEL-SPEC.md for the field/format/value-range contract).

Each generated case emits, keyed by a stable slug:
  - assets/validation/synthetic/<slug>.ocr.txt   noised OCR text (FM-only stress)
  - assets/validation/synthetic/<slug>.html      clean label for PNG rendering
  - one entry in tests/fixtures/ground-truth-synthetic.json (truth, scorer schema)

Two fixture levels per the spec:
  TEXT  — <slug>.ocr.txt : bypasses Vision OCR, stresses FM extraction with the
          controlled, deterministic OCR-noise model from the canary.
  IMAGE — <slug>.html -> render.sh -> <slug>.png : full pipeline incl. real OCR.

Reproducible: fixed seed, no wall-clock, no randomness outside seeded `rng`.

Usage:
  python3 generate.py                # regenerate the full synthetic set
  python3 generate.py --seed 7       # different deterministic draw
  python3 generate.py --count 40     # scale up
"""
import argparse, json, os, random, re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(REPO, "assets", "validation", "synthetic")
GT_OUT = os.path.join(REPO, "tests", "fixtures", "ground-truth-synthetic.json")

# ----------------------------------------------------------------------------
# Content pools (plausible, NJ-CRC-shaped; not real licensees)
# ----------------------------------------------------------------------------
CULTIVATORS = [
    ("Fresh Grow LLC", "Fresh Grow", "C000186"),
    ("Garden State Dispensary", "Garden State Dispensary", "C000067"),
    ("Ayr Wellness NJ", "Ayr Wellness NJ", "C000033"),
    ("Bloom Farms NJ", "Bloom Farms", "C000241"),
    ("Pine Barrens Cannabis Co", "Pine Barrens", "C000412"),
    ("Liberty Leaf Cultivation", "Liberty Leaf", "M000127"),
    ("Cape May Cannabis", "Cape May Cannabis", "C000308"),
]
ADDRESSES = [
    ("15 World's Fair Drive", "Somerset, NJ, 08873", "(973) 400-0188"),
    ("88 Commerce Way", "Trenton, NJ, 08611", "(609) 555-1234"),
    ("210 Industrial Ave", "Newark, NJ, 07105", "(862) 200-7781"),
    ("4 Pinelands Rd", "Vineland, NJ, 08360", "(856) 332-9090"),
]
STRAINS = [
    "Blue Candy Rain", "Caramel Gelato", "Lollipopz", "Warheadz",
    "Sour Watermelon", "Bedtime Blueberry", "Wedding Cake", "Gary Payton",
    "Runtz", "Northern Lights", "Sour Diesel", "Granddaddy Purple",
    "Tropicana Cherry", "Apple Fritter", "Cereal Milk", "Zkittlez",
    "Papaya", "Animal Mintz", "Jealousy", "Modified Grapes",
]
BRANDS = ["Zips", "Kynd", "Panda Farms", "Cookies", "Rythm", "Verano", "(none)"]
# (terpene field, label name, clean spelling, noisy spelling)
TERPS = [
    ("myrcene", "BetaMyrcene", "Betamyrcene"),
    ("limonene", "Limonene", "Lim onene"),
    ("linalool", "Linalool", "Linaool"),
    ("betaCaryophyllene", "BetaCaryophyllene", "BetaCaryophylene"),
    ("pinene", "AlphaPinene", "Aphapinene"),
    ("humulene", "Humulene", "Humuiene"),
]
GROWTH = ["Indoor", "Outdoor", "Soil-grown", "Hydroponic", "Aquaponic"]

WARNINGS = [
    "This product contains cannabis",
    "This product is intended for use by adults 21 years of age or older and not for resale. Keep out of the reach of children",
    "There may be health risks associated with the consumption of this product, including for women who are pregnant, breastfeeding, or planning on becoming pregnant",
    "Do not drive a motor vehicle or operate heavy machinery while using this product",
    "Poison Control 1-800-222-1222",
]
HIGH_POTENCY_WARN = "This is a high potency product and may increase your risk for psychosis"
INGESTIBLE_WARN = "The intoxicating effects of this product may be delayed by two or more hours"
VAPE_WARN = "This device has not been evaluated or approved by the Food and Drug Administration."


def r2(x):
    return round(x, 2)


def metrc_tag(rng):
    body = "".join(rng.choice("0123456789ABCDEF") for _ in range(21))
    return "1A4" + body


def iso(y, m, d):
    return f"{y:04d}-{m:02d}-{d:02d}"


def us_date(isodate):
    y, m, d = isodate.split("-")
    return f"{m}/{d}/{y}"


# ----------------------------------------------------------------------------
# Per-form-factor value generation (ground truth is exact, internally consistent)
# ----------------------------------------------------------------------------
def gen_terpenes(rng, total_cap):
    """Pick 4-6 terpenes with plausible %s; return (dict field->val, dominant, total)."""
    chosen = rng.sample(TERPS, rng.randint(4, 6))
    vals = {}
    for field, _clean, _noisy in chosen:
        vals[field] = r2(rng.uniform(0.05, min(2.5, total_cap)))
    total = r2(min(total_cap, sum(vals.values()) + rng.uniform(0, 0.4)))
    dominant = max(vals, key=vals.get)
    return vals, dominant, total


def gen_flower(rng, high_potency=False, low_thc=False):
    if low_thc:
        thca = r2(rng.uniform(2, 7)); d9 = r2(rng.uniform(0.2, 1.0))
        cbd = r2(rng.uniform(6, 14))
    elif high_potency:
        thca = r2(rng.uniform(46, 52)); d9 = r2(rng.uniform(1.0, 3.0)); cbd = 0.0
    else:
        thca = r2(rng.uniform(18, 34)); d9 = r2(rng.uniform(0.3, 2.5)); cbd = 0.0
    cbg = r2(rng.uniform(0.1, 1.4))
    total_thc = r2(0.877 * thca + d9)
    total_cann = r2(total_thc + cbd + cbg + rng.uniform(0.2, 2.0))
    terps, dom, tt = gen_terpenes(rng, 6.0)
    chem = {"thca": thca, "delta9thc": d9, "cbd": cbd, "cbg": cbg,
            "totalThc": total_thc, "totalCbd": (cbd if cbd else 0.0),
            "totalCannabinoids": total_cann, "totalTerpenes": tt}
    chem.update(terps)
    weight = rng.choice(["1g", "3.5g", "7g", "14g", "28g"])
    return chem, dom, weight


def gen_vape(rng, live_resin):
    if live_resin:
        thca = r2(rng.uniform(55, 80)); d9 = r2(rng.uniform(1, 5))
    else:  # distillate: little THCA, mostly active THC
        thca = r2(rng.uniform(0, 3)); d9 = r2(rng.uniform(70, 86))
    cbg = r2(rng.uniform(0, 2.5))
    total_thc = r2(0.877 * thca + d9)
    total_cann = r2(min(99.0, total_thc + cbg + rng.uniform(0.5, 3.0)))
    terps, dom, tt = gen_terpenes(rng, 12.0)
    chem = {"thca": thca, "delta9thc": d9, "cbg": cbg, "totalThc": total_thc,
            "totalCannabinoids": total_cann, "totalTerpenes": tt}
    chem.update(terps)
    return chem, dom, rng.choice(["0.3g", "0.5g", "1g"])


def gen_concentrate(rng):
    thca = r2(rng.uniform(55, 88)); d9 = r2(rng.uniform(0.5, 5)); cbg = r2(rng.uniform(0, 3))
    total_thc = r2(0.877 * thca + d9)
    total_cann = r2(min(99.0, total_thc + cbg + rng.uniform(0.5, 4.0)))
    terps, dom, tt = gen_terpenes(rng, 15.0)
    chem = {"thca": thca, "delta9thc": d9, "cbg": cbg, "totalThc": total_thc,
            "totalCannabinoids": total_cann, "totalTerpenes": tt}
    chem.update(terps)
    return chem, dom, rng.choice(["0.5g", "1g"])


# ----------------------------------------------------------------------------
# Label text layout (clean, NJ-CRC reading order) -> then noised
# ----------------------------------------------------------------------------
def build_clean_lines(case):
    """Canonical colon:value label text in human reading order."""
    L = []
    pt = case["productType"]
    brand = case["_brand"]
    name = case["strainName"]
    if case.get("_strain_wrap") and len(name.split()) >= 2:
        # Split the strain name across two lines (canary pattern) — tests reassembly.
        parts = name.split(); head = " ".join(parts[:-1]); tail = parts[-1]
        L.append(f"{brand} - {head}" if brand != "(none)" else head)
        L.append(f"{tail} - {case['netWeight']}")
    else:
        L.append(f"{brand} - {name}" if brand != "(none)" else name)
        L.append(f"{name} - {case['netWeight']}")
    L.append(case["_formPhrase"])
    L.append(case["_cultFull"])
    L.append(case["_addr"][0]); L.append(case["_addr"][1])
    L.append(f"Phone#: {case['_addr'][2]}")
    L.append(f"License # {case['_license']}")
    L.append(case["_metrc"])
    if case.get("_decoy_batch"):
        # Batch line shaped like the real one that got mis-read as "120925% THC".
        L.append(case["_batch_code"])
    if case.get("harvestDate"):
        L.append(f"Harvest Date: {us_date(case['harvestDate'])}")
    if case.get("expirationDate"):
        L.append(f"Exp. Date: {us_date(case['expirationDate'])}")

    c = case
    if pt in ("flower", "preRoll", "vape", "concentrate"):
        if not case.get("_omit_potency"):
            L.append("Potency Analysis:")
            if case.get("_lotcode_trap"):
                # A bare 24-char Metrc tag right above THCA — bait for the model
                # to grab the digits as a cannabinoid value.
                L.append(case["_decoy_metrc"])
            if case.get("_thc_adjacency"):
                # Total THC, THCA, Δ9 jammed adjacent and out of order to bait swaps.
                if c.get("totalThc"): L.append(f"THC: {c['totalThc']}%")
                if c.get("thca"): L.append(f"THCA: {c['thca']}%")
                if c.get("delta9thc"): L.append(f"D9-THC: {c['delta9thc']}%")
            else:
                if c.get("thca"): L.append(f"THCA: {c['thca']}%")
                if c.get("delta9thc"): L.append(f"D9-THC: {c['delta9thc']}%")
                if c.get("totalThc"): L.append(f"THC: {c['totalThc']}%")
            if c.get("cbg"): L.append(f"CBG: {c['cbg']}%")
            L.append(f"CBD: {c.get('cbd', 0.0)}%")
            if c.get("totalCannabinoids"): L.append(f"Total Cannabinoids: {c['totalCannabinoids']}%")
            L.append(case["_chemotype"])
            L.append(f"Growth: {case['_growth']}")
            if not case.get("_omit_terpenes"):
                L.append("Terpene Contents -")
                order = list(TERPS)
                if case.get("_terpene_transpose"):
                    # limonene printed immediately before myrcene — bait a transpose
                    order.sort(key=lambda t: {"limonene": 0, "myrcene": 1}.get(t[0], 2))
                for field, clean, _noisy in order:
                    if field not in c or not c.get(field):
                        continue
                    if field == "pinene":
                        # Real labels print Alpha-Pinene + Beta-Pinene as TWO
                        # lines; the schema's `pinene` is their sum. Split it.
                        a = round(c[field] * 0.6, 2)
                        b = round(c[field] - a, 2)
                        L.append(f"Alpha-Pinene: {a}%")
                        L.append(f"Beta-Pinene: {b}%")
                    else:
                        L.append(f"{clean}: {c[field]}%")
                if c.get("totalTerpenes"): L.append(f"Total Terpenes: {c['totalTerpenes']}%")
    elif pt == "tincture":
        L.append(f"Total THC: {case['_mg_pkg']}mg")
        L.append(f"{case['_mg_serv']}mg THC per mL")
        L.append(INGESTIBLE_WARN)
    elif pt == "topical":
        L.append(f"Total THC: {case['_mg_pkg']}mg per container")
        L.append("For topical use only")
    else:
        # mg-dosed edible: dosing text, NEVER % (extractor must not map to %)
        L.append(f"Total THC: {case['_mg_pkg']}mg")
        L.append(f"{case['_mg_serv']}mg THC per serving")
        L.append(f"{case['_servings']} servings per package")
        L.append(INGESTIBLE_WARN)

    L.append("Store in a cool, dry place")
    for w in WARNINGS:
        L.append(w)
    if case.get("_highPotency"):
        L.insert(len(L) - len(WARNINGS), HIGH_POTENCY_WARN)
    if pt == "vape":
        L.append(VAPE_WARN)
    return [ln for ln in L if ln]


# Deterministic OCR-noise model (mirrors zips-blue-candy-rain.ocr.txt)
PCT_VARIANTS = ["%", "06", "96", "00", "9%", "%%", " %", "O/o", "0/0", "9 %"]


def noise_pct(line, rng):
    if "%" not in line:
        return line
    return re.sub(r"%", lambda _m: rng.choice(PCT_VARIANTS), line, count=1)


def noise_typos(line, rng):
    # NOTE: deliberately keep "Pinene" intact (no Alpha/Beta-Pinene mangling) so
    # the deterministic reconcilePinene() can find the two lines. Real OCR can
    # mangle it ("Betainene") but that worst case is out of scope here.
    swaps = {"Linalool": "Linaool", "Limonene": "Lim onene", "CBD": "CBO",
             "CBDA": "CBOA", "Humulene": "Humuiene",
             "BetaCaryophyllene": "BetaCaryophylene"}
    for clean, noisy in swaps.items():
        if clean in line and rng.random() < 0.5:
            line = line.replace(clean, noisy)
    if "THC:" in line and rng.random() < 0.3:
        line = line.replace("THC:", "THC9:")
    return line


def apply_noise(lines, rng, level):
    """level: 'clean' | 'light' | 'heavy' (heavy = scramble reading order)."""
    if level == "clean":
        return list(lines)
    out = []
    for ln in lines:
        ln = noise_typos(ln, rng)
        ln = noise_pct(ln, rng)
        # occasionally split a colon line so key and value land separately
        if level == "heavy" and ":" in ln and rng.random() < 0.35:
            k, _, v = ln.partition(":")
            out.append(k + ":"); out.append(v.strip())
        else:
            out.append(ln)
    if level == "heavy":
        rng.shuffle(out)  # Vision returns fragments out of order
    return out


# ----------------------------------------------------------------------------
# Ground-truth projection (only fields score.py scores)
# ----------------------------------------------------------------------------
GT_CANNABINOIDS = ["totalThc", "totalCbd", "thca", "delta9thc", "cbd", "cbg", "totalCannabinoids"]
GT_TERPENES = ["myrcene", "limonene", "linalool", "betaCaryophyllene", "pinene", "humulene", "totalTerpenes"]


def ground_truth(case, comment):
    gt = {"_comment": comment, "strainName": case["strainName"],
          "cultivator": case["_cultShort"], "productType": case["productType"],
          "netWeight": case["netWeight"]}
    if case.get("harvestDate"): gt["harvestDate"] = case["harvestDate"]
    if case.get("expirationDate"): gt["expirationDate"] = case["expirationDate"]
    # Edibles are mg-dosed: omit % cannabinoids (convention in ground-truth.json).
    if case["productType"] not in ("edible", "tincture", "topical"):
        # no_potency trap: panel absent -> assert nothing numeric (extractor must
        # return null, not hallucinate). no_terpenes: keep cannabinoids, drop terps.
        if not case.get("_omit_potency"):
            for f in GT_CANNABINOIDS:
                if f in case and case[f] is not None:
                    gt[f] = case[f]
            if not case.get("_omit_terpenes"):
                for f in GT_TERPENES:
                    if f in case and case[f] is not None:
                        gt[f] = case[f]
                if case.get("_dominant"):
                    gt["dominantTerpene"] = case["_dominant"]
    return gt


def html_label(case, lines):
    body = "\n".join(f"<div>{ln}</div>" for ln in lines)
    return f"""<!doctype html><meta charset=utf-8>
<style>
 body{{margin:0;background:#f4f1ea;font-family:'Helvetica Neue',Arial,sans-serif}}
 .label{{width:360px;padding:22px 26px;color:#1a1a1a;font-size:12px;line-height:1.5}}
 .label div:first-child{{font-size:20px;font-weight:700;margin-bottom:2px}}
 .label div:nth-child(2){{font-size:13px;color:#444;margin-bottom:10px}}
</style>
<div class="label">{body}</div>"""


# ----------------------------------------------------------------------------
# Case assembly
# ----------------------------------------------------------------------------
def make_case(rng, idx, kind, trap="base"):
    cult_full, cult_short, base_lic = rng.choice(CULTIVATORS)
    addr = rng.choice(ADDRESSES)
    strain = rng.choice(STRAINS)
    brand = rng.choice(BRANDS)
    hy, hm, hd = 2025, rng.randint(1, 12), rng.randint(1, 28)
    harvest = iso(hy, hm, hd)
    expiry = iso(2026, hm, hd)  # ~within 6 months window-ish

    case = {"strainName": strain, "_brand": brand, "_cultFull": cult_full,
            "_cultShort": cult_short, "_license": base_lic, "_addr": addr,
            "_metrc": metrc_tag(rng), "harvestDate": harvest,
            "expirationDate": expiry, "_growth": rng.choice(GROWTH)}

    high_potency = False
    if kind == "flower":
        chem, dom, wt = gen_flower(rng); case["_formPhrase"] = "Inhalable Product"
        case["productType"] = "flower"
    elif kind == "flower_hp":
        chem, dom, wt = gen_flower(rng, high_potency=True); high_potency = True
        case["_formPhrase"] = "Inhalable Product"; case["productType"] = "flower"
    elif kind == "flower_lowthc":
        chem, dom, wt = gen_flower(rng, low_thc=True); case["_formPhrase"] = "Inhalable Product"
        case["productType"] = "flower"
    elif kind == "preroll":
        chem, dom, wt = gen_flower(rng); case["_formPhrase"] = "Pre-Roll"
        case["productType"] = "preRoll"; wt = rng.choice(["0.5g", "1g"])
    elif kind == "vape_distillate":
        chem, dom, wt = gen_vape(rng, live_resin=False); case["_formPhrase"] = "Vape Cartridge"
        case["productType"] = "vape"; high_potency = True
    elif kind == "vape_liveresin":
        chem, dom, wt = gen_vape(rng, live_resin=True); case["_formPhrase"] = "Live Resin Cartridge"
        case["productType"] = "vape"; high_potency = True
    elif kind == "concentrate":
        chem, dom, wt = gen_concentrate(rng); case["_formPhrase"] = "Concentrate"
        case["productType"] = "concentrate"; high_potency = True
    elif kind in ("edible", "tincture", "topical"):
        case["productType"] = kind
        case["_formPhrase"] = {"edible": "Cannabis-Infused Gummies",
                               "tincture": "Tincture", "topical": "Topical Balm"}[kind]
        chem, dom = {}, None
        wt = {"edible": rng.choice(["28.35g", "37.7g", "38.8g"]),
              "tincture": "30mL", "topical": "50g"}[kind]
        case["_mg_pkg"] = rng.choice([100, 50]); case["_mg_serv"] = 10
        case["_servings"] = case["_mg_pkg"] // 10
    else:
        raise ValueError(kind)

    case.update(chem)
    case["_dominant"] = dom
    case["netWeight"] = wt
    case["_highPotency"] = high_potency

    # --- Adversarial trap flags (one isolated trap per case; see PLAN) ---
    case["_trap"] = trap
    case["_strain_wrap"] = trap == "strain_wrap"
    case["_lotcode_trap"] = trap == "lotcode_trap"
    case["_thc_adjacency"] = trap == "thc_adjacency"
    case["_decoy_batch"] = trap == "decoy_batch"
    case["_terpene_transpose"] = trap == "terpene_transpose"
    case["_omit_terpenes"] = trap == "no_terpenes"
    case["_omit_potency"] = trap == "no_potency"
    case["_decoy_metrc"] = metrc_tag(rng)  # second tag used by lotcode_trap
    case["_batch_code"] = f"9 - {hm:02d}{hd:02d}{(hy % 100):02d} - {strain.split()[0]}"
    if trap == "ptype_bait":
        # Strip the explicit form word so an inhalable reads as ambiguous
        # (truth keeps the real productType — tests misclassification).
        if case["productType"] in ("vape", "preRoll"):
            case["_formPhrase"] = "Inhalable Product"
    # chemotype string from the spec rules (label distractor text)
    tthc = case.get("totalThc")
    cbd = case.get("cbd", 0.0) or 0.0
    if tthc is None:
        case["_chemotype"] = ""
    elif (cbd == 0 or tthc / max(cbd, 0.01) > 5) and tthc >= 15:
        case["_chemotype"] = "High THC, Low CBD"
    elif tthc <= 5:
        case["_chemotype"] = "Low THC, High CBD"
    else:
        case["_chemotype"] = "Moderate THC, Moderate CBD"
    return case


# Generation plan: form factors × adversarial traps. Each case isolates ONE trap
# (tagged in the slug, so `score.py --filter <trap>` slices accuracy per trap).
POTENCY_KINDS = ["flower", "flower_hp", "flower_lowthc", "preroll",
                 "vape_distillate", "vape_liveresin", "concentrate"]
MG_KINDS = ["edible", "tincture", "topical"]
# base = no trap (heavy OCR scramble); the rest isolate a single failure mode.
POTENCY_TRAPS = ["base", "strain_wrap", "lotcode_trap", "thc_adjacency",
                 "decoy_batch", "terpene_transpose", "no_terpenes", "no_potency", "ptype_bait"]
MG_TRAPS = ["base", "strain_wrap", "ptype_bait", "decoy_batch"]


def build_plan(seed):
    """Deterministic (kind, trap) plan; shuffled so any --count prefix stays varied."""
    plan = [(k, t) for k in POTENCY_KINDS for t in POTENCY_TRAPS]
    plan += [(k, t) for k in MG_KINDS for t in MG_TRAPS]
    random.Random(seed * 7919 + 1).shuffle(plan)  # plan rng independent of value rng
    return plan


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--count", type=int, default=60)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    plan = build_plan(args.seed)

    # Wipe stale fixtures so a regen with a different count/seed doesn't leave orphans.
    if os.path.isdir(OUT_DIR):
        for f in os.listdir(OUT_DIR):
            if f.startswith("syn-") and f.endswith((".ocr.txt", ".html", ".png")):
                os.remove(os.path.join(OUT_DIR, f))
    os.makedirs(OUT_DIR, exist_ok=True)

    truth = {"_conventions": {
        "_doc": "AUTO-GENERATED by tests/generator/generate.py — do not hand-edit; "
                "regenerate with `python3 tests/generator/generate.py`. Merged with "
                "ground-truth.json by score.py. Keyed by synthetic fixture filename. "
                "Slug encodes the adversarial trap: score.py --filter <trap> slices it.",
        "seed": args.seed, "count": args.count}}

    n = min(args.count, len(plan))
    trap_counts = {}
    for i in range(n):
        kind, trap = plan[i]
        case = make_case(rng, i, kind, trap)
        trap_counts[trap] = trap_counts.get(trap, 0) + 1
        slug = f"syn-{i:03d}-{case['productType']}-{trap}"
        clean_lines = build_clean_lines(case)

        # TEXT fixture: base potency types get the full reading-order scramble;
        # trap cases use light noise so the isolated trap is the main challenge.
        if trap == "base" and case["productType"] in ("flower", "preRoll", "vape", "concentrate"):
            level = "heavy"
        else:
            level = "light"
        noisy = apply_noise(clean_lines, rng, level)
        txt_name = f"{slug}.ocr.txt"
        with open(os.path.join(OUT_DIR, txt_name), "w") as f:
            f.write("\n".join(noisy) + "\n")
        truth[txt_name] = ground_truth(case, f"{kind} / trap={trap} / OCR-noise={level} / seed {args.seed}")

        # IMAGE fixture: clean HTML rendered to <slug>.png by render.sh.
        with open(os.path.join(OUT_DIR, f"{slug}.html"), "w") as f:
            f.write(html_label(case, clean_lines))
        truth[f"{slug}.png"] = ground_truth(case, f"{kind} / trap={trap} / rendered image / seed {args.seed}")

    with open(GT_OUT, "w") as f:
        json.dump(truth, f, indent=2)
    print(f"Generated {n} cases -> {OUT_DIR}")
    print(f"  {n} .ocr.txt (noised) + {n} .html (clean) + {GT_OUT}")
    print(f"  ground-truth entries: {len([k for k in truth if not k.startswith('_')])}")
    print(f"  traps: " + ", ".join(f"{t}×{c}" for t, c in sorted(trap_counts.items())))


if __name__ == "__main__":
    main()
