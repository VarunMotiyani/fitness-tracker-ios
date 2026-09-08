# Athlete Profile Design

**Status:** Approved for implementation — Profile slice only

## Goal

Give the athlete one dedicated place to understand and update the information
that shapes training. It must make plan-affecting settings easy to edit,
present body composition without turning the everyday experience into a lab
report, and provide the durable destination that InBody scan ingestion will use
in a follow-up slice.

## Scope

This slice includes a dedicated Profile destination, editable identity and
training preferences, a manually editable body-composition snapshot, and safe
plan regeneration from those preferences.

This slice explicitly does **not** include image capture, photo-library access,
vision extraction, scan-history storage, segmental analysis, charts, or
automatic changes from an InBody report. Those belong to the next slice after
the Profile UI is reviewed.

## Entry and Navigation

Home gains a labelled, accessible profile action. It presents `AthleteProfileView`
in a full-screen sheet inside its own `NavigationStack`; close returns to Home
without changing the selected bottom tab. The action replaces the current
header's separate daily-check-in icon, avoiding four tightly packed icon-only
actions. Daily check-in remains reachable from Home as a visible card/action
in the page content.

Settings retains its compact Athlete Profile summary but routes into the same
`AthleteProfileView`, never a duplicate editor.

## Information Architecture

The screen has three scannable sections and a single primary edit action:

1. **Athlete at a glance** — goal, experience level, current weight, and a
   short training-capacity label. This is summary only; it prioritises the few
   values that explain the plan at a glance.
2. **Training setup** — goal, experience, sessions per week, session length,
   equipment and areas to avoid. These are the exact values used by
   `UserProfile.makeUserContext()` when a plan is generated.
3. **Body composition** — manually entered current measurements. The overview
   uses a small metrics grid for the useful-at-a-glance values (weight, body-fat
   percentage, skeletal muscle mass, and BMR) and a separate detail row for the
   rest. Empty measurements use an intentional "Add measurement" affordance;
   they are never displayed as `0` or as fabricated demo data.

An `Edit profile` action opens a native form with section headers and labels.
It groups fields as Identity, Training, and Body composition, uses decimal
keyboards for measurements, keeps unit suffixes visible, and saves all edits in
one transaction. Every editable control has a descriptive VoiceOver label.

## Persisted Profile Data

`UserProfile` remains the sole current-profile record. Existing fields remain
unchanged. The following optional `Double` fields are added so a manual entry
and a future confirmed scan update the exact same state:

| Group | Fields |
| --- | --- |
| Core composition | `bodyFatPercent`, `skeletalMuscleMassKg`, `bodyFatMassKg`, `fatFreeMassKg` |
| Body composition analysis | `totalBodyWaterL`, `proteinKg`, `mineralKg` |
| Metabolic and risk metrics | `basalMetabolicRateKcal`, `visceralFatLevel`, `inBodyScore`, `waistHipRatio`, `phaseAngleDegrees` |

Height, birth year, and sex are manual-only. The current profile's `weightKg`
is the fallback reading; a new confirmed manual weight also writes one dated
`BodyweightEntryModel` so the existing chart and future scan history agree.

BMI is derived from current weight and height; it is displayed but never stored.
Target weight, weight-control recommendation, and segmental measurements are
scan-specific rather than durable profile defaults, so they are deferred to the
scan-history slice.

## Plan Update Behaviour

Training fields affect future plan generation but do not silently replace the
already visible plan. After a save that changes any plan input, the Profile
screen shows a clear `Regenerate weekly plan` call to action. Choosing it calls
the existing `generateAndStore(context:activeProfile:catalog:modelContext:)`
path with `profile.makeUserContext()`.

The Plan tab remains the place for manual routine and weekday edits. Profile
therefore changes the planner's constraints and regenerates the weekly plan;
it does not attempt to mutate individual sessions behind the user's back.

## Visual and Interaction Direction

The screen follows PulseAI's black/surface/surface2 dark palette and the user's
selected accent colour. It uses the system font with Dynamic Type instead of a
new sport font, semantic text colours, and SF Symbols. The visual hierarchy is
one generous hero card, compact metric tiles, and lower-density preference rows;
there are no repeated giant cards or paragraph blocks. Tappable controls meet
44pt minimum targets. Save state is explicit: disabled while invalid/saving,
then a short success confirmation. No important information depends on colour
alone.

## Follow-up: InBody Scan Ingestion

The next slice adds an InBody area inside Profile with camera and photo-library
entry points. A selected report is sent to a vision-capable provider, then a
review screen shows the extracted values before one confirmation:

`report photo → extracted fields → athlete review/correction → confirm → scan
history + UserProfile snapshot + bodyweight timeline`

The reference report establishes the scan schema: date, weight, PBF, SMM,
body-fat mass, total body water, protein, mineral, BMR, visceral fat, InBody
score, waist–hip ratio, phase angle, and segmental lean/fat details. Only a
confirmed scan changes current profile fields. Segmental history and automatic
programming signals remain scan-history concerns, not Profile-slice concerns.

## Error Handling and Validation

- Numeric composition values are optional and must be finite, non-negative.
- Percentage values are constrained to 0...100; waist–hip ratio and phase angle
  must be positive.
- Height must be positive, sessions per week remains 2...7, and session length
  remains one of the app's supported choices.
- If plan generation fails, existing saved plan remains intact and the Profile
  screen presents the outcome from the existing generation path.

## Verification

- Unit tests cover profile update validation, bodyweight timeline write-on-save,
  and the exact plan-generation context after editing training fields.
- A focused SwiftData round-trip confirms new optional fields survive storage.
- Manual simulator review covers compact and large Dynamic Type, dark mode,
  edit/save feedback, Home and Settings entry points, and plan regeneration.
