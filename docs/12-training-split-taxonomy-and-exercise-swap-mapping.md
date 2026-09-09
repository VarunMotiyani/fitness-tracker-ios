# Training split taxonomy and exercise swap mapping

## Decision summary

The app should model a workout in layers rather than treating “Push”, “Upper”, “Hypertrophy”,
and “Barbell” as the same kind of label:

1. **Schedule split** — how sessions are distributed across the week (full body, upper/lower,
   PPL, Arnold, PHUL, and so on).
2. **Session focus** — the body regions or movement families trained in one session (push,
   pull, legs, upper, posterior chain, chest/back, arms, conditioning).
3. **Exercise taxonomy** — movement pattern, joint action, muscle role, training intent, and
   equipment.
4. **Prescription metadata** — goal, rep range, intensity, volume, rest, and progression.

This lets the app offer many named splits without hard-coding a separate exercise list for every
name. A swap should query the selected day’s **session focus and movement requirements**, then
rank exercises from both catalogs by compatibility. The persisted value remains the catalog
source plus the catalog’s stable exercise ID; labels and compatibility are derived.

### Implemented groundwork in this pass

The shared core now contains movement/focus enums, a tolerant focus classifier, an exercise tag
resolver, a ranked catalog compatibility query, and an expanded built-in template registry. The
Home/Library day picker and date-scoped persistence use the shared resolver, and the Athlete
Profile editor now exposes the split-style selector so an explicit style feeds plan generation.
Source-scoped persisted IDs and raw-category retention remain the next migration steps; they are
deliberately not inferred from a bare exercise name or catalog force value.

The evidence does not support claiming that a particular split is universally superior. A 2024
systematic review found no meaningful strength or hypertrophy difference between split and
full-body routines when volume is equated.^1 Training frequency also loses its independent
advantage when weekly volume is equated, so the selector should optimize for adherence, session
length, recovery, and the athlete’s available days rather than advertise a “best” split.^2,3

## What is in the current catalogs

The app ships two raw Free-Exercise-DB-shaped resources:

| Resource | Rows | ID example | Primary-muscle vocabulary | Notable limitation |
|---|---:|---|---|---|
| `catalog.json` (Gym Visual media) | 1,324 | `0025` | `pectorals`, `lats`, `delts`, `upper back`, `spine`, … | `force` is heavily skewed to `push` (964/1,324); hinge examples such as deadlift can be marked push. Media is hotlinked and has separate licensing concerns. |
| `free_exercise_db.json` (Yuhonas) | 876 | `Barbell_Bench_Press_-_Medium_Grip` | `chest`, `lats`, `middle back`, `quadriceps`, … | 30 rows have no force; 87 have no mechanic; static images only. |

The two ID sets currently have **zero overlap**. Never use a bare ID as a cross-source identity.
Use a scoped key such as `gymvisual:0025` or `free_static:Barbell_Bench_Press_-_Medium_Grip`.
`FreeExerciseDBMapper` already normalizes primary and secondary muscles, equipment, mechanic,
force, difficulty, and unilateral status into `Exercise`; it currently drops the raw `category`
field, which should be retained for taxonomy scoring.

### Current normalized muscle buckets

The domain has 13 coarse buckets: `chest`, `back`, `lowerBack`, `traps`, `shoulders`, `biceps`,
`triceps`, `forearms`, `quads`, `hamstrings`, `glutes`, `calves`, and `abs`.

This is sufficient for the first implementation, but the resolver should preserve optional
sub-muscle tags (`lats`, `midBack`, `frontDelts`, `sideDelts`, `rearDelts`, `adductors`,
`abductors`, `hipFlexors`, `erectors`, `obliques`) when present. They can be projected into the
13 buckets for existing plans without losing detail for future filters.

## Taxonomy of exercise types

An exercise can have several tags at once. These are orthogonal dimensions, not mutually
exclusive “types”.

### Movement patterns

The NSCA teaching framework explicitly uses squat, hinge, horizontal/vertical push and pull,
lunge, and rotation patterns; carries and anti-movement patterns are useful additions for a
general-fitness app.^4,5

