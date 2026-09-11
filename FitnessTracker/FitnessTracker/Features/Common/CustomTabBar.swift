import SwiftUI

public enum AppTab: Int, CaseIterable {
    case home = 0
    case plan = 1
    case start = 2
    case stats = 3
    case exercises = 4
    case coach = 5
}

enum TabBarMetrics {
    static let capsuleHeight: CGFloat = 58
    static let iconFontSize: CGFloat = 19
    static let pillHeight: CGFloat = 40
    static let startDiameter: CGFloat = 50       // sits inside the capsule, vertically centred
    static let sideInset: CGFloat = 20           // capsule → screen edge
}

/// Floating Liquid Glass bottom bar: a translucent capsule of tab items with the
/// Start action raised on its own disc in the exact centre.
struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    let isWorkoutActive: Bool
    let onStartPressed: () -> Void

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var pillNamespace
    @State private var resumePulse = false

    private let tabs: [(tab: AppTab, icon: String, label: String)] = [
        (.home, "house.fill", "Home"),
        (.plan, "calendar", "Plan"),
        (.stats, "chart.bar.xaxis", "Stats"),
        (.exercises, "dumbbell.fill", "Exercises"),
    ]

    var body: some View {
        ZStack {
            // 1 — the glass capsule with the four tab items
            HStack(spacing: 0) {
                tabItem(tabs[0])
                tabItem(tabs[1])
                Color.clear.frame(width: TabBarMetrics.startDiameter + 20)
                tabItem(tabs[2])
                tabItem(tabs[3])
            }
            .padding(.horizontal, 8)
            .frame(height: TabBarMetrics.capsuleHeight)
            .glassEffect(.regular, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
            // Liquid Glass carries its own contact shadow — no manual .shadow()
            // here, which was stacking a second one under the capsule.

            // 2 — Start disc: dead-centre of the ZStack (= centre of the capsule),
            // drawn last so it sits on top of the glass.
            startDisc
        }
        .padding(.horizontal, TabBarMetrics.sideInset)
        .onAppear { resumePulse = isWorkoutActive }
        .onChange(of: isWorkoutActive) { _, active in resumePulse = active }
    }

    @ViewBuilder
    private func tabItem(_ item: (tab: AppTab, icon: String, label: String)) -> some View {
        let isSelected = selectedTab == item.tab
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(.snappy(duration: 0.25)) { selectedTab = item.tab }
        } label: {
            Image(systemName: item.icon)
                .font(.system(size: TabBarMetrics.iconFontSize, weight: .semibold))
                .foregroundStyle(isSelected ? activeAccent : GymTheme.label3)
                .frame(maxWidth: .infinity)
                // Full capsule height is the hit area (≥44 pt); the visual pill
                // stays pillHeight tall, centred inside it.
                .frame(height: TabBarMetrics.capsuleHeight)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(activeAccent.opacity(0.16))
                            .overlay(Capsule().strokeBorder(activeAccent.opacity(0.28), lineWidth: 0.75))
                            .matchedGeometryEffect(id: "pill", in: pillNamespace)
                            .padding(.vertical, (TabBarMetrics.capsuleHeight - TabBarMetrics.pillHeight) / 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var startDisc: some View {
        let tint = isWorkoutActive ? GymTheme.orange : activeAccent
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onStartPressed()
        } label: {
            ZStack {
                if isWorkoutActive {
                    // Reduce Motion: static ring instead of the repeating
                    // expansion pulse (which also kept the GPU waking forever).
                    Circle()
                        .stroke(GymTheme.orange, lineWidth: 2)
                        .frame(width: TabBarMetrics.startDiameter, height: TabBarMetrics.startDiameter)
                        .scaleEffect(reduceMotion ? 1.0 : (resumePulse ? 1.5 : 1.0))
                        .opacity(reduceMotion ? 0.7 : (resumePulse ? 0 : 0.7))
                        .animation(reduceMotion ? nil : .easeOut(duration: 1.9).repeatForever(autoreverses: false), value: resumePulse)
                }
                Circle()
                    .fill(tint.gradient)
                    .frame(width: TabBarMetrics.startDiameter, height: TabBarMetrics.startDiameter)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: tint.opacity(0.45), radius: 8, y: 3)
                Image(systemName: isWorkoutActive ? "timer" : "play.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.black)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isWorkoutActive ? "Resume workout" : "Start workout")
    }
}
