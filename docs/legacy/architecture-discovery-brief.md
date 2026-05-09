# NJ Weed Label Reader & Reporter — Technical Discovery Brief

**Version:** 0.1 (Discovery)
**Last Updated:** 2026-05-05
**Status:** Pre-PRD discovery — informs scoping, not implementation

---

## 1. Public NJ Cannabis Data Sources

### 1.1 NJ-CRC License Registry

- **No documented public REST API.** The CRC operates a public portal at `https://nj-crc-public.nls.egov.com/` and an applicant/licensee portal at `https://nj.accessgov.com/cannabis-site/`. Both are interactive web UIs, not developer endpoints.
- **What does exist publicly:** the CRC has stated it is "committed to continuing to release data" and has launched a database of municipal opt-in cannabis license information. License approvals are announced batch-by-batch in CRC meeting minutes (e.g., "62 licenses approved", "70 new licenses"). No canonical CSV/JSON feed of all licensees with status was located.
- **Implication for the app:** to validate a license number like `C000186` (Fresh Grow LLC's cultivator license on the sample label) against a trusted source, MVP will likely need to **scrape and cache** data from the CRC public portal on a schedule, or seed a license table from CRC press releases / OPRA requests. Treat this as a build-our-own reference dataset.
- **Action items / open questions:** file an OPRA request for the full active-licensee list (cultivator/manufacturer/retailer with license #, legal name, address, status, effective date); confirm whether the egov portal exposes a JSON endpoint behind its UI (likely yes — worth a network-tab inspection during the spike).

Sources: [NJ CRC Public Portal](https://nj-crc-public.nls.egov.com/), [NJ Cannabis Public Information](https://www.nj.gov/cannabis/about/public-information/), [CRC Municipal Database announcement](https://www.njlm.org/m/newsflash/Home/Detail/2978?arc=3556).

### 1.2 Metrc — Public Package Verification

- **Metrc's main API is closed to licensees only** (state-issued credentials, vendor API key, license number). There is no public consumer API for arbitrary package-tag lookup.
- **Metrc Retail ID** (launched 2024–2025) is the consumer-facing path: it generates a per-unit QR that resolves to a hosted "VerifID" page exposing origin, potency, COA, recall status. **NJ adoption is not confirmed** — Retail ID rollout is uneven across the 21 Metrc states. The label in question shows two QR codes but appears to predate confirmed NJ Retail ID; one is almost certainly the Metrc package barcode (encodes `1A4110300008C8D000041730`), the other likely the cultivator's batch lookup or COA link.
- **Implication for the app:** **do not assume any read API.** The 24-char tag itself is the durable identifier. The app should treat the tag as an opaque ID it stores and dedupes against, then enrich with whatever the QR URL resolves to (could be a Metrc Retail ID page, a cultivator-hosted COA PDF, or nothing useful).

Sources: [Metrc Retail ID](https://www.metrc.com/retailid/), [Cannabis Science & Tech: Metrc consumer scan for recalls](https://www.cannabissciencetech.com/view/new-metrc-feature-lets-california-cannabis-consumers-scan-for-recalls), [Metrc 1M weekly QR codes](https://www.metrc.com/news/metrc-retail-id-achieves-1-million-weekly-run-rate-of-qr-codes-across-21-markets-an-unprecedented-pace-for-cannabis-supply-chain-technology/).

### 1.3 NJ COAs (Certificates of Analysis)

- **Not centrally published.** NJ regs require labs to submit COAs and dispensaries to provide them on request, but there is no statewide COA repository. The CRC's own guidance ("How to Read a COA") instructs consumers to ask the dispensary, scan the on-pack QR, or file an OPRA request.
- **Per-cultivator/lab hosting is the norm** — most COAs live on lab portals (e.g., True Labs, Trichome Analytical, Steep Hill) or cultivator websites, accessible via the on-label QR.
- **Implication:** the app's "view COA" flow has to follow whatever URL the QR resolves to, then either cache the PDF or parse it. There's no shortcut.

Sources: [NJ CRC: How to Read a COA](https://www.nj.gov/cannabis/documents/How%20to%20Read%20a%20COA.pdf), [True Labs NJ COA portal](https://www.truelabscannabis.com/blog/cannabis-lab-testing-results), [NJ CRC Testing Guidance Rev 1.0](https://www.nj.gov/cannabis/documents/businesses/Business%20Resources/CRC%20Testing%20Guidance%209.28.22.pdf).

### 1.4 Third-Party Reference Data (strain/terpene)

- **Leafly** — no open public API in 2026; they shut down public developer access years ago and now run a researcher-only data-sharing program. Scraping is brittle and against ToS.
- **Weedmaps** — developer portal exists at `developer.weedmaps.com` but explicitly **not onboarding new integrations** at this time.
- **Open Cannabis API** (otreeba.com) — community-maintained, REST, free; useful for strain/cultivar normalization but coverage and freshness are inconsistent.
- **Confident Cannabis** — primarily a B2B lab-data platform; no advertised public consumer API.
- **Recommendation:** for MVP, **do not depend on a third-party strain DB.** Store the strain name verbatim from the label and let the user normalize in-app over time. Optionally seed a small internal strain table from Open Cannabis API + Kaggle Leafly dataset for autocomplete.

Sources: [Leafly API documentation](https://help.leafly.com/hc/en-us/articles/20916238531603-Leafly-API-Documentation), [Weedmaps Developer](https://developer.weedmaps.com/), [Open Cannabis API](https://otreeba.com/), [Leafly Strains Kaggle dataset](https://www.kaggle.com/datasets/gthrosa/leafly-cannabis-strains-metadata).

---

## 2. Metrc Tag Format — `1A4110300008C8D000041730`

Per Metrc's published tag guidance and operator references, the 24-character tag is structured (informally) as:

| Segment | Chars | Sample value | Meaning |
|---|---|---|---|
| Generation | 1–2 | `1A` | Tag generation prefix. `1A` indicates a current-gen (Tag Order V2) Metrc tag. Some states have used `2A` for the next generation. |
| State / facility identifier | 3–16 | `4110300008C8D00` | First **16 digits combined** = the **Package Tag Prefix**, unique to a single license. State code, facility ID, and tag-order metadata are encoded here. The same prefix repeats across every tag that license orders. |
| Sequence | 17–24 | `00041730` | Per-license sequential serial number for that tag order. |

So the sample tag tells us: it was issued to one specific NJ-licensed facility (Fresh Grow LLC / `C000186`) and it's serial #41,730 (give or take) from that license's tag pool. The encoded text in the QR code on a Metrc package is **typically just the 24-char tag string itself** (a plain barcode payload), **not** a URL — unless the cultivator overlays a Metrc Retail ID QR or their own COA QR. The second smaller code on this label (`9-120925`) is almost certainly an internal batch/lot ID (note `120925` matches the 12/09/25 timeframe near the 12/10/25 harvest).

**App implication:** parse the tag with a regex (`^1A[0-9A-F]{14}[0-9]{8}$`), use it as the unique key, and resolve the QR payload separately (it may be a URL or just the tag).

Sources: [Distru: Complete Guide to Metrc Tags](https://www.distru.com/cannabis-blog/complete-guide-to-metrc-tags), [Metrc Plant & Package Tag Best Practices PDF](https://www.metrc.com/wp-content/uploads/2024/03/Plant-TaggingV3-1.pdf), [Canix: Update Metrc Package Tag Prefixes](https://help.canix.com/hc/en-us/articles/360059759092-Update-Metrc-Package-Tag-Prefixes), [Flourish: Comprehensive Guide to Metrc Tags & Retail IDs](https://www.flourishsoftware.com/blog/a-comprehensive-guide-to-metrc-tags-and-retail-ids-for-cannabis-operators).

---

## 3. OCR / Extraction Approach

The label has **predictable failure modes** for naive OCR:

- Glossy mylar / wax-paper finish causes specular highlights that wipe out 1–2 lines per shot
- Curved surface on jars and bags introduces perspective skew across the cannabinoid table
- Cannabinoid & terpene tables are tiny (often 6–8 pt) and use Greek letters and superscripts (`THCv9`, `BetaCaryophyllene`) that generic OCR models routinely garble
- Strain name is rotated 90° at the bottom of many NJ labels (true on this sample)
- Dates use multiple formats (`12/10/2025` vs `Harvest 12.10.25`)
- Brand "Total Cannabinoids" lines look like header rows and confuse table extractors

### Options compared

| Approach | Strength | Weakness for this use case | MVP fit |
|---|---|---|---|
| **Apple Vision (on-device, iOS)** | Free, offline, fast (~0.3s), great line/text recognition, handles rotated text well | iOS-only; no semantic understanding — gives raw lines, you still need a parser | Strong if iOS-first |
| **Google ML Kit Text Recognition (on-device, Android + iOS)** | Free, offline, fast (~0.05s), cross-platform | Latin-only (fine here); same issue: raw lines, no schema | Strong if cross-platform |
| **Google Document AI / AWS Textract / Azure DI (cloud OCR)** | Best raw accuracy on dense tables (~95–98%); table structure extraction | Cost per page (~$0.01–$0.05), latency, requires upload of label image (privacy), no semantic field mapping | Overkill for MVP; revisit if table accuracy is the bottleneck |
| **LLM-only vision (Claude Sonnet 4.6, Claude Opus 4.7, GPT-4o)** | Single call image → typed JSON; handles rotated text, glare, layout variation; understands "THCA vs THC vs Total" semantically | $0.005–$0.04/image, 1–4s latency, occasional hallucinations on faint numbers, requires server-side key (or proxy) | **Strong** — fewest moving parts, highest fidelity on field mapping |
| **Hybrid: on-device OCR → LLM for structuring** | Cheap raw text extraction; LLM only does the small structuring task; works offline-ish | Two failure points; OCR errors propagate; more code | Best long-term for cost and reliability |

### Recommendation for MVP

**LLM-only vision (Claude Sonnet 4.6) for the V1 extraction path**, called from a thin backend that proxies the API key. Reasoning:

1. Label layouts vary wildly across NJ brands — brittle table parsers will break weekly. An LLM with a typed JSON schema (cannabinoids, terpenes, dates, license #, Metrc tag) generalizes across layouts on day one.
2. The user takes one photo; one round-trip to the server returns structured JSON. UX is clean.
3. Cost at MVP scale (a user logs maybe 1–10 products/week) is negligible (<$0.05/user/month).
4. We can A/B against the hybrid path once we have ground-truth labeled data from real users.

**Specific prompt strategy:** send the image with a JSON schema in the system prompt (Anthropic supports tool-use / structured output), request all numeric fields as numbers (not strings), and require an explicit `confidence` per field plus a `raw_ocr_text` dump for debugging. Pre-process client-side: auto-rotate, deskew, two captures (auto-exposure + reduced-exposure to kill glare), let user crop.

**V2 evolution:** once we have ~500 labeled labels, train a hybrid pipeline (ML Kit OCR → small fine-tuned classifier or local LLM) to drop server cost and enable offline scanning.

Sources: [OmniAI OCR Benchmark](https://getomni.ai/blog/ocr-benchmark), [Comparing Apple Vision and Google ML Kit](https://www.bitfactory.io/de/dev-blog/comparing-on-device-ocr-frameworks-apple-vision-and-google-mlkit/), [AWS Textract vs Google Document AI 2026](https://www.braincuber.com/blog/aws-textract-vs-google-document-ai-ocr-comparison), [Koncile: Claude vs GPT vs Gemini for invoice extraction](https://www.koncile.ai/en/ressources/claude-gpt-or-gemini-which-is-the-best-llm-for-invoice-extraction).

---

## 4. QR Scanning

- **Decode both codes in one pass.** The library should scan the full frame, return all detected codes, and let the app classify each by payload pattern (Metrc tag regex vs URL vs short alphanumeric).
- **Library pick:**
  - On React Native: **`react-native-vision-camera`** + the `vision-camera-code-scanner` / ML Kit barcode plugin. It uses native ML Kit (Android) and Vision (iOS), supports multi-code detection in one frame, and runs inside the same camera session as the OCR capture.
  - On native iOS: `AVFoundation` `AVCaptureMetadataOutput` is sufficient and free.
  - On Flutter: `mobile_scanner` (ML Kit-backed).
- **Avoid ZXing-only libraries** — older, slower, weaker in low light vs ML Kit.
- **Edge cases:** Metrc package barcodes are sometimes printed as 1D Code-128 alongside the QR — the same scanner plugin handles both formats; configure to accept QR + Code-128 + DataMatrix.

Sources: [Scanbot: open-source RN barcode scanners](https://scanbot.io/blog/popular-open-source-react-native-barcode-scanners/), [VisionCamera QR/Barcode docs](https://react-native-vision-camera.com/docs/guides/code-scanning), [VisionCamera vs Expo Camera 2026](https://www.pkgpulse.com/blog/react-native-vision-camera-vs-expo-camera-vs-expo-image-picker-2026).

---

## 5. MVP Tech Stack — Opinionated Pick

**Recommendation: React Native + Expo (with `react-native-vision-camera` via dev client) → Supabase backend → Supabase Storage for label photos → Anthropic API (Claude Sonnet 4.6) for extraction, called from a Supabase Edge Function.**

Rationale:

- **Cross-platform from day one.** A weed-tracking app's core users are on both iOS and Android; one codebase halves time-to-market.
- **Expo (with dev client)** gets us OTA updates, EAS builds, and a clean dev loop without sacrificing native modules — Vision Camera works fine in this setup as of 2026.
- **Supabase over Firebase:**
  - Postgres is the right model for this data (consumption events, products, terpene profiles, joins for "favorite strains by terpene"). Firebase/Firestore would force awkward denormalization.
  - Built-in auth, Row-Level Security (so users only see their own logs), Edge Functions for the LLM proxy, and Storage with signed URLs — covers everything we need without standing up a Node API.
  - Open-source and self-hostable later if needed.
- **Storage:** Supabase Storage for MVP simplicity. If image volume grows past free tier, migrate to **Cloudflare R2** (S3-compatible, no egress fees) — much cheaper than S3 for the read-heavy "show me my history" pattern.
- **Why not native iOS-first:** Apple Vision quality is genuinely good, but it forces an Android rebuild later and gates the user base. We'd give up months for a marginal OCR quality bump that the LLM path largely closes anyway.
- **Why not Flutter:** viable choice, similar capabilities. RN wins on (a) larger ecosystem of cannabis-adjacent and analytics SDKs, (b) easier hiring, (c) existing user familiarity from other projects in this org. Not a strong technical loss either way.
- **Why not PWA:** camera APIs on iOS Safari are still inconsistent for sustained capture + barcode scanning, and "install to home screen" friction kills retention. Reserve PWA as a "view-only history dashboard" companion.

---

## 6. Key Technical Risks & Open Questions

1. **No authoritative NJ license API.** Validating that `C000186` is a real, active license requires us to build and maintain our own license dataset (scrape + cache + reconcile against CRC press releases). Risk: stale data shows users "INVALID" for legitimate products. **Open: file OPRA request and inspect egov portal network traffic to find a stable JSON source.**
2. **Metrc package verification is closed.** We cannot independently verify a tag is real — we can only validate format and check for duplicates. Counterfeit-detection is out of scope until/unless NJ adopts Metrc Retail ID broadly.
3. **OCR accuracy on cannabinoid tables.** Even Claude vision occasionally misreads `THCA 29.73%` as `THCA 29.78%`. We need a confidence threshold + user-confirm step for any extracted % value before persisting.
4. **Privacy / legal posture.** Cannabis is federally illegal; storing user consumption history + photos is sensitive. Decisions needed: encrypt at rest? anonymous accounts only (no email)? auto-delete photos after extraction? **This is a PRD-level question, not architecture.**
5. **App store policy.** Apple App Store has historically rejected cannabis-tracking apps unless region-restricted. Plan for a TestFlight + side-loaded Android release first; investigate whether a web companion is needed for users blocked from app stores.
6. **Strain-name normalization.** "Blueberry Caviar," "Blueberry Caviar #2," and "BB Caviar" are the same to the user. We need fuzzy matching (trigram or embedding-based) in the consumption analytics, not exact-string grouping.
7. **COA link rot.** Cultivator-hosted COA URLs disappear when brands rebrand or labs change. If we want long-term "show me past lab results" we have to **download and store the COA PDF at scan time**, not just the URL. That doubles storage cost — decide at PRD time.

---

*End of discovery brief. Next step: convert to PRD with product owner, then full architecture doc.*
