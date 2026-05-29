#!/bin/zsh
# Render every synthetic <slug>.html label to <slug>.png (the IMAGE-level
# fixtures that exercise the full pipeline incl. real Vision OCR).
#
# Uses the gstack headless browser (Chromium) for crisp 2x text rendering.
# Run after `python3 generate.py`. Idempotent.
#
# Usage: zsh tests/generator/render.sh
set -e
HERE=${0:A:h}
SYN="$HERE/../../assets/validation/synthetic"

# Resolve the gstack browse binary (repo-local team install or per-user).
ROOT=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)
B=""
[ -n "$ROOT" ] && [ -x "$ROOT/.claude/skills/gstack/browse/dist/browse" ] && B="$ROOT/.claude/skills/gstack/browse/dist/browse"
[ -z "$B" ] && [ -x "$HOME/.claude/skills/gstack/browse/dist/browse" ] && B="$HOME/.claude/skills/gstack/browse/dist/browse"
if [ -z "$B" ]; then
  echo "ERROR: gstack browse binary not found. Render <slug>.html with any headless"
  echo "Chromium (e.g. 'chrome --headless --screenshot') instead." >&2
  exit 1
fi

"$B" viewport 480x1600 --scale 2 >/dev/null 2>&1 || true
count=0
for h in "$SYN"/syn-*.html; do
  png="${h%.html}.png"
  "$B" goto "file://$h" >/dev/null 2>&1
  sleep 0.4
  "$B" screenshot --selector .label "$png" >/dev/null 2>&1
  count=$((count+1))
done
echo "Rendered $count label image(s) -> $SYN"
