# App Store Submission Checklist — Pocketbud

Everything needed to ship Pocketbud to the App Store. **The cannabis-specific items (★) are where most apps get rejected — read those carefully.** Pocketbud is an *informational/journaling* app that never sells, delivers, or facilitates purchase of cannabis, which keeps it in the low-risk lane.

## 0. Account & legal (one-time)
- [ ] **Apple Developer Program — $99/yr** (required for TestFlight *and* App Store; the free path is Xcode sideload only).
- [ ] App Store Connect agreements + tax + banking (only needed because of the tip-jar IAPs).
- [ ] Privacy Policy URL (**required field**) — host a simple page. Can be brutally short: "Pocketbud collects no data. Everything stays on your device."
- [ ] Support URL (required) and optional Marketing URL.

## 1. App icon
- [ ] **1024×1024 px PNG**, sRGB or P3, **no alpha / no transparency, flattened, square** (Apple rounds the corners — don't pre-round). Export the master from `docs/branding/icon-final.html`.
- [ ] Drop the 1024 into the Xcode asset catalog (single-size "App Store" slot; Xcode 14+ generates the rest).
- [ ] No text-heavy icon, no "beta" badges, no Apple hardware imagery.

## 2. Screenshots (per required display size, up to 10 each)
- [ ] **6.9" iPhone** (16/17 Pro Max) — **1320×2868** (or 1290×2796). **Required.**
- [ ] **6.5" iPhone** (older Pro Max) — 1242×2688 / 1284×2778. Recommended.
- [ ] iPad screenshots only if you ship iPad (13" 2064×2752) — skip if iPhone-only.
- [ ] First 2–3 screenshots carry the pitch: lead with the **Scan → Results** flow and the **"Everything stays on your phone"** privacy promise. Use the `docs/branding/` mockups as the basis.
- [ ] Optional: App Preview video (15–30s).

## 3. Metadata (character limits)
- [ ] **Name** ≤ 30 — `Pocketbud`
- [ ] **Subtitle** ≤ 30 — e.g. `Your private AI budtender`
- [ ] **Promotional text** ≤ 170 (updatable without review)
- [ ] **Description** ≤ 4000 — lead with privacy + on-device AI.
- [ ] **Keywords** ≤ 100 chars total, comma-separated — e.g. `cannabis,weed,label,THC,terpene,scanner,journal,private,budtender,strain`
- [ ] **Primary category:** Lifestyle (alt: Health & Fitness / Reference). **Secondary:** Reference.

## 4. ★ Age rating
- [ ] Complete the rating questionnaire honestly → cannabis references put this at **17+** ("Frequent/Intense — Drug Use or References"). Expect and accept 17+.

## 5. ★ App Privacy "nutrition label"
- [ ] In App Store Connect → App Privacy, declare **"Data Not Collected"** across the board. This is Pocketbud's biggest differentiator — it shows as **"No Data Collected"** on the product page. Make sure no analytics/crash SDK silently breaks this claim.
- [ ] Privacy Policy URL must agree with the label (no data collected).

## 6. ★ Cannabis review-guideline compliance (Guideline 1.4.3 + 1.1.6)
- [ ] Confirm the app **does not** facilitate sale/delivery of cannabis (Pocketbud doesn't — it reads labels). If it ever did, it would need geo-restriction to legal regions + licensed-retailer gating.
- [ ] Add a short in-app + listing disclaimer: *"For informational and educational use. Not medical advice. 21+."*
- [ ] In **App Review notes**, state plainly: "Informational/journaling app. Reads product labels on-device. Does not sell, deliver, or facilitate purchase of cannabis. No user data leaves the device." This pre-empts the common reviewer concern.
- [ ] Avoid promotional copy that reads as *encouraging consumption* (guideline tripwire). Frame as *understand what you're consuming*.

## 7. ★ Tip jar / IAP (the only thing that leaves the device, Apple-mediated)
- [ ] Create 3 **consumable** IAPs in App Store Connect: `com.demarconet.weedlabel.tip.{small,medium,large}` (update bundle prefix if the bundle ID changes with the rename).
- [ ] Localized display name + price tier for each; review screenshot of the tip-jar screen.
- [ ] Tips must stay pure goodwill — never gate features (guideline 3.1.1). Current "never required" copy is correct.

## 8. Build & technical
- [ ] Deployment target **iOS 26.0+** (Foundation Models `@Generable` requirement).
- [ ] `NSCameraUsageDescription` in Info.plist — e.g. "Pocketbud uses the camera to read cannabis labels on your device."
- [ ] Required device capability if appropriate; declare camera.
- [ ] **Encryption / export compliance:** uses only standard OS encryption → set `ITSAppUsesNonExemptEncryption = NO` in Info.plist to skip the prompt.
- [ ] Launch screen, Dynamic Type, light + dark mode all pass.
- [ ] `DEVELOPMENT_TEAM: 5VPR237YHV` set in project.yml (xcodegen wipes it otherwise).
- [ ] Update display name / bundle ID to Pocketbud branding when the repo rename happens.

## 9. Pre-submit smoke test
- [ ] TestFlight internal build installs and runs on a real AI-capable device (iPhone 15 Pro / 16 / 17).
- [ ] Scan → result → log book → tip purchase (sandbox) all work.
- [ ] No analytics/network calls on the wire (verify the "no data" claim with a proxy).
- [ ] ★ **Beta feedback compiled out:** the App Store archive uses the **Release** config (NOT `Beta`/`weedlabel-Beta`), so the `#if BETA` tester-feedback feature is absent. Confirm with `strings <app-binary> | grep -c "scan feedback"` → must be **0**. (TestFlight uploads use the `weedlabel-Beta` scheme; the final submission uses `weedlabel`/Release.) See `docs/SPEC-beta-feedback.md`.
