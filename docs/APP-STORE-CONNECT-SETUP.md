# App Store Connect — setup you can do from your phone

What you can knock out in mobile Safari / the App Store Connect app **while you're out**, so the
only thing left for the Mac is the build upload (which I've scripted — see `fastlane/README.md`).

> Bundle ID: `com.demarconet.weedlabel` · Team: `5VPR237YHV` · App name: **Pocketbud**

---

## ① Create the App Store Connect API key (do this first — highest leverage)
This unblocks fully-automated, 2FA-free uploads from the Mac.

1. Mobile Safari → **appstoreconnect.com** → **Users and Access** → **Integrations** tab →
   **App Store Connect API**.
2. Tap **+**, name it `pocketbud-ci`, access **App Manager** (or Admin).
3. Note the **Key ID** and the **Issuer ID** (top of the keys list).
4. The **`.p8`** file downloads only once — do it when you're back at the Mac (or AirDrop it).
   Save it at `~/.appstoreconnect/AuthKey_<KEYID>.p8`.

Send me / jot the Key ID + Issuer ID and I'll wire them into the env for `fastlane beta`.

---

## ② Register the App ID (if not already)
developer.apple.com → **Certificates, IDs & Profiles** → **Identifiers** → **+** →
**App IDs** → **App** → Bundle ID **Explicit** = `com.demarconet.weedlabel`. Capabilities: defaults
are fine (no push, no special entitlements). Description: `Pocketbud`.

> Or skip — the first `fastlane beta` can create this for you.

---

## ③ Create the app record
appstoreconnect.com → **Apps** → **+** → **New App**:
- Platform **iOS**, Name **Pocketbud**, Primary language **English (U.S.)**
- Bundle ID `com.demarconet.weedlabel`, SKU `pocketbud` (any unique string)
- Full access

---

## ④ Things to set in the listing (can pre-fill from phone)
Most of this `fastlane metadata` will push for you from the Mac, but you can do it by hand too —
all the text is in `docs/APP-STORE-LISTING.md`:
- **Subtitle:** Your private AI budtender
- **Category:** Lifestyle (secondary: Reference)
- **Age rating** questionnaire → answer cannabis references honestly → expect **17+**
- **App Privacy:** choose **Data Not Collected** across the board (this one is web/app only — not
  automated). Privacy Policy URL required; Support URL required (host `docs/legal/*.html` first).

---

## ⑤ TestFlight (after the first build is uploaded from the Mac)
- **Internal Testing** group → add testers by Apple ID (up to 100, no review) → start here.
- Set **What to Test** (text in `docs/TESTFLIGHT-RECRUITING.md` §3).
- For a **public link** (external testing) you must pass **Beta App Review** first — paste the
  App Review notes from `docs/APP-STORE-LISTING.md`.

---

## What's left for the Mac (I've prepped all of it)
- `fastlane beta` → build + upload the TestFlight build *(needs the Mac; first run creates your
  Distribution cert — best run by you, not headless)*.
- `fastlane metadata` → push listing text + screenshots.
- Host `docs/legal/privacy.html` + `support.html`, then drop the URLs into
  `fastlane/metadata/en-US/{privacy,support}_url.txt`.
