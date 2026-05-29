#!/usr/bin/env python3
"""Claude Code status-line renderer for the HighNotes harness.

Wired in via `.claude/settings.local.json`:

    "statusLine": { "type": "command",
                    "command": "python3 /abs/path/tests/harness/statusline.py",
                    "refreshInterval": 1 }

`refreshInterval: 1` makes Claude Code re-run this every second even while the
session is idle/blocked on a long Bash command or Monitor — so the bar stays live
during a `swift run HighNotesHarness` instead of freezing until the next turn.

Claude Code pipes session JSON on stdin (model, workspace, …); we use it for the
context line. The progress line is read from the harness's `.progress.json`
(same file `progress.py watch` renders) and only appears while a run is fresh.
"""
import json, os, sys, time, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
PROGRESS_FILE = os.environ.get("HN_PROGRESS_FILE") or os.path.join(HERE, ".progress.json")
HIDE_DONE_AFTER = 300   # seconds — stop showing a finished run's line after this
STALE_AFTER = 120       # seconds without a write while "running" → flag it

# ANSI
DIM = "\033[2m"; BOLD = "\033[1m"; RESET = "\033[0m"
GREEN = "\033[32m"; CYAN = "\033[36m"; YELLOW = "\033[33m"; GREY = "\033[90m"


def read_stdin_json():
    try:
        return json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return {}


def git_branch():
    try:
        out = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"],
                             cwd=HERE, capture_output=True, text=True, timeout=1)
        b = out.stdout.strip()
        return b or None
    except Exception:
        return None


def context_line(ctx):
    model = (ctx.get("model") or {}).get("display_name") or (ctx.get("model") or {}).get("id") or "Claude"
    ws = ctx.get("workspace") or {}
    cwd = ws.get("current_dir") or ctx.get("cwd") or os.getcwd()
    dirname = os.path.basename(cwd.rstrip("/")) or cwd
    parts = [f"{BOLD}{dirname}{RESET}"]
    b = git_branch()
    if b:
        parts.append(f"{GREY}⎇ {b}{RESET}")
    parts.append(f"{DIM}{model}{RESET}")
    return f"{DIM} · {RESET}".join(parts)


def fmt_dur(s):
    if s is None or s < 0:
        return "—"
    s = int(s)
    if s < 60:
        return f"{s}s"
    m, s = divmod(s, 60)
    return f"{m}m" if m < 60 else f"{m // 60}h{m % 60:02d}m"


def primary_bar(bars, now):
    """The bar that best represents 'where the run is': the most recently
    updated one that isn't finished; else the most recently updated overall."""
    if not bars:
        return None, None
    unfinished = {k: v for k, v in bars.items()
                  if (v.get("total") or 0) == 0 or (v.get("current", 0) < v.get("total", 0))}
    pool = unfinished or bars
    name = max(pool, key=lambda k: pool[k].get("updated_at", 0))
    return name, pool[name]


def progress_line(width):
    try:
        with open(PROGRESS_FILE) as f:
            st = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, ValueError):
        return None
    now = time.time()
    status = st.get("status", "running")
    updated = st.get("updated_at", 0)
    age = now - updated
    if status == "done" and age > HIDE_DONE_AFTER:
        return None  # finished a while ago — drop the line entirely

    name, bar = primary_bar(st.get("bars") or {}, now)
    if not bar:
        return None
    cur = bar.get("current", 0) or 0
    tot = bar.get("total", 0) or 0
    frac = (cur / tot) if tot else 0.0
    started = bar.get("started_at")
    elapsed = (now - started) if started else None
    eta = elapsed * (tot - cur) / cur if (started and cur > 0 and tot > cur and elapsed) else None

    barw = max(8, min(28, width - 46))
    filled = int(round(frac * barw))
    color = CYAN if status == "done" else GREEN
    blocks = f"{color}{'█' * filled}{GREY}{'░' * (barw - filled)}{RESET}"
    head = f"{CYAN}✅{RESET}" if status == "done" else f"{GREEN}▶{RESET}"
    seg = f"{head} {BOLD}{name}{RESET} {blocks} {cur}/{tot} {frac*100:.0f}%"
    if status != "done" and eta is not None:
        seg += f" {DIM}eta {fmt_dur(eta)}{RESET}"
    if status == "running" and age > STALE_AFTER:
        seg += f" {YELLOW}⚠ stalled?{RESET}"
    note = st.get("note") or ""
    if note and width > 80:
        seg += f"  {GREY}{note[:width-len(seg)]}{RESET}"
    return seg


def main():
    ctx = read_stdin_json()
    try:
        width = int(os.environ.get("COLUMNS") or 100)
    except ValueError:
        width = 100
    lines = [context_line(ctx)]
    p = progress_line(width)
    if p:
        lines.append(p)
    sys.stdout.write("\n".join(lines))


if __name__ == "__main__":
    main()
