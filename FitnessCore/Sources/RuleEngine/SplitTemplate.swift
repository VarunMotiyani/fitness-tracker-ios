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

    public static let fullBody2 = SplitTemplate(
        name: "2-day full body",
        sessionFocuses: [fullBodyFocus, fullBodyFocus]
    )

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

    public static let pushPullLegs3 = SplitTemplate(
        name: "3-day push / pull / legs",
        sessionFocuses: [pushFocus, pullFocus, legsFocus]
    )

    public static let upperLower6 = SplitTemplate(
        name: "6-day upper / lower",
        sessionFocuses: [upperFocus, lowerFocus, upperFocus, lowerFocus, upperFocus, lowerFocus]
    )

    public static let upperLower2 = SplitTemplate(
        name: "2-day upper / lower",
        sessionFocuses: [upperFocus, lowerFocus]
    )

    public static let phul4 = SplitTemplate(
        name: "4-day PHUL (power / hypertrophy upper lower)",
        sessionFocuses: [upperFocus, lowerFocus, upperFocus, lowerFocus]
    )

    public static let pplul5 = SplitTemplate(
        name: "5-day PPLUL",
        sessionFocuses: [pushFocus, pullFocus, legsFocus, upperFocus, lowerFocus]
    )

    public static let bro5 = SplitTemplate(
        name: "5-day body-part split",
        sessionFocuses: [chestFocus, backFocus, shouldersFocus, legsFocus, armsFocus]
    )

    public static let arnold6 = SplitTemplate(
        name: "6-day Arnold split",
        sessionFocuses: [chestBackFocus, shouldersArmsFocus, legsFocus,
                         chestBackFocus, shouldersArmsFocus, legsFocus]
    )

    public static let torsoLimbs4 = SplitTemplate(
        name: "4-day torso / limbs",
        sessionFocuses: [chestBackFocus, limbsFocus, chestBackFocus, limbsFocus]
    )

    public static let torsoLimbs6 = SplitTemplate(
        name: "6-day torso / limbs",
        sessionFocuses: [chestBackFocus, limbsFocus, chestBackFocus, limbsFocus, chestBackFocus, limbsFocus]
    )

    public static let upperLowerArms4 = SplitTemplate(
        name: "4-day upper / lower + arms",
        sessionFocuses: [upperFocus, lowerFocus, shouldersArmsFocus, lowerCoreFocus]
    )

    public static let phat5 = SplitTemplate(
        name: "5-day PHAT",
        sessionFocuses: [upperFocus, lowerFocus, backShouldersFocus, lowerFocus, chestArmsFocus]
    )

    public static let powerbuilding4 = SplitTemplate(
        name: "4-day powerbuilding",
        sessionFocuses: [lowerFocus, pushFocus, posteriorFocus, upperFocus]
    )

    public static let fullBodyDUP3 = SplitTemplate(
        name: "3-day full body (undulating)",
        sessionFocuses: [fullBodyFocus, fullBodyFocus, fullBodyFocus]
    )

    /// All built-in styles exposed to plan creation. The original three remain in this list
    /// for backwards compatibility; new styles are aliases at the template level rather than
    /// separate exercise catalogs.
    public static let all: [SplitTemplate] = [
        fullBody2, fullBody3, fullBodyDUP3,
        pushPullLegs3, upperLower2, upperLower4, upperLower6,
        phul4, pplul5, bro5, arnold6,
        torsoLimbs4, torsoLimbs6, upperLowerArms4, phat5, powerbuilding4,
        pushPullLegs6
    ]

    private static let fullBodyFocus: [MuscleGroup] =
        [.quads, .hamstrings, .glutes, .chest, .back, .shoulders, .biceps, .triceps, .abs]
    private static let upperFocus: [MuscleGroup] =
        [.chest, .back, .traps, .shoulders, .biceps, .triceps, .forearms]
    private static let lowerFocus: [MuscleGroup] =
        [.quads, .hamstrings, .glutes, .calves, .abs]
    private static let pushFocus: [MuscleGroup] = [.chest, .shoulders, .triceps]
    private static let pullFocus: [MuscleGroup] = [.back, .biceps, .traps]
    private static let legsFocus: [MuscleGroup] = [.quads, .hamstrings, .glutes, .calves]

    private static let chestFocus: [MuscleGroup] = [.chest, .triceps]
    private static let backFocus: [MuscleGroup] = [.back, .traps, .biceps, .forearms, .lowerBack]
    private static let shouldersFocus: [MuscleGroup] = [.shoulders, .traps, .abs]
    private static let armsFocus: [MuscleGroup] = [.biceps, .triceps, .forearms]
    private static let chestBackFocus: [MuscleGroup] = [.chest, .back, .traps, .lowerBack]
    private static let shouldersArmsFocus: [MuscleGroup] = [.shoulders, .biceps, .triceps, .forearms]
    private static let limbsFocus: [MuscleGroup] = [.shoulders, .biceps, .triceps, .forearms, .quads, .hamstrings, .glutes, .calves]
    private static let lowerCoreFocus: [MuscleGroup] = [.quads, .hamstrings, .glutes, .calves, .abs]
    private static let backShouldersFocus: [MuscleGroup] = [.back, .traps, .shoulders]
    private static let chestArmsFocus: [MuscleGroup] = [.chest, .biceps, .triceps, .forearms]
    private static let posteriorFocus: [MuscleGroup] = [.hamstrings, .glutes, .lowerBack, .back, .traps]
}
