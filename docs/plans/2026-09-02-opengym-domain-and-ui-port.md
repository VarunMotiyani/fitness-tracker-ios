# openGym Domain Logic & Gym-Floor UI Port — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Follow the SDD ledger process in `.superpowers/sdd/2026-09-02-opengym-domain-and-ui-port/`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port openGym's battle-tested gym mechanics, domain logic, and tactile UI/UX into the native Swift iOS project (`FitnessCore` package + `FitnessTracker` app), while integrating seamlessly with the proactive AI layer (`PlanCoordinator`, `SessionFinalizer`, `CoachMemory`, InBody vision).

**Architecture:**
1. **`FitnessCore/Metrics`**: Pure Swift models for `PlateMath`, `RecoveryModel` (36h half-life exponential fatigue decay + 14d strength retention), Set Intensifiers (`DropSetEntry`, `RestPauseCluster`), and multi-policy `ProgressionRule`s (Double Progression, Greyskull LP AMRAP, and deload rules).
2. **`FitnessTracker/Models` & `Metrics`**: SwiftData `@Model` mappings for set intensifiers and `SwiftDataMetricsRepository` integration with `RecoveryModel`.
3. **`FitnessTracker/Features` (SwiftUI)**: Front/Back anatomical vector `MuscleMapView`, gym-floor `.subrow` steppers for drop-sets/rest-pause in `SessionFocusView`, `PlateMathSheet`, rest timer screen flash, and `ActivityHeatmapView`.
4. **AI Layer Integration**: Injecting real-time muscle fatigue scores into AI session finalization prompts.

**Constraints:**
- No git commits, no git push. All changes stay local on the current branch.
- `FitnessCore` remains strictly UI-framework-free (pure Swift Testing).
- App target default actor isolation is `@MainActor`.

---

## Tasks

- [x] **Task 1: `PlateMath` (Barbell & Plate Loading Calculator)**
  - Produces: `PlateMath.swift` in `FitnessCore/Sources/Metrics/`, unit tests in `PlateMathTests.swift`.
  - Capabilities: Olympic, Women's, EZ, Trap, and Smith machine bars; kg and lb plate loading breakdown.

- [x] **Task 2: `RecoveryModel` (Fatigue & Muscle Recovery Decay)**
  - Produces: `RecoveryModel.swift` in `FitnessCore/Sources/Metrics/`, unit tests in `RecoveryModelTests.swift`.
  - Capabilities: 36h exponential half-life decay, $1-\exp(-\text{stimulus}/\text{REF})$ saturation, strength retention decay, `ready`/`recovering`/`fatigued` muscle state classification.

- [ ] **Task 3: Set Intensifiers & Multi-Policy Progression in `FitnessCore`**
  - Modify: `MetricSnapshots.swift` (add `DropSetEntry`, `RestPauseCluster`, snapshot properties).
  - Modify: `ProgressionRule.swift` (Double Progression across rep ranges, Greyskull LP AMRAP rules, deload triggers).
  - Tests: `ProgressionRuleTests.swift` & `MetricSnapshotsTests.swift`.

- [ ] **Task 4: SwiftData Model Mapping & Repository Updates in `FitnessTracker`**
  - Modify: `SessionModels.swift` (`LoggedSetModel` storage for drops/clusters).
  - Modify: `ModelSnapshotMapping.swift` (round-trip mappings).
  - Modify: `SwiftDataMetricsRepository.swift` (expose recovery status method).
  - Tests: `ModelSnapshotMappingTests.swift`.

- [ ] **Task 5: Front & Back Vector Muscle Map (`MuscleMapView.swift`)**
  - Create: `BodyVectorData.swift` (Anterior and Posterior SVG vector paths for 16 muscle groups).
  - Create: `MuscleMapView.swift` (Interactive SwiftUI component with Fatigue & Volume Balance modes).

- [ ] **Task 6: Plate Math Sheet & Inline Set Steppers in `SessionFocusView`**
  - Create: `PlateMathSheet.swift` (visual plate rack).
  - Modify: `SessionFocusView.swift` (inline plate math trigger, drop-set and rest-pause `.subrow` steppers).

- [ ] **Task 7: Activity Heatmap & Rest Timer Screen Flash**
  - Modify: `RestTimerView.swift` (screen flash & haptic alert).
  - Create: `ActivityHeatmapView.swift` (52-week GitHub-style activity grid).

- [ ] **Task 8: AI Session Coach Integration & Verification**
  - Connect `RecoveryModel` into `SessionFinalizer` prompt context.
  - Run full test suite regression (`swift test` & `xcodebuild test`).
