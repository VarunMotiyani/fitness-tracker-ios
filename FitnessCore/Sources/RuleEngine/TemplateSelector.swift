import FitnessDomain

public enum TemplateSelector {

    public static func select(sessionsPerWeek: Int,
                              experience: ExperienceLevel) -> SplitTemplate {
        switch experience {
        case .beginner:
            return sessionsPerWeek <= 3
                ? SplitTemplateLibrary.fullBody3
                : SplitTemplateLibrary.upperLower4
        case .intermediate, .advanced:
            if sessionsPerWeek <= 3 { return SplitTemplateLibrary.fullBody3 }
            if sessionsPerWeek == 4 { return SplitTemplateLibrary.upperLower4 }
            return SplitTemplateLibrary.pushPullLegs6
        }
    }
}
