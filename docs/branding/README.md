# Pocketbud branding assets

Brand source of truth is **`/DESIGN.md`** (repo root). This folder holds the visual artifacts.

## Current (green-primary brand, 2026-05-30)
- **`showcase.html`** — the live, editable brand showcase. Open in a browser. Hero + privacy pillars, app icon, all four screens, palette, type. Self-contained, no build step. Everything here is hand-built HTML/CSS (real text/fonts/hex), so it's accurate — not AI art.
- **`pocketbud-icon.svg`** — canonical app-icon source, 1024×1024, opaque. Edit this, then re-export the master.
- **`icon-master-1024.png`** — rendered App Store master (square, no alpha; Apple rounds it).
- **`icon-final.html`** — icon at sizes + export instructions.
- **`showcase-full.png`**, **`hero.png`**, **`icon-large.png`**, **`icon-sizes-home.png`**, **`screens.png`** — static snapshots of the showcase (for quick reference / sharing).

## To re-render snapshots
Open `showcase.html` in a browser and screenshot, or use the gstack `browse` binary:
```
B=~/.claude/skills/gstack/browse/dist/browse
$B viewport 1200x1640 --scale 2
$B goto "file://$(pwd)/showcase.html"   # copy to /tmp first if browse refuses the path
$B screenshot screens.png --selector .phones
```

## explorations/
Superseded amber-era mockups (first-pass screen directions A/B/C, early leaf icon concepts, amber-tile icon). Kept for history; **not** the current brand. Ignore for implementation.

## App Store
Icon + screenshot + metadata + privacy-label requirements are in **`/docs/APP-STORE-CHECKLIST.md`**.
