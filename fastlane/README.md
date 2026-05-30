# Fastlane — Pocketbud release automation

Turns the two Mac-only steps into one command each. **Build upload needs this Mac;**
the account/listing admin can be done from your phone (see `docs/TESTFLIGHT-RECRUITING.md`).

## One-time setup (~10 min, on the Mac)

1. **Install fastlane** (not yet installed on this machine):
   ```bash
   brew install fastlane          # or: gem install fastlane
   ```

2. **Create an App Store Connect API key** (App Store Connect → Users and Access →
   Integrations → App Store Connect API → "+"). Role **App Manager** or **Admin**.
   Download the **`.p8`** (you can only download it once) and note the **Key ID** + **Issuer ID**.
   > This can be created from mobile Safari while you're out; just download the `.p8` on the Mac.

3. **Point fastlane at the key** (don't commit the `.p8` — it's git-ignored):
   ```bash
   export ASC_KEY_ID=XXXXXXXXXX
   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   export ASC_KEY_PATH="$HOME/.appstoreconnect/AuthKey_XXXXXXXXXX.p8"
   ```
   (Put these in a local `.env` or your shell profile.)

4. **Register the App ID + create the app record** (once). Either:
   - From your phone/Safari: developer.apple.com → Identifiers → register `com.demarconet.weedlabel`;
     then App Store Connect → Apps → "+" → New App. **Or**
   - Let the first `fastlane beta` create the app record automatically (it can, with the API key).

## Day-to-day

```bash
# Ship a TestFlight build (build Beta scheme + upload):
bundle exec fastlane beta        # or: fastlane beta

# Push the App Store listing text + screenshots (no binary):
bundle exec fastlane metadata

# Sanity-check metadata lengths without uploading:
bundle exec fastlane check_metadata
```

## Before the first run — fill these placeholders
- `fastlane/metadata/en-US/support_url.txt` and `privacy_url.txt` → your hosted page URLs
  (deployable pages are in `docs/legal/`).
- `fastlane/metadata/review_information/phone_number.txt` → your number.

## Notes
- `fastlane beta` archives the **Beta** config (includes the `#if BETA` tester-feedback
  feature). The final **App Store** submission should use the `weedlabel` scheme / Release
  config so the feature compiles out — see `docs/SPEC-beta-feedback.md`.
- Signing: you currently have only an **Apple Development** cert. `-allowProvisioningUpdates`
  (set in the Fastfile) lets Xcode create the **Distribution** cert + App Store profile on the
  first archive. That's a one-time change to your Apple account, so the **first** `fastlane beta`
  is best run by you, not headless.
- Screenshots live in `fastlane/screenshots/en-US/` (1320×2868 = 6.9" iPhone). Add more sizes
  later if desired; the 6.9" set is the only required one.
- Categories, age rating (17+), and the **Data Not Collected** privacy label are set in App
  Store Connect (the privacy label isn't managed by deliver here). See `docs/APP-STORE-CHECKLIST.md`.
