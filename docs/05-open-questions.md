# 05 — Open Questions

_Date: 2026-08-27_

Decisions not yet made. None block starting Phase 1; most resolve during
implementation planning.

## Content & licensing

1. **Which exercise dataset?** Candidates: `free-exercise-db` (yuhonas) —
   permissive, ~800 exercises with images; wger — AGPL, careful about license
   implications for a bundled app. Need to pick one and record the license in the
   repo before bundling.
2. **Curation list.** Which ~100–150 exercises make the v1 catalog? Should cover
   every movement pattern × equipment type Varun has. Draft this from his
   equipment checklist once onboarding is filled in.
3. **Image format / size budget.** How much app-bundle size is acceptable for
   instruction images? Compress / downscale target.

## Engine / programming

4. **Volume landmark source.** Which published set-count ranges per muscle group
   per experience level do we encode? Pick a reference and cite it.
5. **Load estimation for brand-new lifts** with no history — bodyweight-ratio
   heuristics, an onboarding "estimate your working weight" step, or start
   deliberately light and ramp fast?
6. **Progression cap numbers.** Exact per-session load-increase caps (e.g. +2.5 kg
   upper / +5 kg lower, or a %). Needs a first pass, then tune from real logs.
7. **Deload trigger.** What exact combination of "brutal" ratings + stalls +
   weeks-since-deload fires the lighter week?

## AI

8. **Provider + model selection (deferred research).** Undecided. Benchmark
   candidates on reasoning quality, latency, and cost per call: Gemini
   Flash-class, GPT-mini-class, Claude Haiku-class, an OpenRouter-style router, a
   local model. Must have (or degrade gracefully without) a vision path for the
   InBody call. Sizing to test against: ~150 calls/month, ~1M tokens/month
   (see `03` §6.5). Also: what month-to-date spend triggers a warning banner?
   - **Note:** consumer chat subscriptions (Gemini Pro/Advanced, ChatGPT
     Go/Plus) do **not** grant API access — no supported way to route the app
     through them. Viable zero/low-cost paths: Gemini API **free tier**, or an
     **on-device model** via Apple's Foundation Models framework (needs Apple
     Intelligence hardware — not the iPhone 14; fine on the iPhone 17 Pro).
9. **History window.** 4–6 weeks was the design figure — confirm what fits
   comfortably in context alongside the catalog slice without bloating tokens.
10. **Prompt/version storage.** Keep prompts in code, or in a bundled file that
    can be tweaked without a rebuild?
19. **`LLMProvider` surface.** Are `complete` + `completeWithImage` (per
    `03` §6) the right minimal set? Does any realistic candidate provider fail to
    support the nesting depth of the `WeeklyPlan` schema — and if so, is the
    Validator + retry path enough to cover it?
20. **Cost meter accuracy.** Token→price mapping differs per model and changes
    over time. Store `pricePerMTokIn/Out` in settings and update by hand, or
    fetch a small pricing table?

## InBody

11. **Sheet format variance.** InBody 570 vs 770 vs 970 vs gym-rebranded
    printouts differ in layout. How many real sample photos can Varun provide for
    testing the extractor?
12. **Confidence threshold.** Below what per-field confidence do we drop the
    pre-fill and force manual entry for that field?

## Product

13. **App name.** "Fitness Tracker" is a placeholder.
14. **Onboarding "won't do" list.** Free-text, or pick-from-catalog, or both?
15. **Notification defaults.** On or off at first run? Which ones?

## Project / tooling

16. **Git.** This directory is not a git repo yet. Initialize before Phase 1?
17. **Xcode project vs Swift Package.** App target structure — plain Xcode
    project, or SPM modules for RuleEngine/Validator to keep them testable in
    isolation?
18. **Minimum iOS version.** Design says iOS 17+ (SwiftData). Confirm the iPhone
    14 is on iOS 17 or later.
