# HighNotes — Documentation

Current, authoritative specs for the **native iOS, on-device** product
(HighNotes, "Your AI budtender"). Read these before non-trivial changes.

| Doc | What it covers |
|---|---|
| [`PRD-v1.md`](./PRD-v1.md) | Product requirements: what HighNotes is, who it's for, functional requirements, reliability tiers, goals/non-goals, constraints |
| [`SAD-v1.md`](./SAD-v1.md) | Software architecture: on-device design, two-pass FM extraction, the pipeline state machine, every component, the layered safety architecture, build/signing/test |
| [`UXD-v1.md`](./UXD-v1.md) | UX design: screen flow, every screen, the capture/confirm experience, the result hero, strain-type editor, copy guidelines |
| [`EXECUTION-LOG-2026-05.md`](./EXECUTION-LOG-2026-05.md) | How we executed the spike → v1: what we learned, what we built in order, every scope change |
| [`OPEN-ISSUES.md`](./OPEN-ISSUES.md) | Consolidated backlog — every known issue with severity, plus decisions deferred on purpose |

## Status (2026-05-27)
Device-tested v1 spike. 224 tests passing. On-device scan → two-pass FM
extraction → strain intelligence → grounded AI summary, with high-res capture,
user-correctable strain DB, learn-more links, and an optional StoreKit **tip
jar** (About-only, never a paywall). See the execution log for the full story
and the open issues.

## Legacy (do NOT build against)
[`legacy/`](./legacy/) holds the v0.1 PRD/SAD for the abandoned Next.js + Supabase
PWA. Read them only for the durable *why* (personas, wedge thesis, NJ-CRC field
schemas, logging modes, phasing) — every platform decision there is dead.
