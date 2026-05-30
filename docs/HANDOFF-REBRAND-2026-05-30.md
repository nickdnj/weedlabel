# Handoff: Rebranding (2026-05-30)

For the agent picking up the **rebrand**. The extraction/capture work is done and
stable — this handoff is scoped to renaming + reskinning. Read this top to bottom
before touching anything, then read `DESIGN.md` (the design source of truth).

`main` @ `88267d2` — clean tree, pushed, builds, deployed to the user's iPhone 16
Pro. 287 tests; the only failures are 5 pre-existing camera-flow tests in
`ScanModelTests` (broken by the AVFoundation capture rewrite, unrelated — verified
identical at base commit `166fac3`). Don't be alarmed by them.

## TL;DR — what's being asked

Apply the rebrand. The product name has churned: the **code currently ships
"HighNotes"** (`Brand.swift`), but **`DESIGN.md` + `CLAUDE.md` say the leading
name is "Pocketbud"** with a green-primary / amber-accent look that **supersedes**
the green→violet gradient still in `Brand.swift`/`OnboardingView.swift`. **First
job: confirm the final name + palette with the user, then make the code match
`DESIGN.md`.**

## ⚠️ The naming conflict (resolve this first)

| Surface | Current value | Notes |
|---|---|---|
| `Brand.swift` `name` | **"HighNotes"** | tagline "Your AI budtender" |
| `Brand.swift` palette | green→teal→violet gradient | **superseded by DESIGN.md** (green/amber) |
| `project.yml` `INFOPLIST_KEY_CFBundleDisplayName` | **"HighNotes"** | the on-device app name |
| `DESIGN.md` / `CLAUDE.md` | **"Pocketbud"** | "Your AI budtender. Lives in your pocket…" |
| Repo / Xcode target / scheme | `weedlabel` | original codename |
| Bundle id | `com.demarconet.weedlabel` | load-bearing — see below |

So three names are live at once (weedlabel / HighNotes / Pocketbud). Get the user
to pick one, then sweep.

## Where branding lives (the reskin surface)

- **`weedlabel/Brand.swift`** — THE central token file. `name`, `tagline`,
  `green`/`teal`/`violet`, `gradient`, `backgroundWash`. Comment at top literally
  says "so a rebrand is one file." Most of the string/color rebrand happens here.
  Note: it still encodes the OLD green→violet "bold-playful" direction; DESIGN.md
  wants green-primary / amber-accent — update the tokens, not just the name.
- **`DESIGN.md`** (repo root) — source of truth: palette, SF Pro Rounded type,
  dark-green-ink surfaces, the three-privacy-pillars pattern, app icon spec.
  **Do not deviate from it without explicit user approval.**
- **App icon** — live: `weedlabel/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.
  Master/source: `docs/branding/icon-master-1024.png`, `pocketbud-icon.svg`
  (white-shirt pocket protector + green leaf + lit joint). Mockups:
  `docs/branding/showcase.html`, `screens.png`.
- **Brand strings in views** (grep `HighNotes`): `AboutView`, `TipJarView`,
  `LogBookView`, `OnboardingView`, `LogEntryDetailView`, `ContentView`,
  `ScanModel`, `Services/TipJar.swift`, `Services/LogStore.swift`. Prefer routing
  these through `Brand.name` rather than re-hardcoding the new name.
- **Docs** also say "HighNotes" throughout (`PRD-v1`, `SAD-v1`, `UXD-v1`,
  `APP-STORE-CHECKLIST`, `OPEN-ISSUES`, etc.) — sweep for consistency, lower
  priority than the app itself.

## 🚫 Rename-risk matrix — what's safe vs what breaks things

**Safe / low-risk (do these):**
- `Brand.swift` `name`/`tagline`/palette.
- `project.yml` `INFOPLIST_KEY_CFBundleDisplayName` (the visible app name) — change
  freely; it's independent of the bundle id.
- App icon asset swap.
- View/doc string sweeps.

**High-risk (only with explicit user sign-off — the user has deferred these):**
- **Bundle id `com.demarconet.weedlabel`** — changing it orphans the StoreKit IAP
  product IDs `com.demarconet.weedlabel.tip.{small,medium,large}`
  (`Services/TipJar.swift`), the `TipJar.storekit` config, and any TestFlight/App
  Store Connect record. Leave the bundle id alone unless the user explicitly wants
  a new App Store identity.
- **Repo / Xcode target / scheme rename (`weedlabel`)** — cosmetic but touches
  `project.yml` `name:`, the target, `*Tests` target, scheme, derived paths, and
  every build command in the docs. The user has repeatedly **deferred** this.

The display name and the bundle id are decoupled — you can ship "Pocketbud" to the
home screen without touching `com.demarconet.weedlabel`. Recommend exactly that.

## Build / deploy / test (non-obvious — keep these)

- **Build with the Xcode toolchain**, or `FoundationModels` is missing:
  `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- **`xcodegen generate` wipes `DEVELOPMENT_TEAM`** unless it's in `project.yml`
  (it is: `5VPR237YHV`). New files / target changes need a regen.
