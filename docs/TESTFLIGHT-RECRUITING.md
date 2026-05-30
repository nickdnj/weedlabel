# TestFlight Recruiting Kit — Pocketbud

Everything you need to recruit and onboard beta testers. Copy/paste the blurbs,
adjust names. **Pocketbud — "Your AI budtender. Lives in your pocket, never leaves it."**

---

## 0. The hard device requirement (read first)

Pocketbud's AI runs **on-device** via Apple Foundation Models, so a tester **must** have:

- **iPhone 15 Pro / 15 Pro Max, or any iPhone 16 or 17** (Apple-Intelligence-capable hardware), **and**
- **iOS 26 or later**, with **Apple Intelligence turned on** (Settings → Apple Intelligence & Siri).

> A regular iPhone 15 / 14 / SE **won't** run the AI read. Don't waste an invite slot on
> ineligible hardware — screen for this *before* sending the TestFlight link. There's a
> one-line eligibility check in the invite copy below.

Best-fit testers also **shop NJ dispensaries** — v1 reads **NJ-CRC labels** (the colon-delimited
THCA/terpene/license format). Out-of-state labels may parse worse; that's expected for v1.

---

## 1. Who to recruit (from the personas)

| Persona | Who they are | Why they'll care |
|---|---|---|
| **Sara, the Connoisseur** | Remembers strains she liked, wants to find them again | The Log Book + strain read |
| **Marcus, the Symptom Tracker** | Wants to understand effects | Plain-English cannabinoid/terpene summary |
| **Dani, the Value/Trust Shopper** | Checks provenance before buying | License #, harvest date, COA links |

All testers **21+**. Aim for **8–15 active testers** to start — enough signal, few enough that the
email feedback stays manageable (see [SPEC-beta-feedback](SPEC-beta-feedback.md)).

**Where to find them (suggestions, not a spam plan):**
- Friends/family who shop NJ dispensaries and have eligible iPhones — highest response, start here.
- NJ cannabis communities you already participate in (e.g. r/NJEnts and similar) — post once, honestly,
  as the solo developer; don't blast. Lead with privacy ("nothing leaves your phone").
- Budtenders / dispensary staff you know — they see the most labels.

---

## 2. Invite copy

### Short text / DM
> Hey — I built a tiny iPhone app, **Pocketbud**, that reads a cannabis label and explains it in
> plain English (THC, terps, the vibe). It's **100% on your phone — nothing gets uploaded**. Want to
> beta test? Quick check first: do you have an **iPhone 15 Pro, 16, or 17** on **iOS 26**? If yes, I'll
> send you a TestFlight link.

### Email
> **Subject: Want to try Pocketbud? (private cannabis-label reader, iPhone beta)**
>
> Hi [name],
>
> I've been building **Pocketbud** — point your iPhone at a dispensary label and it reads the
> cannabinoids, terpenes, and provenance and gives you a plain-English summary. The whole thing runs
> **on your device**: no account, no tracking, nothing uploaded.
>
> I'm looking for a few beta testers. Two requirements:
> 1. An **iPhone 15 Pro, iPhone 16, or iPhone 17** running **iOS 26** with Apple Intelligence on.
> 2. You shop **NJ dispensaries** (the first version is tuned for NJ labels).
>
> If that's you, reply and I'll send a TestFlight invite. Takes ~2 min to install. You scan a few
> labels, tell me what's right or wrong — that's it.
>
> Thanks,
> [you]

### Social / forum post
> I'm a solo dev and made **Pocketbud**: scan a NJ dispensary label, get a plain-English read on the
> THC/terpenes/provenance — **entirely on-device, nothing uploaded, no account**. Looking for a handful
> of beta testers on **iPhone 15 Pro / 16 / 17 (iOS 26)**. Comment or DM if you want in. 🌿

---

## 3. What testers see in TestFlight (App Store Connect fields)

### Beta App Description (TestFlight "Test Information" → Description)
> Pocketbud is your private, on-device AI budtender. Point your iPhone at a NJ cannabis label and it
> reads the cannabinoids, terpenes, and provenance, then explains them in plain English — and saves it
> to a private Log Book. Everything runs on your device; nothing is uploaded.
>
> **This is a beta.** The AI sometimes misreads a label — when it does, tap to correct it, and please
> share the scan so I can improve it (you'll be asked after a scan; it's on by default for testers and
> you can turn it off in About → Share scans). Sharing always goes through your own Mail and only when
> you tap send.

### What to Test (TestFlight "What to Test")
> 1. **Scan a few real labels** — flower, vape, edible, pre-roll. Does the strain name, THC%, and
>    terpene list match the printed label?
> 2. **Correct any misreads** — tap the strain name / values to fix them. Was correcting obvious?
> 3. **Share the scan** when prompted (👍/👎 + note) so I get the real label data.
> 4. **Log Book** — is the saved entry useful? Can you find a past scan?
> 5. **Anything confusing, slow, or broken** — send it via TestFlight's screenshot feedback (shake or
>    screenshot in the TestFlight app).
>
> Known limits: v1 is tuned for **NJ-CRC** labels; out-of-state formats may parse worse. AI features
> need an iPhone 15 Pro / 16 / 17 on iOS 26.

### Feedback email / contact
- TestFlight built-in feedback (screenshots + notes) → App Store Connect, automatic.
- In-app **Share scan** → email to you with the structured scan data + photo.

---

## 4. Tester FAQ

**Is my data being collected?**
No. Pocketbud runs entirely on your phone — no account, no analytics, no upload. The only thing that
ever leaves your device is a scan **you** choose to share (beta only), which goes through **your own
Mail app** and only when you tap send. You can turn sharing off in **About → Share scans**.

**What's in a shared scan?**
The label text the app read, the AI's interpretation, any corrections you made, your note, and the
label photo. You see it all in the mail composer before it sends.

**Why does it need a newer iPhone?**
The AI that reads and explains the label runs on-device using Apple Intelligence, which needs an
iPhone 15 Pro, 16, or 17 on iOS 26.

**Does it work for non-NJ labels?**
v1 is tuned for New Jersey dispensary labels. Other formats may read less accurately for now.

**Is this medical advice?**
No — it's informational and educational only. 21+.

**How much time does testing take?**
A few minutes. Scan some labels over a couple of weeks, correct misreads, share a few. That's it.

---

## 5. Mechanics (for you)

- **Internal testing** (up to 100 testers you add by Apple ID, no Beta App Review): fastest way to
  start — use this for the first cohort.
- **External testing** (public link, up to 10,000): requires a **Beta App Review** pass first. Use the
  App Review notes from [APP-STORE-CHECKLIST](APP-STORE-CHECKLIST.md) §6 verbatim.
- Build for TestFlight with the **`weedlabel-Beta`** scheme (includes the feedback feature). The final
  App Store submission uses the **`weedlabel`** (Release) scheme. See [SPEC-beta-feedback](SPEC-beta-feedback.md).
- Suggested Gmail filter for inbound feedback: `subject:"Pocketbud beta — scan feedback"` → label
  `pocketbud-beta`, skip inbox.

> Prereq for *any* TestFlight: the **$99/yr Apple Developer Program** + a build uploaded to App Store
> Connect. See [APP-STORE-CHECKLIST](APP-STORE-CHECKLIST.md) §0.