| Pattern ID | Definition | Examples | Main muscles |
|---|---|---|---|
| `kneeDominant` | knee extension with a relatively upright torso | squat, hack squat, leg press | quads, glutes |
| `hipHinge` | hip extension with controlled trunk/hip flexion | deadlift, RDL, good morning | hamstrings, glutes, erectors |
| `singleLeg` | unilateral knee/hip pattern | split squat, lunge, step-up | quads, glutes, hamstrings |
| `horizontalPush` | press away from the torso | bench press, push-up, dip | chest, triceps, front delts |
| `verticalPush` | press overhead | overhead press, landmine press | shoulders, triceps |
| `horizontalPull` | pull toward the torso | row, reverse fly, face pull | back, rear delts, biceps |
| `verticalPull` | pull from overhead | pull-up, chin-up, pulldown | lats, biceps, mid-back |
| `carry` | loaded locomotion or static carry | farmer carry, suitcase carry | traps, grip, trunk, legs |
| `antiExtension` | resist spinal extension | plank, ab wheel, dead bug | abs, trunk |
| `antiRotation` | resist transverse-plane rotation | Pallof press, suitcase carry | obliques, trunk |
| `antiLateralFlexion` | resist side bending | suitcase carry, side plank | obliques, QL |
| `rotation` | controlled trunk rotation | cable chop, medicine-ball throw | abs, obliques, hips |
| `spinalFlexion` | trunk flexion | cable crunch, sit-up | abs, hip flexors |
| `calfRaise` | plantar flexion | standing/seated calf raise | calves |
| `elbowFlexion` | curl pattern | barbell curl, hammer curl | biceps, brachialis, forearms |
| `elbowExtension` | extension pattern | pushdown, skull crusher | triceps |
| `shoulderAbduction` | raise the arm laterally | lateral raise | side delts |
| `shoulderHorizontalAbduction` | move arm away/back from a press position | reverse fly | rear delts, upper back |
| `scapularElevation` | shrug/carry pattern | shrug, farmer carry | traps |
| `powerOlympic` | high-velocity triple extension or lift derivative | clean, snatch, high pull | total body |
| `plyometric` | rapid stretch-shortening action | jump, bound, throw | task-dependent |
| `conditioning` | cyclic or interval work | bike, rower, sled, run | cardiovascular / total body |
| `mobilityRecovery` | controlled range-of-motion or tissue work | stretch, foam roll | region-specific |

### Exercise structure and intent

- `compound` / `isolation` (multi-joint vs single-joint)
- `bilateral` / `unilateral`
- `freeWeight` / `machine` / `cable` / `bodyweight` / `band` / `implement`
- `stable` / `unstable`
- `strength`, `hypertrophy`, `power`, `endurance`, `conditioning`, `mobility`, `rehab`
- `primary`, `secondary`, or `accessory` role inside a session
- `heavy`, `moderate`, or `light` loading emphasis

Do not infer goal from exercise name alone. The same squat can be a strength, hypertrophy,
power, or conditioning prescription depending on load, reps, velocity, and rest.

## Schedule split families

The following registry is intentionally broad. Each entry is a sequence of session definitions;
the sequence can be rotated across available weekdays and can include explicit rest days. “A/B”
means the sessions alternate rather than being identical copies.

### 2-day options

| ID | Sessions | Best fit |
|---|---|---|
| `fullBody2` | Full A / Full B | beginners, busy schedules |
| `upperLower2` | Upper / Lower | simple regional split |
| `pushPull2` | Push / Pull (legs assigned to both) | upper-body emphasis; requires leg-balance guard |
| `totalBodyStrength2` | Strength full body A / B | low-frequency strength |
| `fullBodyConditioning2` | Resistance full body / conditioning + mobility | general fitness |

### 3-day options

| ID | Sessions | Notes |
|---|---|---|
| `fullBody3` | Full A / Full B / Full A (rotate next week) | current default for ≤3 days |
| `ppl3` | Push / Pull / Legs | classic three-day PPL |
| `upperLowerFull3` | Upper / Lower / Full | balances region and frequency |
| `fullBodyDUP3` | Full strength / Full hypertrophy / Full power or conditioning | daily undulating emphasis |
| `strengthLift3` | Squat / Bench + upper pull / Deadlift + press | powerlifting-flavoured |
| `fullBodyAthletic3` | Total body / sprint-jump-throw / total body | athletic/general performance |

### 4-day options

