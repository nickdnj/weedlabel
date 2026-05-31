# App Store Listing — Pocketbud (copy pack)

Ready-to-paste text for App Store Connect + the two required hosted pages. Character
limits noted; all drafts are within limit. Pairs with [APP-STORE-CHECKLIST](APP-STORE-CHECKLIST.md).

> Bundle display name is **Pocketbud**; the Xcode target/bundle ID is still `weedlabel`
> (`com.demarconet.weedlabel`) — rename deferred, doesn't affect the listing.

---

## Store metadata

### Name (≤30) — 9 chars
```
Pocketbud
```

### Subtitle (≤30) — 24 chars
```
Your private AI budtender
```

### Promotional text (≤170, updatable without review) — 138 chars
```
Scan any NJ cannabis label and get a plain-English read on THC, terpenes, and provenance — 100% on your phone. Nothing ever uploaded.
```

### Keywords (≤100 chars, comma-separated, no spaces) — 96 chars
```
cannabis,weed,label,THC,terpene,scanner,strain,budtender,journal,private,dispensary,COA,NJ
```

### Description (≤4000)
```
Pocketbud is your private AI budtender. Point your iPhone at a cannabis label and Pocketbud reads the cannabinoids, terpenes, and provenance, then explains them in plain English — so you actually understand what you're about to enjoy.

Everything runs on your device. No account. No tracking. Nothing is uploaded — your scans never leave your phone.

WHAT IT DOES
• Scan a label with your camera — Pocketbud reads the text and codes on-device.
• Understand it — an on-device AI summary explains the THC/CBD, terpene profile, and what the numbers mean.
• Know the source — cultivator, license number, harvest/expiration, and a link to the Certificate of Analysis when the label has one.
• Keep a private Log Book — save what you tried so you can find the good ones again. It stays on your device.
• Correct it in a tap — when the AI misreads something, fix it; it learns your corrections locally.

PRIVATE BY DESIGN
Pocketbud uses Apple's on-device intelligence. There's no server, no login, and no analytics. The only thing that ever leaves the app is you tapping a web link (like a COA). That's the whole point: it lives in your pocket and never leaves it.

BUILT FOR NEW JERSEY (FOR NOW)
This version is tuned for New Jersey dispensary (NJ-CRC) labels. Other formats may read less accurately for now.

REQUIREMENTS
Pocketbud's AI features need an iPhone 15 Pro, iPhone 16, or iPhone 17 on iOS 26 with Apple Intelligence enabled. On other devices you can still scan and view the label's structured data.

For informational and educational use only. Not medical advice. 21+.
```

### What's New (version notes, first release)
```
First release. Scan NJ cannabis labels, get a private on-device read on cannabinoids, terpenes, and provenance, and keep a private Log Book. Everything stays on your phone.
```

---

## App Review notes (paste into App Review Information)
```
Pocketbud is an informational/journaling app. It reads cannabis product labels on-device using the camera and Apple Foundation Models, and shows a plain-English summary plus a private, on-device log.

It does NOT sell, deliver, or facilitate the purchase of cannabis. It has no storefront, no ordering, and no location-based retailer features. No user data leaves the device: there is no account, no server, no analytics, and no third-party SDKs. The only network activity is the user tapping an external web link (e.g. a Certificate of Analysis).

Monetization is an optional tip jar (three consumable IAPs) reached only from the About screen; it never gates any feature.

Age rating: 17+ (cannabis references). In-app disclaimer states informational/educational use, not medical advice, 21+.

To test the AI read: use an Apple-Intelligence-capable device (iPhone 15 Pro / 16 / 17) on iOS 26 with Apple Intelligence enabled, then scan a NJ dispensary label (colon-delimited THCA/terpene format). A sample label is acceptable.
```

---

## Privacy Policy page (host at a public URL; required field)

> Host anywhere public (GitHub Pages, a static host). Keep it this short — it must agree
> with the "Data Not Collected" nutrition label.

```
Pocketbud — Privacy Policy
Last updated: May 31, 2026

Pocketbud collects no data.

Everything Pocketbud does — reading a label, the AI summary, and your Log Book — happens entirely on your device. We have no servers, no account system, and no analytics. We do not collect, store, transmit, sell, or share any personal information or usage data.

The camera is used only to read labels on your device; images and label data are stored locally on your phone and are never uploaded.

The only time anything leaves your device is when you choose to tap an external web link (such as a Certificate of Analysis), which opens in your browser.

In-app tips are optional purchases handled entirely by Apple; we never receive your payment information.

Because we collect nothing, there is nothing for us to access, correct, or delete on our end — clearing the app's data on your device removes everything.

Questions: vistter2@gmail.com
```

---

## Support page (host at a public URL; required field)

```
Pocketbud — Support

Pocketbud is a private, on-device AI budtender for reading cannabis labels.

Common questions:

• "The AI features aren't available." — They need an iPhone 15 Pro, 16, or 17 on iOS 26 with Apple Intelligence turned on (Settings → Apple Intelligence & Siri). On other devices you can still scan and view the label's structured data.

• "It misread my label." — Tap the value or strain name to correct it. Pocketbud is tuned for New Jersey (NJ-CRC) labels; other formats may read less accurately for now.

• "Is my data private?" — Yes. Pocketbud collects nothing and uploads nothing. See our Privacy Policy.

• "How do I clear my data?" — About → Clear local data.

Contact: vistter2@gmail.com
```

---

## Notes / TODO before submit
- Fill `[DATE]` in both pages (support email is set to vistter2@gmail.com), host them, and put the URLs in App Store Connect (Privacy Policy URL is a required field; Support URL is required).
- Age rating questionnaire → expect **17+** (cannabis references).
- App Privacy → **Data Not Collected** across the board (checklist §5). Verify no SDK breaks this.
- Screenshots: see `docs/branding/screenshots/` (real-app captures) and `docs/branding/showcase.html` (mockups). 6.9" required size is 1320×2868.
- `ITSAppUsesNonExemptEncryption = NO` to skip the export-compliance prompt (checklist §8).