- SourceKit in this editor shows false `No such module 'UIKit'/'FoundationModels'`
  errors (CLT toolchain). Ignore; trust `xcodebuild`.
- Device build/install/launch (Nick's iPhone 16 Pro):
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  DEV=48396B42-5E08-594F-AB72-FB4B3228A6C4
  xcodebuild -project weedlabel.xcodeproj -scheme weedlabel -configuration Debug \
    -destination "platform=iOS,id=$DEV" -derivedDataPath /tmp/wlbuild2 \
    -allowProvisioningUpdates build
  APP=/tmp/wlbuild2/Build/Products/Debug-iphoneos/weedlabel.app
  xcrun devicectl device install app --device $DEV "$APP"
  xcrun devicectl device process launch --device $DEV com.demarconet.weedlabel
  ```
- Tests (simulator; FM works in iOS 26 sim, Vision OCR does not):
  ```bash
  xcodebuild -project weedlabel.xcodeproj -scheme weedlabel \
    -destination 'platform=iOS Simulator,id=DBF4F03C-6D81-40BE-B4F8-D7592F701F2A' test
  ```
- Pushing to `main` requires explicit user authorization each time.

## ✋ Do NOT touch (stable, tested — not part of the rebrand)

The extraction/capture pipeline is finished and verified on device this session.
Leave it unless the user asks:
- `Services/StaticImageOCR.swift` (orientation scoring), `Services/LabelIsolator.swift`,
  `Views/LabelCamera.swift` (capture engine).
- `Models/CannabisLabel.swift` reconcilers (`reconcileCannabinoids`, clustered-row
  pairing, `fixImpossibleThc`), `Services/StrainNameFixer.swift` (candidate logic).
- The Phase 1 (strain-name) + Phase 2 (cannabinoid) **pick-from-label correction
  UI** in `PostScanView` / `ContentView` `ParsedFieldsList`.

## State of the product (so you know what you're reskinning)

Fully on-device pipeline: AVFoundation capture → orientation-correct OCR → two-pass
Foundation Models extraction → deterministic reconcilers → grounded AI summary →
Log Book (local JSON). The 180° rotation blocker (OI-0) is **resolved**; potency
column-desyncs and the strain-name long tail are handled deterministically AND, for
whatever slips through, via **tap-to-pick correction lists read from the label**
(the user picks the right name/number — no typing). See `docs/OPEN-ISSUES.md` for
remaining quality residuals and `docs/SPEC-confidence-check.md` for the proposed
next feature (per-field confidence → auto-open the pickers) — **not yet built**,
fine to leave for after the rebrand.

## Suggested rebrand order

1. Confirm final name + that DESIGN.md's green/amber palette is the target.
2. `Brand.swift`: name, tagline, palette/gradient to match DESIGN.md.
3. `project.yml` `INFOPLIST_KEY_CFBundleDisplayName`; `xcodegen generate`; build.
4. Swap the app icon asset (Pocketbud icon already in `docs/branding/`).
5. Reskin views that hardcode the old look to `Brand` tokens; sweep stray
   "HighNotes" strings → `Brand.name`.
6. Doc sweep (lower priority).
7. Leave bundle id / repo / target rename unless the user explicitly green-lights.