| ID | Sessions | Notes |
|---|---|---|
| `upperLower4` | Upper / Lower / Upper / Lower | current regional template |
| `phul4` | Upper Power / Lower Power / Upper Hypertrophy / Lower Hypertrophy | same focus as UL; different prescriptions |
| `upperLowerArms4` | Upper / Lower / Upper + arms / Lower + core | arm-priority variant |
| `torsoLimbs4` | Torso / Limbs / Torso / Limbs | torso = chest/back; limbs = shoulders/arms/legs |
| `pushPull4` | Push / Pull / Push / Pull + lower-body quota | only valid with explicit leg quota on both days |
| `fullBodyUpperLower4` | Full / Upper / Lower / Full | useful for mixed goals |
| `powerbuilding4` | Squat / Bench / Deadlift / Upper accessories | strength lift anchors + hypertrophy work |
| `lowerUpperConditioning4` | Lower / Upper / Conditioning / Full | general fitness |

### 5-day options

| ID | Sessions | Notes |
|---|---|---|
| `pplul5` | Push / Pull / Legs / Upper / Lower | popular hybrid; each region can reach ~2 exposures |
| `phat5` | Upper Power / Lower Power / Back+Shoulders Hypertrophy / Lower Hypertrophy / Chest+Arms Hypertrophy | power + bodybuilding hybrid |
| `bro5` | Chest / Back / Shoulders / Legs / Arms | body-part split; low frequency per muscle |
| `upperLowerPPL5` | Upper / Lower / Push / Pull / Legs | alternate order around rest days |
| `arnoldPlus5` | Chest+Back / Shoulders+Arms / Legs / Upper / Lower | higher-volume hybrid |
| `strengthHypertrophy5` | Squat / Bench / Pull / Deadlift / Overhead + arms | powerbuilding variant |
| `fullBodySpecialization5` | Full / Full / weak-point / Full / Full | one focused accessory day |

### 6-day options

| ID | Sessions | Notes |
|---|---|---|
| `ppl6` | Push / Pull / Legs × 2 | classic six-day PPL |
| `arnold6` | Chest+Back / Shoulders+Arms / Legs × 2 | classic Arnold pairing |
| `upperLower6` | Upper / Lower × 3 | distributes volume into shorter sessions |
| `pushPull6` | Push / Pull × 3 with lower-body quota | only if lower work is explicit |
| `torsoLimbs6` | Torso / Limbs × 3 | high-frequency variant |
| `powerHypertrophy6` | Strength push/pull/legs / Hypertrophy push/pull/legs | goal alternation |

### 7-day and rotating options

| ID | Sessions | Notes |
|---|---|---|
| `pplRestPPL` | Push / Pull / Legs / Rest / Push / Pull / Legs | calendar-shaped PPL |
| `bro6Rest` | Chest / Back / Shoulders / Legs / Arms / Weak point / Rest | advanced bodybuilding style |
| `conjugate4` | Max upper / Max lower / Dynamic upper / Dynamic lower | velocity/intensity changes; requires advanced prescription |
| `fullBodyMicrocycle` | 3–6 full-body sessions in a rolling queue | does not assume Monday–Sunday |
| `upperLowerRolling` | Upper / Lower repeated, rest inserted by recovery | ideal when missed days should slide forward |
| `custom` | user-defined session definitions | always supported as the escape hatch |

The registry should also expose aliases for discoverability: “body-part split” → `bro5`,
“push-pull-legs” → `ppl3` or `ppl6`, “power/hypertrophy upper/lower” → `phul4`, and “Arnold” →
`arnold6`. Aliases must not create duplicate implementations.

## Canonical session focus definitions

These are composable focus IDs used by the split registry and the swap picker:

| Focus ID | Required buckets | Optional / weak buckets |
|---|---|---|
| `push` | chest, shoulders, triceps | abs |
| `pull` | back, traps, biceps | forearms, rear delts/shoulders, lower back |
| `legs` | quads, hamstrings, glutes, calves | abs, lower back |
| `lower` | quads, hamstrings, glutes, calves | abs, lower back |
| `upper` | chest, back, shoulders, biceps, triceps | traps, forearms |
| `fullBody` | at least one upper push, upper pull, knee/hinge pattern | carries/core |
| `chestBack` | chest, back | traps, lower back |
| `shouldersArms` | shoulders, biceps, triceps | forearms |
| `arms` | biceps, triceps | forearms, shoulders |
| `posteriorChain` | hamstrings, glutes, lower back | back, traps, calves |
| `quadGlute` | quads, glutes | calves, hamstrings |
| `hamstringGlute` | hamstrings, glutes | lower back, calves |
| `core` | abs | lower back |
| `conditioning` | conditioning tag | full-body muscles are secondary |
| `power` | power/olympic tag plus a lift pattern | goal metadata decides load |
| `mobilityRecovery` | mobility/recovery tag | region-specific |

