import FitnessDomain

public struct SplitTemplate: Sendable, Equatable {
    public let name: String
    public let sessionFocuses: [[MuscleGroup]]
    public var sessionCount: Int { sessionFocuses.count }
    public init(name: String, sessionFocuses: [[MuscleGroup]]) {
        self.name = name
        self.sessionFocuses = sessionFocuses
    }
}

public enum SplitTemplateLibrary {

    public static let fullBody3 = SplitTemplate(
        name: "3-day full body",
        sessionFocuses: Array(repeating: fullBodyFocus, count: 3)
    )

    public static let upperLower4 = SplitTemplate(
        name: "4-day upper / lower",
        sessionFocuses: [upperFocus, lowerFocus, upperFocus, lowerFocus]
    )

    public static let pushPullLegs6 = SplitTemplate(
        name: "6-day push / pull / legs",
        sessionFocuses: [pushFocus, pullFocus, legsFocus, pushFocus, pullFocus, legsFocus]
    )

    public static let all: [SplitTemplate] = [fullBody3, upperLower4, pushPullLegs6]

    private static let fullBodyFocus: [MuscleGroup] =
        [.quads, .hamstrings, .glutes, .chest, .back, .shoulders, .biceps, .triceps, .abs]
    private static let upperFocus: [MuscleGroup] =
        [.chest, .back, .shoulders, .biceps, .triceps]
    private static let lowerFocus: [MuscleGroup] =
        [.quads, .hamstrings, .glutes, .calves, .abs]
    private static let pushFocus: [MuscleGroup] = [.chest, .shoulders, .triceps]
    private static let pullFocus: [MuscleGroup] = [.back, .biceps, .traps]
    private static let legsFocus: [MuscleGroup] = [.quads, .hamstrings, .glutes, .calves]
}
