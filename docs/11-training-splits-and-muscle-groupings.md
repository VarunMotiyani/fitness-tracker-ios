# Training Splits & Muscle Groupings — Research

**Date:** 2026-09-10
**Why:** The app labels sessions "Push Day / Pull Day / Legs Day" purely by `session.order`,
which is a lie for any plan that isn't a 6-day PPL split (a 4-day `upperLower4` plan calls its
Upper session "Push Day", and the day-scoped exercise picker then shows the whole upper body).
This doc collects the well-known splits and the canonical muscle-per-session groupings so we can
(a) name a session honestly from its `focusMuscles`, and (b) add more templates.

All muscle names below are mapped onto the app's 13-case `MuscleGroup` enum:
`chest, back, lowerBack, traps, shoulders, biceps, triceps, forearms, quads, hamstrings, glutes, calves, abs`.
(The app has no separate front/side/rear delts, no lats-vs-mid-back, no adductors — `shoulders`
and `back` are the coarse buckets.)

---

## 1. The movement-pattern buckets

Every split is built by slicing the body one of two ways: **by movement** (push / pull / legs) or
**by region** (upper / lower). Everything else is a recombination.

| Bucket | Muscles (app enum) | Rationale |
|---|---|---|
| **Push** | `chest`, `shoulders`, `triceps` | Muscles that extend the elbow / flex or abduct the shoulder — they cooperate on presses. |
| **Pull** | `back`, `traps`, `biceps`, `forearms`, (rear delts → `shoulders`) | Muscles that flex the elbow / adduct-extend the shoulder — they cooperate on rows & pulldowns. Rear delts are trained on pull day even though the app files them under `shoulders`. |
| **Legs / Lower** | `quads`, `hamstrings`, `glutes`, `calves`, (`abs`, `lowerBack`) | Everything below the waist. Core is usually bolted onto leg day. |
| **Upper** | Push ∪ Pull = `chest`, `back`, `traps`, `shoulders`, `biceps`, `triceps`, `forearms` | Everything above the waist. |
| **Full body** | all 13 | One session touches every pattern: squat, hinge, h-push, v-push, h-pull, v-pull. |
| **Core / Abs** | `abs`, `lowerBack` | Rarely its own day; appended to legs or a "shoulders & abs" day. |

**Movement patterns** a well-formed session covers (used to sanity-check a generated plan):
squat (knee-dominant), hinge (hip-dominant), horizontal push, vertical push, horizontal pull,
vertical pull, plus optional single-leg, carry, and core.

