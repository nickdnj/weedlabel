#!/usr/bin/env python3
"""Realtime progress for the HighNotes harness.

A small shared JSON state file (default: `tests/harness/.progress.json`) holds one
or more named *bars* (Overall / OCR / Apple / Claude / score …). Three writers
cooperate through it:

  - the Swift harness writes its OCR / Apple / Claude bars per-label as it runs
    (see ProgressReporter.swift) — so the bar reflects ACTUAL work, not a guess;
  - an orchestrating agent drives the surrounding steps with this CLI's
    start/set/note/done subcommands;
  - `watch` renders a live, redrawing bar in a SEPARATE terminal.

Writes are atomic (temp file + rename), so `watch` never sees a half-written file.

Typical agent flow (the harness fills OCR/Apple/Claude on its own):
    python3 progress.py start --phase Overall --total 3 --note "OCR+extract → score → gate"
    python3 progress.py set   --phase Overall --current 1 --total 3 --note "running harness"
    DEVELOPER_DIR=... swift run HighNotesHarness            # writes OCR/Apple/Claude bars
    python3 progress.py set   --phase score   --current 1 --total 1 --note "scoring run.json"
    python3 score.py results/<run>/run.json
    python3 progress.py done

And in your OWN terminal, to watch:
    python3 progress.py watch
"""
import argparse, json, os, sys, time, shutil

DEFAULT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".progress.json")
STALE_AFTER = 30.0  # seconds without an update → flag a bar as possibly stalled
PHASE_ORDER = ["Overall", "OCR", "Apple", "Claude", "score"]


def state_path(args):
    return args.file or os.environ.get("HN_PROGRESS_FILE") or DEFAULT_FILE


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, ValueError):
        return None


def save(path, state):
    state["updated_at"] = time.time()
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, path)  # atomic on the same filesystem


def update_bar(path, phase, current, total, label, note, status="running"):
    st = load(path) or {"status": "running", "note": "", "bars": {}}
    st.setdefault("bars", {})
    if note is not None:
        st["note"] = note
    if phase is not None:
        now = time.time()
        bar = st["bars"].get(phase, {})
        # Reset the clock when a bar (re)starts or its total changes, so ETA is sane.
        if "started_at" not in bar or bar.get("total") != total or (current or 0) < bar.get("current", 0):
            bar["started_at"] = now
        bar["current"] = current if current is not None else bar.get("current", 0)
        bar["total"] = total if total is not None else bar.get("total", 0)
        bar["updated_at"] = now
        if label is not None:
            bar["label"] = label
        st["bars"][phase] = bar
    st["status"] = status
    save(path, st)
    return st


# ── rendering ──────────────────────────────────────────────────────────────

def fmt_dur(s):
    if s is None or s < 0:
        return "  —  "
    s = int(s)
    if s < 60:
        return f"{s}s"
    m, s = divmod(s, 60)
    if m < 60:
        return f"{m}m{s:02d}s"
    h, m = divmod(m, 60)
    return f"{h}h{m:02d}m"


def order_key(name):
    return (PHASE_ORDER.index(name) if name in PHASE_ORDER else len(PHASE_ORDER), name)


def bar_line(name, bar, width, now):
    cur = bar.get("current", 0) or 0
    tot = bar.get("total", 0) or 0
    frac = (cur / tot) if tot else 0.0
    started = bar.get("started_at")
    updated = bar.get("updated_at")
    elapsed = (now - started) if started else None
    eta = None
    if started and cur > 0 and tot > cur and elapsed and elapsed > 0:
        eta = elapsed * (tot - cur) / cur
    barw = max(10, width - 52)
    filled = int(round(frac * barw))
    blocks = "█" * filled + "░" * (barw - filled)
    pct = f"{frac * 100:4.0f}%"
    tail = f"{cur:>3}/{tot:<3} {pct}  e{fmt_dur(elapsed)} eta {fmt_dur(eta)}"
    line = f"{name:<8}[{blocks}] {tail}"
    if updated and (now - updated) > STALE_AFTER and frac < 1.0:
        line += "  ⚠ stalled?"
    label = bar.get("label")
    if label:
        line += f"  {label}"
    return line


def render(state, width):
    now = time.time()
    if not state:
        return "⏳ waiting for progress — no .progress.json yet…"
    lines = []
    note = state.get("note") or ""
    status = state.get("status", "running")
    head = "✅ done" if status == "done" else "▶ running"
    if note:
        head += f" — {note}"
    lines.append(head)
    lines.append("")
    bars = state.get("bars") or {}
    if not bars:
        lines.append("(no bars yet)")
    for name in sorted(bars, key=order_key):
        lines.append(bar_line(name, bars[name], width, now))
    age = now - state.get("updated_at", now)
    lines.append("")
    lines.append(f"updated {fmt_dur(age)} ago   (Ctrl-C to stop watching)")
    return "\n".join(lines)


def watch(path, interval):
    last_done = False
    try:
        while True:
            state = load(path)
            width = shutil.get_terminal_size((100, 24)).columns
            sys.stdout.write("\033[H\033[J")  # cursor home + clear screen
            sys.stdout.write(render(state, width) + "\n")
            sys.stdout.flush()
            if state and state.get("status") == "done":
                if last_done:  # show the final frame one extra beat, then exit
                    break
                last_done = True
            else:
                last_done = False
            time.sleep(interval)
    except KeyboardInterrupt:
        sys.stdout.write("\n")


# ── CLI ──────────────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description="Realtime progress for the HighNotes harness.")
    p.add_argument("--file", help=f"state file (default: {DEFAULT_FILE} or $HN_PROGRESS_FILE)")
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_setters(sp):
        sp.add_argument("--phase", help="bar name (Overall/OCR/Apple/Claude/score/…)")
        sp.add_argument("--current", type=int)
        sp.add_argument("--total", type=int)
        sp.add_argument("--label", help="optional per-bar detail (e.g. current label)")
        sp.add_argument("--note", help="free-text status shown above the bars")

    sp = sub.add_parser("start", help="reset state and (optionally) seed one bar")
    add_setters(sp)

    sp = sub.add_parser("set", help="update one bar (creates it if absent)")
    add_setters(sp)

    sp = sub.add_parser("note", help="set the free-text note above the bars")
    sp.add_argument("text")

    sub.add_parser("done", help="mark the whole run done")
    sub.add_parser("clear", help="delete the state file")

    sp = sub.add_parser("watch", help="live-render the bars in this terminal")
    sp.add_argument("--interval", type=float, default=0.25, help="redraw period in seconds (default 0.25)")

    args = p.parse_args()
    path = state_path(args)

    if args.cmd == "start":
        st = {"status": "running", "note": args.note or "", "bars": {}}
        save(path, st)
        if args.phase:
            update_bar(path, args.phase, args.current or 0, args.total or 0, args.label, args.note)
    elif args.cmd == "set":
        update_bar(path, args.phase, args.current, args.total, args.label, args.note)
    elif args.cmd == "note":
        st = load(path) or {"status": "running", "bars": {}}
        st["note"] = args.text
        save(path, st)
    elif args.cmd == "done":
        st = load(path) or {"status": "running", "bars": {}}
        st["status"] = "done"
        save(path, st)
    elif args.cmd == "clear":
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    elif args.cmd == "watch":
        watch(path, args.interval)


if __name__ == "__main__":
    main()
