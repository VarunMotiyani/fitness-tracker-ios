import Foundation
import FitnessDomain

public enum ExerciseRole: String, Codable, CaseIterable, Hashable, Sendable {
    case primary, accessory, conditioning, mobility, unknown
}

public struct ExerciseTags: Codable, Equatable, Hashable, Sendable {
    public let movementPatterns: Set<MovementPattern>
    public let focusIDs: Set<WorkoutFocusID>
    public let role: ExerciseRole
    public let confidence: Double

    public init(movementPatterns: Set<MovementPattern>, focusIDs: Set<WorkoutFocusID>,
                role: ExerciseRole, confidence: Double) {
        self.movementPatterns = movementPatterns
        self.focusIDs = focusIDs
        self.role = role
        self.confidence = confidence
    }
}

/// Derives a conservative, explainable taxonomy from the normalized catalog record. Raw
/// `force` is supporting evidence only: one bundled source labels many hinges as push.
public enum ExerciseTaxonomy {
    public static func tags(for exercise: Exercise) -> ExerciseTags {
        let name = exercise.name.lowercased()
        var patterns = Set<MovementPattern>()

        if containsAny(name, ["deadlift", "romanian", "stiff leg", "stiff-leg", "good morning", "hip thrust", "glute bridge", "pull through", "pull-through", "swing"]) {
            patterns.insert(.hipHinge)
        }
        if containsAny(name, ["squat", "leg press", "hack squat", "wall sit"]) {
            patterns.insert(.kneeDominant)
        }
        if containsAny(name, ["lunge", "split squat", "step-up", "step up", "pistol"]) {
            patterns.insert(.singleLeg)
        }
        if containsAny(name, ["bench press", "push-up", "push up", "chest press", "chest fly", "chest flye", "dip"]) {
            patterns.insert(.horizontalPush)
        }
        if containsAny(name, ["overhead press", "shoulder press", "military press", "arnold press", "push press", "landmine press"]) {
            patterns.insert(.verticalPush)
        }
        if containsAny(name, ["row", "reverse fly", "rear delt", "face pull", "face-pull"]) {
            patterns.insert(.horizontalPull)
        }
        if containsAny(name, ["pull-up", "pull up", "chin-up", "chin up", "lat pulldown", "pulldown", "pulldown", "pullover"]) {
            patterns.insert(.verticalPull)
        }
        if containsAny(name, ["carry", "farmer", "suitcase", "waiter walk", "dead hang", "hold"] ) {
            patterns.insert(.carry)
        }
        if containsAny(name, ["plank", "ab wheel", "rollout", "dead bug", "hollow hold"]) {
            patterns.insert(.antiExtension)
        }
        if containsAny(name, ["pallof", "anti-rotation", "anti rotation", "suitcase carry"]) {
            patterns.insert(.antiRotation)
        }
        if containsAny(name, ["side plank", "side bend", "lateral flexion"]) {
            patterns.insert(.antiLateralFlexion)
        }
        if containsAny(name, ["russian twist", "wood chop", "cable chop", "rotation", "rotational", "medicine ball throw"]) {
            patterns.insert(.rotation)
        }
        if containsAny(name, ["crunch", "sit-up", "sit up", "leg raise", "knee raise", "v-up", "v up"]) {
            patterns.insert(.spinalFlexion)
        }
        if containsAny(name, ["calf raise", "calf press", "donkey calf"]) { patterns.insert(.calfRaise) }
        if containsAny(name, ["curl", "chin-up", "chin up"]) { patterns.insert(.elbowFlexion) }
        if containsAny(name, ["triceps", "pushdown", "push-down", "skull crusher", "extension"]) { patterns.insert(.elbowExtension) }
        if containsAny(name, ["lateral raise", "side raise", "front raise"]) { patterns.insert(.shoulderAbduction) }
        if containsAny(name, ["rear delt", "reverse fly", "reverse pec", "face pull"]) { patterns.insert(.shoulderHorizontalAbduction) }
        if containsAny(name, ["shrug"]) { patterns.insert(.scapularElevation) }
        if containsAny(name, ["clean", "snatch", "jerk", "high pull", "thruster"]) { patterns.insert(.powerOlympic) }
        if containsAny(name, ["jump", "bound", "box jump", "plyo", "depth jump", "throw"]) { patterns.insert(.plyometric) }
        if containsAny(name, ["run", "jog", "bike", "cycling", "elliptical", "stair", "rower", "sled", "sprint"]) {
            patterns.insert(.conditioning)
        }
        if containsAny(name, ["stretch", "mobility", "foam roll", "foam roller"]) { patterns.insert(.mobilityRecovery) }

        // Muscle evidence supplies a fallback when naming is sparse or inconsistent.
        if patterns.isEmpty {
            switch exercise.primaryMuscle {
            case .chest: patterns.insert(.horizontalPush)
            case .back, .traps: patterns.insert(.horizontalPull)
            case .biceps, .forearms: patterns.insert(.elbowFlexion)
            case .triceps: patterns.insert(.elbowExtension)
            case .quads: patterns.insert(.kneeDominant)
            case .hamstrings, .glutes, .lowerBack: patterns.insert(.hipHinge)
            case .calves: patterns.insert(.calfRaise)
            case .abs: patterns.insert(.antiExtension)
            case .shoulders: patterns.insert(exercise.force == .pull ? .horizontalPull : .verticalPush)
            }
        }

        var focuses = Set<WorkoutFocusID>()
        let muscles = Set([exercise.primaryMuscle]).union(exercise.secondaryMuscles)
        for focus in [WorkoutFocusID.push, .pull, .legs, .lower, .upper, .fullBody,
                      .chestBack, .shouldersArms, .arms, .posteriorChain, .quadGlute,
                      .hamstringGlute, .core] {
            let expected = WorkoutFocus.definition(for: focus).muscles
            if !muscles.intersection(expected).isEmpty { focuses.insert(focus) }
        }
        let role: ExerciseRole = patterns.contains(.conditioning) ? .conditioning
            : patterns.contains(.mobilityRecovery) ? .mobility
            : exercise.mechanic == .compound ? .primary
            : exercise.mechanic == .isolation ? .accessory : .unknown
        let confidence = patterns.isEmpty ? 0.35 : (exercise.force == nil ? 0.75 : 0.9)
        return ExerciseTags(movementPatterns: patterns, focusIDs: focuses, role: role,
                            confidence: confidence)
    }

