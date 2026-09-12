import UIKit

/// Shared, pre-prepared feedback generators. Allocating a fresh
/// `UI*FeedbackGenerator` per tap (and never calling `prepare()`) adds a
/// visible hitch to the first tap on a physical device; reusing warm
/// instances removes it.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func impactLight() { light.impactOccurred(); light.prepare() }
    static func impactMedium() { medium.impactOccurred(); medium.prepare() }
    static func impactRigid() { rigid.impactOccurred(); rigid.prepare() }
    static func selectionChanged() { selection.selectionChanged(); selection.prepare() }
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
        notification.prepare()
    }
}