Session labels should be resolved from focus metadata, not `session.order`. A generated session
may include a small amount of core or arms without ceasing to be a push, pull, or lower session.
Use weighted overlap with a threshold and fall back to a human-readable muscle list when the
session is genuinely custom.

## Swap compatibility algorithm

### Persisted model

Add (or evolve toward) these concepts in the core package:

```swift
struct CatalogExerciseID: Codable, Hashable, Sendable {
    let source: ExerciseMediaSource
    let value: String
}

struct ExerciseTags: Codable, Equatable, Sendable {
    var movementPatterns: Set<MovementPattern>
    var focusIDs: Set<WorkoutFocusID>
    var role: ExerciseRole
    var confidence: Double
    var provenance: [TagProvenance]
}

struct SplitDefinition: Codable, Equatable, Sendable {
    let id: SplitID
    let displayName: String
    let sessions: [SessionDefinition]
    let aliases: [String]
}
```

The existing `Exercise.id` can remain source-local for compatibility, but any persisted swap,
history record, or cross-catalog join should carry the source. Existing plans can be migrated by
assuming the current bundled source and recording a migration provenance flag.

### Tag derivation (deterministic, explainable)

1. Normalize raw primary and secondary muscles into canonical and optional sub-muscle tags.
2. Parse category and name tokens (`squat`, `hinge`, `deadlift`, `row`, `press`, `curl`, `raise`,
   `carry`, `plank`, `jump`, `run`, `bike`, `stretch`, etc.).
3. Use equipment, mechanic, unilateral marker, and raw force as supporting evidence.
4. Apply an explicit override table for known catalog errors (for example, deadlift/RDL/good
   morning are hinges even if one source says `force = push`).
5. Store provenance and confidence per derived tag. Do not silently promote a low-confidence tag
   to a hard constraint.

Suggested scoring:

```text
score = 0.45 * primary-muscle match
      + 0.20 * secondary-muscle match
      + 0.20 * movement-pattern match
      + 0.10 * mechanic/role match
      + 0.05 * equipment availability
```

For an explicit `push`/`pull` focus, movement pattern and canonical muscle evidence outrank raw
force. For a general `upper` focus, muscle overlap is the dominant signal. For a power or
conditioning session, goal/category tags are required in addition to muscles.

### Query behavior for a day-scoped replacement

Given a day’s effective session and the item being replaced:

1. Derive the day’s `SessionDefinition` and required pattern/role from the original item.
2. Filter out the current exercise, excluded IDs, unavailable equipment, and exercises already in
   the day unless duplicates are explicitly allowed.
3. Require the session’s focus compatibility. For a push day, do not show all upper-body
   exercises; for an upper day, include both push and pull families.
4. Preserve the original item’s intent where possible: compound stays compound, bilateral stays
   bilateral, pattern stays pattern, and primary muscle remains covered.
5. Rank by compatibility score, difficulty proximity, equipment, recent use, and catalog media
   quality. Return a reason such as “same horizontal-push pattern; chest primary; barbell
   available”.
6. If fewer than three candidates pass hard constraints, relax secondary constraints in order:
   exact pattern → role/mechanic → secondary muscle → equipment (only if the user allows it).
   Never relax the session focus or a user injury exclusion.

The same resolver must be used by the Home day editor, Exercises tab, plan editor, AI tools,
history export, and memory layer. This avoids the current failure mode where one screen sees a
focus-filtered list while another uses only `primaryMuscle`.

## Data quality and safety rules

- Keep raw fields (`category`, raw force/mechanic, source, source ID) for auditability.
- Treat force as nullable evidence, not ground truth; the two catalogs demonstrate why.
- Do not map “cardiovascular system” to `quads` semantically. Preserve a `conditioning` tag and
  only project to a muscle bucket for legacy APIs.
