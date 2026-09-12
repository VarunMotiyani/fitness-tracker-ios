# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

One user (the developer-athlete himself): an intermediate-to-advanced lifter training in a real gym with barbell, dumbbell, cable, machine and bodyweight work. Phone-only, one-handed, mid-workout, often sweaty-handed and time-pressured. Between sessions he checks whether the plan is working and reviews what the coach noticed.

## Product Purpose

An adaptive strength & physique coach that builds a rolling week of sessions, tells him exactly what to do each session with the equipment he actually has, adapts to what he actually did and how he felt, and reads monthly InBody scans to verify results. Success = he lifts better numbers at a lower body-fat percentage while the app does the programming thinking for him.

## Positioning

The plan is a rolling target, not a calendar: every app open recomputes from actual completed history, nothing is ever "missed", and the coach is proactive — it posts observations, plan-change suggestions, and check-ins on its own, and the user accepts or skips them. It is not a passive workout logger with an AI chat bolted on; the AI plans, the rule engine enforces guardrails (load caps, volume landmarks, injury exclusions, rest gaps), and the user never manages a split by hand.

## Operating Context

Gym-floor session logging (sets, reps, load, RIR, warm-ups, supersets, rest timers), pre-session energy/time check, post-session easy/right/brutal feedback, daily check-in, bodyweight and InBody tracking, plan review, coach chat, Hevy/CSV import-export. Bring-your-own LLM API key (OpenAI-compatible/Gemini adapters); no backend; fully offline-capable except AI calls.

## Capabilities and Constraints

- On-device only: SwiftData store, bundled ~1.5 MB exercise catalog (free-exercise-db), no account, no sync.
- AI is advisory: every suggestion passes the rule-engine validation layer before it can touch the plan (docs/03-technical-architecture.md).
- BYO provider key from Keychain; cost capped by a budget guard (AICallRecord ledger, CostChip).
- Binding visual constraint: dark, pure-black "gym floor" identity (GymTheme, `.preferredColorScheme(.dark)`) — harden it (contrast variants, Smart-Invert-safe tokens), never replace it.
- iPhone-only per product intent (README "phone-only"); iPad/landscape is out of scope and being removed from the shipped target (2026-09-11 audit decision D1).
- iOS 26 deployment target; SwiftUI + SwiftData; Swift 6 strict concurrency.
- Terminology the app owns: rolling plan, session, routine, microcycle, RIR, PR, niggle list, coach note, observation, suggestion, InBody.

## Brand Commitments

Name: PulseAI (app display name; repo title "Fitness Tracker" is the working title). Voice: coach-like, direct, second person, short ("Updating your plan…", "Ready to wrap up?"). No emoji in UI chrome. Dark pure-black + single lime accent + SF Symbols + Liquid Glass floating tab bar with center Start disc are the established identity.

## Evidence on Hand

- docs/: full design corpus (00–12), decision register (06), LEDGER.md engineering log, HANDOFF.md project digest, plans/ and specs/ per-feature docs.
- Bundled catalog JSON + demo seed generator (DemoSeedGenerator) for realistic history.
- Absences future work must not fabricate: no testimonials, no App Store presence, no design system doc (DESIGN.md not yet written), no multi-user or social features.

## Product Principles

1. The plan bends to life, not the reverse — history recomputes, nothing is "missed".
2. The coach acts first: proactive observations/suggestions beat a blank chat box.
3. The gym floor is the core screen — one-handed, glanceable, tap-fast; everything else is between-workouts.
4. AI proposes, rules dispose: no model output reaches the plan without validation and guardrails.
5. Private by construction: one user, on-device data, user's own key.

## Accessibility & Inclusion

No formal standard imposed, but the 2026-09-11 audit set the working bar: VoiceOver-complete workout-logging flow, Dynamic Type support, 44 pt touch targets, AA contrast on text, Reduce Motion + flashing-alerts respected (the rest-timer strobe is a photosensitivity risk and must be gated).
