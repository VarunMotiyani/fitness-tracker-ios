# 07 — Exercise Dataset Research

_Date: 2026-08-27 · Web research for open question Q1_

Goal: pick the exercise catalog source. Requirement from the design — the catalog
is **bundled into the app** and works **fully offline**, no backend
([06-decisions.md](06-decisions.md) A2), single user. So the source must be
**downloadable and redistributable**, not a hosted API.

## Options compared

| Source | Count | Media | License | Bundleable? |
|--------|------:|-------|---------|-------------|
| **`yuhonas/free-exercise-db`** | ~873 | static start/end **JPGs** (0–2 per exercise) | **Unlicense** (public domain, no attribution) | ✅ yes, no strings |
| `wger` (wger-project) | ~845 | some images, few animations | **CC-BY-SA 3.0/4.0** (attribution + share-alike) | ⚠️ yes, with attribution + share-alike obligations |
| `exercemus/exercises` | ~800+ | mixed | curated from wger + exercises.json, mixed permissive | ⚠️ depends on entry |
| `hasaneyldrm/exercises-dataset` | 1,324 | **animated GIFs** + thumbnails (180×180), 10 languages | code/text MIT; **media © GymVisual**, "with permission" only | ❌ media needs a separate paid GymVisual licence |
| **ExerciseDB** (`exercisedb.dev` / RapidAPI) | 11,000+ (many variations) | ~20k images, ~5k GIFs, ~15k videos | API code AGPL-3.0; **media proprietary**, hosted-API / hotlink model | ❌ API-access only; permanent caching/bundling not permitted |
| MuscleWiki | large | high-quality video/GIF | proprietary; scraped copies on GitHub are unlicensed | ❌ |

### Notes on the count leader (ExerciseDB)

- Biggest raw catalog and one of the few with animated demos.
- Distributed as a **hosted API** (mainly via RapidAPI, also `exercisedb.dev`).
  No official bulk download.
- Approximate pricing (RapidAPI-controlled, changes often):
  - Free: ~10 requests/day, flagged "not for production"
  - ~$10–15/mo for ~3,000 requests
  - ~$25–35/mo for ~10,000 requests
  - $50+/mo above that
- Figures are from ExerciseDB's own pages and a competitor comparison
  (WorkoutX) — treat as rough.
- **Why it's the wrong fit regardless of price:** it assumes an app with a
  backend that proxies and caches calls, with hotlinked media. Our app is
  offline-first with the catalog in the bundle and no server. Using it properly
  would mean adding a backend (violates A2) and paying a subscription forever so
  one person can fetch data that never changes; caching the media to go offline
  breaks the API terms.

## Decision

**Base = `yuhonas/free-exercise-db`.** It is the most comprehensive dataset that
is genuinely free to download, redistribute, and bundle — which the architecture
requires. Static start/end frames are enough for "how do I do this" at a glance.

- **Gap-filler:** `wger` entries (with an attribution file) only if the curated
  subset has holes. ([06-decisions.md](06-decisions.md) C3)
- **Animated-demo upgrade path:** a **one-time media licence** (GymVisual-class,
  the media behind ExerciseDB / `hasaneyldrm`) swapped into the app's media layer
  later. The `Exercise` schema separates media refs from exercise data
  specifically so this drops in without touching planning or validation.
  ([06-decisions.md](06-decisions.md) C5)
- **Not** an ongoing hosted-API subscription (ExerciseDB) — wrong architecture
  and wrong cost model for a personal offline app.

## To do when the catalog is built

- Commit the source license text(s) into the repo.
- Record which entries (if any) came from `wger` and add the CC-BY-SA
  attribution file.
- Curate the ~100–150-exercise subset from Varun's equipment checklist (Q2).
- Decide image compression / bundle-size budget (Q3).

## Sources

- <https://github.com/yuhonas/free-exercise-db>
- <https://github.com/wger-project/wger>
- <https://github.com/exercisedb/exercisedb-api>
- <https://github.com/hasaneyldrm/exercises-dataset>
- <https://github.com/exercemus/exercises>
- <https://workoutxapp.com/blog/workoutx-vs-exercisedb.html>