- Keep `adductors`, `abductors`, and `hip flexors` distinct in the optional tag layer even though
  the current mapper projects them to `glutes`.
- Separate exercise identity from media identity. A Gym Visual image and a Free-Exercise-DB
  image for similarly named exercises are not automatically the same exercise.
- A split is a scheduling preference, not medical advice. Injury exclusions, recovery gaps, and
  user-entered constraints remain hard guards.
- Plans remain rolling targets. A missed day can move to the next eligible non-rest day, but a
  day-scoped manual swap must not mutate the recurring split.

## Recommended implementation sequence

1. **Core taxonomy types and tests** — `MovementPattern`, `WorkoutFocusID`, `SplitID`, roles,
   `CatalogExerciseID`, tag provenance, and the split registry above.
2. **Raw catalog preservation** — retain category/source metadata while mapping both resources;
   add distribution and known-error fixtures.
3. **Tag resolver** — deterministic rules plus override table, confidence, and explainability.
4. **Compatibility query** — one API returning ranked swap candidates and reasons; replace the
   current primary-muscle-only picker and persistence guard.
5. **Split selector** — expose style × days, with aliases and a custom option; keep existing
   three templates as compatibility aliases.
6. **Consumer migration** — RulePlanBuilder, day-scoped Home editor, Library/Exercise detail,
   AI suggestion tools, proactive insights, export, and memory all call the same resolver.
7. **Focused verification** — catalog fixtures, resolver tests for push/pull/upper/lower/full
   body, source-scoped IDs, missing metadata, and day-only persistence; run only affected Swift
   package/app tests for each change.

## Research notes and sources

1. Ramos-Campo DJ et al., “Efficacy of Split Versus Full-Body Resistance Training on Strength
   and Muscle Growth: A Systematic Review With Meta-Analysis,” *Journal of Strength and
   Conditioning Research* (2024), [PubMed](https://pubmed.ncbi.nlm.nih.gov/38595233/).
2. Schoenfeld BJ, Ogborn D, Krieger JW, “Effects of Resistance Training Frequency on Measures of
   Muscle Hypertrophy,” *Sports Medicine* (2016), [PubMed](https://pubmed.ncbi.nlm.nih.gov/27102172/).
3. Schoenfeld BJ, Grgic J, Krieger JW, “How many times per week should a muscle be trained to
   maximize muscle hypertrophy?” *Journal of Sports Sciences* (2019),
   [PubMed](https://pubmed.ncbi.nlm.nih.gov/30558493/).
4. NSCA, “Progressive Strategies for Teaching Fundamental Resistance Training Movement
   Patterns,” [NSCA](https://www.nsca.com/education/articles/ptq/teaching-resistance-training-movement-patterns/).
5. NSCA, *Personal Training Quarterly* movement-pattern position article (squat, hinge, push,
   pull, lunge, rotation, and additional patterns), [PDF](https://www.nsca.com/globalassets/education/ptq/ptq-5.2.pdf).
6. American College of Sports Medicine, “Progression Models in Resistance Training for Healthy
   Adults,” [PubMed](https://pubmed.ncbi.nlm.nih.gov/11828249/).
7. American College of Sports Medicine, “Resistance Training Prescription for Muscle Function,
   Hypertrophy, and Physical Performance in Healthy Adults: An Overview of Reviews,” [ACSM
   position stands](https://acsm.org/education-resources/pronouncements-scientific-communications/position-stands/).
8. StrengthLog, “The 6 Best Workout Splits to Build Muscle & Strength,” for descriptive coverage
   of full-body, upper/lower, PPL, PPLUL, body-part, and Arnold families,
   [StrengthLog](https://www.strengthlog.com/best-workout-splits/).
9. StrengthLog, “Arnold Split,” for the historical chest/back, shoulders/arms, legs structure,
   [StrengthLog](https://www.strengthlog.com/arnold-split/).
10. Local sources: `docs/11-training-splits-and-muscle-groupings.md`,
    `FitnessCore/Sources/ExerciseCatalog/FreeExerciseDBMapper.swift`,
    `FitnessTracker/FitnessTracker/Catalog/catalog.json`, and
    `FitnessTracker/FitnessTracker/Catalog/free_exercise_db.json`.
