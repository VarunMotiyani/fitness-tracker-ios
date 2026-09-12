import Foundation

/// The movement families used by split definitions and the day-scoped exercise picker.
/// These are deliberately orthogonal to `MuscleGroup`: a session can be both `upper` and
/// `push`, while an exercise can be both `compound` and `horizontalPush`.
public enum MovementPattern: String, Codable, CaseIterable, Hashable, Sendable {
    case kneeDominant, hipHinge, singleLeg
    case horizontalPush, verticalPush, horizontalPull, verticalPull
    case carry, antiExtension, antiRotation, antiLateralFlexion, rotation, spinalFlexion
    case calfRaise, elbowFlexion, elbowExtension, shoulderAbduction
    case shoulderHorizontalAbduction, scapularElevation
    case powerOlympic, plyometric, conditioning, mobilityRecovery
}

public enum WorkoutFocusID: String, Codable, CaseIterable, Hashable, Sendable {
    case push, pull, legs, lower, upper, fullBody
    case chestBack, shouldersArms, arms
    case posteriorChain, quadGlute, hamstringGlute, core
    case conditioning, power, mobilityRecovery, custom
}

public enum SplitID: String, Codable, CaseIterable, Hashable, Sendable {
    case fullBody2, fullBody3, fullBodyDUP3
    case ppl3, ppl6, upperLower2, upperLower4, upperLower6
    case phul4, phat5, pplul5, bro5, arnold6
    case torsoLimbs4, torsoLimbs6, upperLowerArms4
    case powerbuilding4, conjugate4, custom
}

public struct SessionDefinition: Codable, Equatable, Hashable, Sendable {
    public let focus: WorkoutFocusID
    public let muscles: Set<MuscleGroup>
    public let movementPatterns: Set<MovementPattern>

    public init(focus: WorkoutFocusID,
                muscles: Set<MuscleGroup>,
                movementPatterns: Set<MovementPattern> = []) {
        self.focus = focus
        self.muscles = muscles
        self.movementPatterns = movementPatterns
    }
}

public struct SplitDefinition: Codable, Equatable, Hashable, Sendable {
    public let id: SplitID
    public let displayName: String
    public let aliases: [String]
    public let sessions: [SessionDefinition]

    public init(id: SplitID, displayName: String, aliases: [String] = [], sessions: [SessionDefinition]) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.sessions = sessions
    }
}

public enum WorkoutFocus {
    public static let pushMuscles: Set<MuscleGroup> = [.chest, .shoulders, .triceps]
    public static let pullMuscles: Set<MuscleGroup> = [.back, .traps, .biceps, .forearms]
    public static let lowerMuscles: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves, .abs]
    public static let upperMuscles: Set<MuscleGroup> = pushMuscles.union(pullMuscles)
    public static let legsMuscles: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves]

    public static func definition(for focus: WorkoutFocusID) -> SessionDefinition {
        switch focus {
        case .push:
            return SessionDefinition(focus: focus, muscles: pushMuscles,
                                     movementPatterns: [.horizontalPush, .verticalPush, .elbowExtension])
        case .pull:
            return SessionDefinition(focus: focus, muscles: pullMuscles,
                                     movementPatterns: [.horizontalPull, .verticalPull, .elbowFlexion])
        case .legs:
            return SessionDefinition(focus: focus, muscles: legsMuscles,
                                     movementPatterns: [.kneeDominant, .hipHinge, .singleLeg, .calfRaise])
        case .lower:
            return SessionDefinition(focus: focus, muscles: lowerMuscles,
                                     movementPatterns: [.kneeDominant, .hipHinge, .singleLeg, .calfRaise])
        case .upper:
            return SessionDefinition(focus: focus, muscles: upperMuscles,
                                     movementPatterns: [.horizontalPush, .verticalPush, .horizontalPull, .verticalPull])
        case .fullBody:
            return SessionDefinition(focus: focus, muscles: MuscleGroup.allCases.reduce(into: Set<MuscleGroup>()) { $0.insert($1) },
                                     movementPatterns: [.kneeDominant, .hipHinge, .horizontalPush, .verticalPush, .horizontalPull, .verticalPull])
        case .chestBack:
            return SessionDefinition(focus: focus, muscles: [.chest, .back, .traps, .lowerBack],
                                     movementPatterns: [.horizontalPush, .horizontalPull, .verticalPull])
        case .shouldersArms:
            return SessionDefinition(focus: focus, muscles: [.shoulders, .biceps, .triceps, .forearms],
                                     movementPatterns: [.verticalPush, .shoulderAbduction, .elbowFlexion, .elbowExtension])
        case .arms:
            return SessionDefinition(focus: focus, muscles: [.biceps, .triceps, .forearms],
                                     movementPatterns: [.elbowFlexion, .elbowExtension])
        case .posteriorChain:
            return SessionDefinition(focus: focus, muscles: [.hamstrings, .glutes, .lowerBack, .back, .traps],
                                     movementPatterns: [.hipHinge, .horizontalPull, .verticalPull, .carry])
        case .quadGlute:
            return SessionDefinition(focus: focus, muscles: [.quads, .glutes, .calves],
                                     movementPatterns: [.kneeDominant, .singleLeg])
        case .hamstringGlute:
            return SessionDefinition(focus: focus, muscles: [.hamstrings, .glutes, .lowerBack, .calves],
                                     movementPatterns: [.hipHinge, .singleLeg])
        case .core:
            return SessionDefinition(focus: focus, muscles: [.abs, .lowerBack],
                                     movementPatterns: [.antiExtension, .antiRotation, .antiLateralFlexion, .rotation, .spinalFlexion])
        case .conditioning:
            return SessionDefinition(focus: focus, muscles: [], movementPatterns: [.conditioning])
        case .power:
            return SessionDefinition(focus: focus, muscles: MuscleGroup.allCases.reduce(into: Set<MuscleGroup>()) { $0.insert($1) },
                                     movementPatterns: [.powerOlympic, .plyometric])
        case .mobilityRecovery:
            return SessionDefinition(focus: focus, muscles: MuscleGroup.allCases.reduce(into: Set<MuscleGroup>()) { $0.insert($1) },
                                     movementPatterns: [.mobilityRecovery])
        case .custom:
            return SessionDefinition(focus: focus, muscles: [], movementPatterns: [])
        }
    }

    /// Best-fit focus for a generated session. This is intentionally tolerant of accessory
    /// muscles (for example abs on a push day) and avoids relying on session order.
    public static func classify(muscles: Set<MuscleGroup>) -> WorkoutFocusID {
        guard !muscles.isEmpty else { return .custom }
        let candidates: [WorkoutFocusID] = [.push, .pull, .legs, .lower, .upper, .fullBody,
                                             .chestBack, .shouldersArms, .arms, .posteriorChain,
                                             .quadGlute, .hamstringGlute, .core]
        let ranked = candidates.map { focus -> (WorkoutFocusID, Double) in
            let expected = definition(for: focus).muscles
            let intersection = Double(muscles.intersection(expected).count)
            let union = Double(muscles.union(expected).count)
            return (focus, union == 0 ? 0 : intersection / union)
        }.sorted { $0.1 > $1.1 }
        guard let first = ranked.first, first.1 >= 0.55 else { return .custom }
        return first.0
    }
}
