# Legacy Docs (v0.1 — Next.js PWA path, superseded)

These are the discovery and design documents for the **original** direction of this project: a Next.js 15 PWA on Vercel, backed by Supabase (Postgres + Auth + Storage + Edge Functions), using Claude Sonnet 4.6 vision through a Supabase Edge Function for label parsing.

That direction was **pivoted on 2026-05-09** to a native iOS app using VisionKit + Foundation Models, fully on-device. See the repo root `README.md` for the current direction.

These docs are preserved because:

- The discovery work (personas, wedge analysis, NJ-CRC label structure, persona logging modes, phasing) is still valid regardless of platform.
- The PRD field schemas (cannabinoids, terpenes, provenance, Metrc) translate directly into the Swift `Generable` type.
- The architectural reasoning around per-scan cost, schema normalization, and ADRs documents the "why" of decisions that may resurface.

**Do not treat these as current architecture.** Anything platform-specific (Next.js, Supabase, RLS, Edge Functions, Anthropic API integration, Vercel deployment) is **superseded**.

## Files

| File | What it is |
|---|---|
| `PRD-v0.1.md` | Product Requirements Document v0.1 (2026-05-05). Personas, scope, P0/P1/P2 phasing, 11 open questions. Field schemas survive the pivot. |
| `SAD-v0.1.md` | Software Architecture Document v0.1. Next.js + Supabase architecture, 5 ADRs, per-scan cost model. **Architecture is superseded** — read for "why" reasoning, not "how." |
| `requirements-discovery-brief.md` | Product Requirements agent's discovery output — the source material for PRD v0.1. |
| `architecture-discovery-brief.md` | Software Architecture agent's discovery output — the source material for SAD v0.1. |
| `autoplan-review-2026-05-05.md` | gstack `/autoplan` multi-agent review of the v0.1 plan (CEO + design + eng + DX). Useful for capturing review-style critique that may apply to v0.2 as well. |

## What still applies after the pivot

- All persona work (Sara, Marcus, Dani)
- Wedge thesis (removing manual data entry from cannabis journaling)
- Field schemas — Metrc tag, cannabinoid percentages, terpene panel, license #, harvest/expiration, batch/lot
- Logging modes — quick (4 taps, ~15s) vs detailed (7 sections, 19-dim Likert effects grid, mood delta, symptoms relieved)
- Phasing — P0 MVP (label scan → product library → session logging → dashboard), P1 polish, P2 v1.5 consumer-protection "Reporter" features
- Backdating window question (still open)

## What does NOT apply

- Next.js / Vercel / PWA implementation
- Supabase (Postgres + Auth + Storage + Edge Functions + RLS)
- Claude Sonnet 4.6 via Anthropic API
- Per-scan cost model ($0.014 / $0.005 cached) — replaced by $0 on-device
- 4 of the 11 open PRD questions: license registry seeding, encryption-at-rest scope, Anthropic vision spike (collapsed by the on-device pivot)
- Multi-persona free flagship (nutrition was dropped)
