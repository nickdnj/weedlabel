# App Store Submission — status (2026-05-31)

Pocketbud v1.0, bundle `com.demarconet.weedlabel`, App Store Connect app **"Pocketbud: AI Budtender"**.

## ✅ Done (automated)
- **Build 4** uploaded + **VALID** — the App Store binary: Release config, **no** `#if BETA`
  tester-feedback, **no** tip jar (TIPJAR gated to Debug). Verified: 0 data-collection strings.
  (Builds 1–3 on TestFlight; build 3 = Beta config for beta testers.)
- **Listing metadata** pushed: name, subtitle, description, keywords, promo, categories
  (Lifestyle / Reference), App Review notes (cannabis-compliance pre-empt).
- **Screenshots** uploaded (6.9", 1320×2868, showing the current icon/mark).
- **Privacy + Support pages** hosted on GitHub Pages and set as the listing URLs:
  - https://nickdnj.github.io/weedlabel/legal/privacy.html
  - https://nickdnj.github.io/weedlabel/legal/support.html
- **App Review contact**: Nick DeMarco / vistter2@gmail.com / +1 732 542 5165.
- Encryption compliance: `ITSAppUsesNonExemptEncryption = NO` (auto-clears the prompt).
- Codesigning now authorized for hands-free builds (`fastlane release` / `beta`).

## 🙋 Remaining — App Store Connect web (only you can do these)
1. **App Privacy → "Data Not Collected"** — complete the privacy questionnaire; declare no data
   collected across the board. (This is the headline differentiator — verify no SDK contradicts it.)
2. **Age rating** questionnaire → answer cannabis references honestly → **17+**.
3. **Pricing and Availability → Free**.
4. **Version 1.0 → Build** section → **select build 4**.
5. **Add for Review → Submit**.

## Notes
- Tip jar is shipped **disabled** (gated to Debug) to skip the Paid Apps agreement; add tips in a
  later update (create the 3 consumables + sign agreements/tax/banking first).
- For a new build later: bump `CURRENT_PROJECT_VERSION` in `project.yml`, then
  `fastlane release` (App Store) or `fastlane beta` (TestFlight). Both run hands-free now.
- Cannabis review risk is low (informational/journaling, no sale/delivery) — the review notes
  state this plainly per `docs/APP-STORE-CHECKLIST.md` §6.