    public static func compatibilityScore(_ exercise: Exercise,
                                          session: SessionDefinition,
                                          requiredPatterns: Set<MovementPattern> = [],
                                          preferredRole: ExerciseRole? = nil) -> Double {
        let tags = tags(for: exercise)
        let focusHit = session.muscles.isEmpty
            ? (session.movementPatterns.intersection(tags.movementPatterns).isEmpty ? 0.0 : 1.0)
            : (session.muscles.contains(exercise.primaryMuscle) ? 1.0
               : exercise.secondaryMuscles.contains(where: session.muscles.contains) ? 0.55 : 0.0)
        guard focusHit > 0 else { return 0 }
        let patterns = requiredPatterns.isEmpty ? session.movementPatterns : requiredPatterns
        let patternHit = patterns.isEmpty ? 0.5
            : Double(patterns.intersection(tags.movementPatterns).count) / Double(patterns.count)
        let roleHit = preferredRole.map { $0 == tags.role ? 1.0 : 0.0 } ?? 0.5
        return 0.45 * focusHit + 0.4 * patternHit + 0.1 * roleHit + 0.05 * tags.confidence
    }

    private static func containsAny(_ value: String, _ tokens: [String]) -> Bool {
        tokens.contains { value.contains($0) }
    }
}

public extension CatalogStore {
    /// Returns ranked, focus-safe candidates for a day-scoped replacement.
    func compatibleExercises(for session: SessionDefinition,
                             excluding excludedIDs: Set<String> = [],
                             requiredPatterns: Set<MovementPattern> = [],
                             preferredRole: ExerciseRole? = nil) -> [Exercise] {
        all.filter { !excludedIDs.contains($0.id) }
            .map { ($0, ExerciseTaxonomy.compatibilityScore($0, session: session,
                                                            requiredPatterns: requiredPatterns,
                                                            preferredRole: preferredRole)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return (lhs.0.name, lhs.0.id) < (rhs.0.name, rhs.0.id)
            }
            .map { $0.0 }
    }
}