Sources: [Hevy — PPL guide](https://www.hevyapp.com/push-pull-legs-ultimate-guide/),
[A Workout Routine — full-body split](https://www.aworkoutroutine.com/full-body-split/),
[GarageGymReviews — PPL](https://www.garagegymreviews.com/push-pull-legs-routine).

---

## 2. The famous splits

### 2.1 Full Body — 2–4 days/week

Every session trains the whole body. Best frequency-per-effort ratio; the default for beginners
and time-crunched lifters. Run as **A/B alternating** (A-B-A one week, B-A-B the next) on
non-consecutive days.

| Session | Focus muscles | Canonical exercises |
|---|---|---|
| **Full A** | all | Back Squat, Bench Press, Barbell Row (± Leg Curl, Biceps Curl, Face Pull) |
| **Full B** | all | Deadlift *or* Romanian Deadlift, Overhead Press, Pull-Up / Lat Pulldown (± Leg Press, Lateral Raise, Triceps Pushdown, Calf Raise) |

- **Rule:** one exercise per movement pattern — a knee-dominant, a hip-hinge, an upper push, an
  upper pull; 3–7 exercises/session.
- **Classic barbell versions:** StrongLifts 5×5 (A: Squat/Bench/Row; B: Squat/OHP/Deadlift),
  Starting Strength (3×5 + power clean), GZCLP (4 day, T1 Squat/Bench/Dead/OHP + T2 + T3).

Sources: [A Workout Routine — full-body](https://www.aworkoutroutine.com/full-body-split/),
[StrongLifts 5×5](https://stronglifts.com/stronglifts-5x5/workout-program/),
[Boostcamp — GZCLP](https://www.boostcamp.app/coaches/cody-lefever/gzcl-program-gzclp),
[Crunch — full-body strength](https://www.crunch.com/thehub/most-effective-full-body-strength-routine/).

### 2.2 Upper / Lower — 4 days/week (also 2 or 6)

Split by region. Each muscle hit ~2×/week. The **most recommended intermediate split** and what
the app's `upperLower4` template already is.

| Session | Focus muscles | Canonical exercises |
|---|---|---|
| **Upper** | `chest`, `back`, `traps`, `shoulders`, `biceps`, `triceps`, `forearms` | Bench / Incline Press, Barbell or Pendlay Row, Overhead Press, Pull-Up / Lat Pulldown, Lateral Raise, Biceps Curl, Triceps Extension |
| **Lower** | `quads`, `hamstrings`, `glutes`, `calves`, `abs` | Back Squat, Romanian Deadlift / Deadlift, Leg Press or Hack Squat, Leg Curl, Leg Extension, Standing + Seated Calf Raise, Cable Crunch |

- 4-day layout: Upper / Lower / rest / Upper / Lower / rest / rest.
- Often periodised: first Upper/Lower of the week heavy (3–6 reps), second lighter (8–15).

Sources: [Legion — PPLUL](https://legionathletics.com/pplul/),
[StrengthLog — PPLUL](https://www.strengthlog.com/pplul-split/),
[Sole — PPL vs Upper/Lower](https://www.soletreadmills.com/blogs/news/ppl-vs-upper-lower-split-which-is-more-effective).

### 2.3 Push / Pull / Legs (PPL) — 3 or 6 days/week

Split by movement. 3-day = each pattern 1×/week (beginner-friendly); 6-day = 2×/week
(the classic bodybuilding hypertrophy split). The app's `pushPullLegs6` template.

| Session | Focus muscles | Canonical exercises |
|---|---|---|
| **Push** | `chest`, `shoulders`, `triceps` | Bench Press, Incline Dumbbell Press, Seated Shoulder Press, Cable Fly, Lateral Raise, Triceps Pushdown / Overhead Extension |
| **Pull** | `back`, `traps`, `biceps`, `forearms` (+ rear delts) | Deadlift *or* Barbell Row, Lat Pulldown, Seated Cable Row, Shrug, Face Pull, Barbell / Dumbbell Curl |
| **Legs** | `quads`, `hamstrings`, `glutes`, `calves` (+ `abs`) | Back Squat, Romanian Deadlift, Leg Press, Leg Extension, Leg Curl, Calf Raise, Hanging Leg Raise / Cable Crunch |

- 6-day layout: Push / Pull / Legs / Push / Pull / Legs / rest.
- 3-day layout: Push / rest / Pull / rest / Legs / rest / rest.

Sources: [Hevy — PPL guide](https://www.hevyapp.com/push-pull-legs-ultimate-guide/),
[A Workout Routine — PPL](https://www.aworkoutroutine.com/push-pull-legs-split/),
[Transparent Labs — PPL](https://www.transparentlabs.com/blogs/all/push-pull-legs-routine-guide-to-ppl).

### 2.4 PPLUL (Push / Pull / Legs / Upper / Lower) — 5 days/week

Splices PPL and Upper/Lower so 5 training days each get a distinct session; each muscle ~2×/week.
Common as PPL = hypertrophy focus, Upper/Lower = strength focus.

`Mon Push · Tue Pull · Wed Legs · Thu Upper · Fri Lower`

Sources: [Hevy — PPLUL](https://www.hevyapp.com/pplul-split/),
[StrengthLog — PPLUL](https://www.strengthlog.com/pplul-split/),
[GymGeek — ULPPL](https://gymgeek.com/workout-routines/ulppl-split/).

### 2.5 Bro Split / Body-Part Split — 5 days/week

One muscle group per day, high volume, low frequency (~1×/week each). Still popular; produces
real growth but is generally beaten by 2×/week frequency for naturals.

`Mon Chest · Tue Back · Wed Shoulders · Thu Legs · Fri Arms`

| Day | Focus muscles | Canonical exercises |
|---|---|---|
| **Chest** | `chest` (+ `triceps` secondary) | Bench, Incline Press, Dip, Cable Fly, Pec-Deck |
| **Back** | `back`, `traps`, `lowerBack` (+ `biceps`) | Deadlift, Pull-Up, Barbell Row, Seated Row, Lat Pulldown, Shrug |
| **Shoulders** | `shoulders` (± `abs`) | Overhead Press, Arnold Press, Lateral Raise, Rear-Delt Fly, Upright Row, Face Pull |
| **Legs** | `quads`, `hamstrings`, `glutes`, `calves` | Squat, Leg Press, Lunge, RDL, Leg Curl, Leg Extension, Calf Raise |
| **Arms** | `biceps`, `triceps`, `forearms` | Close-Grip Bench, Barbell Curl, Skull Crusher, Preacher Curl, Pushdown, Hammer Curl, Wrist Curl |

Sources: [Outlift — bro split](https://outlift.com/the-perfect-bro-split-workout-routine/),
[Legion — bro split](https://legionathletics.com/bro-split/),
[SET FOR SET — bro split](https://www.setforset.com/blogs/news/bro-split).

### 2.6 Arnold Split — 6 days/week

Chest+Back / Shoulders+Arms / Legs, each pair 2×/week. Like PPL but pulls arms & shoulders out
of push/pull day and trains them fresh; very high volume.

`Chest+Back · Shoulders+Arms · Legs · Chest+Back · Shoulders+Arms · Legs · rest`

| Session | Focus muscles |
|---|---|
| **Chest & Back** | `chest`, `back`, `traps`, `lowerBack` |
| **Shoulders & Arms** | `shoulders`, `biceps`, `triceps`, `forearms` |
| **Legs** | `quads`, `hamstrings`, `glutes`, `calves` (+ `abs`) |

Sources: [StrengthLog — Arnold split](https://www.strengthlog.com/arnold-split/),
[Liftosaur — Arnold split](https://www.liftosaur.com/programs/arnold-split).

### 2.7 Torso / Limbs — 4 days/week

Arnold's cut of the body: **torso** = chest + back; **limbs** = shoulders + arms + legs.

| Session | Focus muscles |
|---|---|
| **Torso** | `chest`, `back`, `traps`, `lowerBack` |
| **Limbs** | `shoulders`, `biceps`, `triceps`, `forearms`, `quads`, `hamstrings`, `glutes`, `calves` |

Source: [Chris Adams PT — Torso/Limbs](https://www.chrisadamspersonaltraining.com/torso/limbs-split).

### 2.8 PHUL — Power Hypertrophy Upper Lower — 4 days/week

Upper/Lower run twice: once heavy (power), once high-volume (hypertrophy).

`Upper Power · Lower Power · rest · Upper Hypertrophy · Lower Hypertrophy`

Focus muscles are identical to the Upper / Lower rows in §2.2; only the rep ranges differ
(3–6 on power days, 8–15 on hypertrophy days).

Source: [PHUL app listing](https://apps.apple.com/bf/app/phul-workout-split-routine/id1104097770).

### 2.9 PHAT — Power Hypertrophy Adaptive Training (Layne Norton) — 5 days/week

Two power days (whole upper / whole lower), three hypertrophy days split like a bro split.

| Day | Name | Focus muscles | Sample exercises (sets × reps) |
|---|---|---|---|
| 1 | **Upper Power** | `chest`,`back`,`traps`,`shoulders`,`biceps`,`triceps` | Bent-Over/Pendlay Row 3×3-5, Weighted Pull-Up 2×6-10, DB Bench 3×3-5, Weighted Dip 2×6-10, DB Shoulder Press 3×6-10, EZ-Bar Curl 3×6-10, Skullcrusher 3×6-10 |
| 2 | **Lower Power** | `quads`,`hamstrings`,`glutes`,`calves` | Squat 3×3-5, Hack Squat 2×6-10, Leg Extension 2×6-10, Stiff-Leg Deadlift 3×5-8, Leg Curl 2×6-10, Standing + Seated Calf Raise |
| 3 | Rest | — | — |
| 4 | **Back & Shoulders Hypertrophy** | `back`,`traps`,`shoulders` | Row 4×8-10, Rack Chin 3×8-12, Seated Cable Row 3×8-12, DB Row/Shrug 2×12-15, Close-Grip Pulldown 2×15-20, DB Shoulder Press 3×8-12, Upright Row 2×12-15, Lateral Raise 3×12-20 |
| 5 | **Lower Hypertrophy** | `quads`,`hamstrings`,`glutes`,`calves` | Squat 4×8-10, Hack Squat 3×8-12, Leg Press 2×12-15, Leg Extension 3×15-20, RDL 3×8-12, Lying + Seated Leg Curl, Calf Raise ×2 |
| 6 | **Chest & Arms Hypertrophy** | `chest`,`biceps`,`triceps` | DB Bench 4×8-10, Incline DB Press 3×8-12, Machine Chest Press 3×12-15, Cable Fly 2×15-20, Preacher Curl 3×8-12, Concentration Curl 2×12-15, Spider Curl 2×15-20, Single-Arm Tri Extension 3×8-12, Pushdown 2×12-15, Cable Kickback 2×15-20 |
| 7 | Rest | — | — |

Sources: [Hevy — PHAT](https://www.hevyapp.com/phat-workout/),
[StrengthLog — PHAT](https://www.strengthlog.com/phat-workout-routine/),
[BarBend — PHAT](https://barbend.com/phat-training/).

### 2.10 Classic barbell strength programs (for reference)

| Program | Days | Structure |
|---|---|---|
| **StrongLifts 5×5** | 3 (A/B alt) | A: Squat 5×5, Bench 5×5, Row 5×5 · B: Squat 5×5, OHP 5×5, Deadlift 1×5 |
| **Starting Strength** | 3 (A/B alt) | A: Squat, Bench, Deadlift · B: Squat, Press, Power Clean (all 3×5) |
| **GZCLP** | 4 (A/B) | T1 Squat/Bench/Dead/OHP 5×3+ · T2 accessory compound · T3 isolation 3×15+ |
| **5/3/1** | 3–4 | one main lift/day (Squat, Bench, Deadlift, OHP) on % of training max + accessories (BBB / triumvirate / jack shit templates) |

Source: [Boostcamp — GZCLP](https://www.boostcamp.app/coaches/cody-lefever/gzcl-program-gzclp),
[RPE Training — StrongLifts calculator](https://rpetraining.com/stronglifts-5x5-calculator).

---

## 3. Session archetype → focus-muscle set (the data the app needs)

Match a generated session's `Set(focusMuscles)` against these to get an honest name. Order the
checks most-specific first; fall back to a joined muscle list.

| Archetype | `focusMuscles` set (app enum) | Label |
|---|---|---|
| Push | `{chest, shoulders, triceps}` | "Push Day" |
| Pull | `{back, biceps, traps}` or `{back, biceps, traps, forearms}` | "Pull Day" |
| Legs | `{quads, hamstrings, glutes, calves}` | "Legs Day" |
| Lower (+core) | `{quads, hamstrings, glutes, calves, abs}` | "Lower Day" |
| Upper | `{chest, back, shoulders, biceps, triceps}` (± `traps`, `forearms`) | "Upper Day" |
| Full body | ≥ 3 of {`chest`,`back`,`shoulders`} **and** ≥ 2 of {`quads`,`hamstrings`,`glutes`} | "Full Body" |
| Chest & Back | `{chest, back}` (± `traps`, `lowerBack`) | "Chest & Back" |
| Shoulders & Arms | `{shoulders, biceps, triceps}` (± `forearms`) | "Shoulders & Arms" |
| Arms | `{biceps, triceps}` (± `forearms`) | "Arm Day" |
| Chest | `{chest}` | "Chest Day" |
| Back | `{back}` or `{back, traps}` (± `lowerBack`) | "Back Day" |
| Shoulders | `{shoulders}` (± `abs`) | "Shoulder Day" |
| Core | `{abs}` or `{abs, lowerBack}` | "Core Day" |
| _fallback_ | anything else | `focusMuscles.map(label).joined(", ")` |

Notes:
- Match by **subset / superset with tolerance**, not `==` — a generated Push day might also list
  `abs`. Suggested rule: pick the archetype whose muscle set has the highest Jaccard overlap
  with the session's set, above a 0.6 threshold; else fall back.
- "Legs" vs "Lower" is just whether `abs` is present. Either label is fine; pick one and be
  consistent with the template that produced it.
- Rear delts: the app buckets them in `shoulders`, so a "Pull Day" that includes rear-delt work
  will still list `shoulders` in some generators. Treat `shoulders` as a *weak* signal for Pull.

---

## 4. Canonical exercise library per muscle group

Compound (multi-joint) listed first, then isolation. Use for the day-scoped exercise picker's
"compatible" filter and for template population.

**Chest** — Flat/Incline/Decline Barbell & Dumbbell Bench Press · Machine Chest/Hammer-Strength Press ·
Weighted Dip (forward lean) · Push-Up · Cable Crossover / Cable Fly (low/mid/high) · Dumbbell Fly ·
Pec-Deck.

**Back** (lats + mid-back) — Deadlift · Pull-Up / Chin-Up · Lat Pulldown (wide / close / neutral) ·
Barbell / Pendlay / T-Bar Row · Dumbbell Row · Seated Cable Row · Chest-Supported Row (DB / machine) ·
Inverted Row · Straight-Arm Pulldown.

**Traps** — Barbell / Dumbbell / Trap-Bar Shrug · Upright Row · Face Pull · Farmer's Carry ·
(heavy Deadlift & Rack Pull).

**Lower back / erectors** — Deadlift · Romanian Deadlift · Good Morning · Back Extension /
Hyperextension · Cable Pull-Through · loaded Carry.

**Shoulders** (front / side / rear delts) — Overhead Press (barbell / dumbbell / machine) ·
Push Press · Arnold Press · Lateral Raise (DB / cable / machine) · Front Raise ·
Rear-Delt Fly / Reverse Pec-Deck · Face Pull · Upright Row.

**Biceps** — Barbell / EZ-Bar Curl · Dumbbell Curl (standing / seated / incline) · Hammer Curl ·
Preacher Curl · Concentration Curl · Cable Curl · Spider Curl · Chin-Up.

**Triceps** — Close-Grip Bench Press · Weighted Dip (upright) · Skull Crusher / Lying Extension ·
Overhead Extension (barbell / DB / cable) · Cable Pushdown (bar / rope) · Kickback · Bench Dip ·
Diamond Push-Up.

**Forearms** — Wrist Curl / Reverse Wrist Curl · Reverse Curl · Hammer Curl · Farmer's Carry ·
Dead Hang · Plate Pinch · Wrist Roller.

**Quads** — Back Squat · Front Squat · Hack Squat / Machine Squat · Leg Press · Bulgarian Split
Squat · Walking Lunge · Step-Up · Leg Extension.

**Hamstrings** — Romanian Deadlift · Stiff-Leg Deadlift · Sumo / Conventional Deadlift ·
Good Morning · Glute-Ham Raise · Lying / Seated Leg Curl · Nordic Curl · Cable Pull-Through.

**Glutes** — Hip Thrust · Glute Bridge · Romanian Deadlift · Sumo Deadlift · Bulgarian Split
Squat · Walking Lunge · Step-Up · Cable Kickback · Cable Pull-Through · Back Extension.

**Calves** — Standing Calf Raise (machine / Smith / barbell) · Seated Calf Raise ·
Leg-Press Calf Raise · Donkey Calf Raise · single-leg DB Calf Raise.

**Abs / core** — Hanging Leg / Knee Raise · Cable Crunch · Ab-Wheel Rollout · Plank / Side Plank ·
Weighted Crunch · Bicycle Crunch · V-Up · Russian Twist · Pallof Press · Dead Bug · Hollow Hold.

Sources: [A Workout Routine — exercises per muscle](https://www.aworkoutroutine.com/list-of-exercises-for-each-muscle-group/),
[Styrki — exercises by muscle](https://styrki.com/exercise-library/muscles),
[TTrening — 12 major muscle groups](https://ttrening.com/learn/articles/muscle-groups-explained),
[Planet Fitness — glute exercises](https://www.planetfitness.com/blog/articles/12-best-glute-exercises-for-beginners),
[TODAY — 25 core exercises](https://www.today.com/health/diet-fitness/core-exercises-rcna240119).

---

## 5. Recommendations for the app

1. **Honest session naming.** Replace the `order`-based `WorkoutDayPresentation.title` /
   `HomeView` "Push/Pull/Legs" hardcoding with a `sessionArchetype(focusMuscles:) -> String`
   using the §3 table (highest-overlap match, 0.6 threshold, else joined muscle list). One
   helper, consumed by Home, the day sheet, the week strip, and export.

2. **Contextual picker scope.** The day-scoped "add / replace exercise" filter should match on
   the session's archetype bucket (§1), not the raw `focusMuscles` list — e.g. a Push session
   filters to `{chest, shoulders, triceps}` primary muscles, so a `upperLower4` "Upper Day"
   correctly shows the full upper body while a `pushPullLegs6` "Push Day" stays push-only.
   Keep the looser primary-or-secondary check only for the persistence guard.

3. **New `SplitTemplate`s worth adding** (all expressible with the current 13-case enum):
   - `pushPull4` — `[push, pull, push, pull]` (legs folded into pull via hamstrings/glutes? no —
     skip unless we add a leg day; PPL is better at 3).
   - `pushPullLegs3` — `[push, pull, legs]` (currently only the 6-day version exists).
   - `bro5` — `[chest+triceps, back+biceps, shoulders+abs, legs, arms]`.
   - `arnold6` — `[chestBack, shouldersArms, legs, chestBack, shouldersArms, legs]`.
   - `phul4` / `phat5` — same focuses as Upper/Lower and Bro, distinguished by rep-range metadata.
   - `fullBody2` — `[fullBody, fullBody]` for a 2-day option.

4. **`TemplateSelector`** currently only branches on `sessionsPerWeek` (≤3 → full body, 4 →
   upper/lower, ≥5 → PPL6). Consider letting the athlete pick a *style* (full-body / upper-lower /
   PPL / bro / classic-strength) and mapping (style × days) → template, instead of inferring.

5. **Focus-muscle hygiene in `RulePlanBuilder`.** It already sets `focusMuscles: sessionMuscles`
   from the template, so once templates are named correctly this is consistent. For AI-generated
   plans (`PlanDTO`), validate/repair `focusMuscles` against the nearest archetype so the picker
   and labels don't drift.
