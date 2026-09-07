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
    static let iconFrame = CGSize(width: 28, height: 24)
    static let iconContentFrame = CGSize(width: 22, height: 22)
    static let iconFontSize: CGFloat = 20
    static let titleFontSize: CGFloat = 10
    static let itemSpacing: CGFloat = 3
    static let centerActionOverlayWidth: CGFloat = 80
    static let primaryTabCount = 5
}

struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    let isWorkoutActive: Bool
    let onStartPressed: () -> Void

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    /// Drives the "unfinished workout" ring around the FAB — see `centerStartButton`.
    @State private var resumePulse: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = proxy.size.width - 16

            HStack(spacing: 0) {
                // Five equal slots keep the primary navigation uniform. Coach
                // remains available from the Home toolbar instead of crowding
                // the persistent bottom bar.
                tabButton(tab: .home, title: "Home", icon: "house.fill")
                tabButton(tab: .plan, title: "Plan", icon: "calendar")

                Color.clear
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                tabButton(tab: .stats, title: "Stats", icon: "chart.bar.xaxis")
                tabButton(tab: .exercises, title: "Exercises", icon: "dumbbell.fill")
            }
            .frame(width: contentWidth)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .center) {
                centerStartButton
                    .frame(width: TabBarMetrics.centerActionOverlayWidth)
            }
        }
        .frame(height: 54)
        .padding(.horizontal, 8)
        .background(
            GymTheme.bgElevated
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private func tabButton(tab: AppTab, title: String, icon: String) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: TabBarMetrics.itemSpacing) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .font(.system(size: TabBarMetrics.iconFontSize, weight: .semibold))
                    .foregroundStyle(selectedTab == tab ? activeAccent : GymTheme.label3)
                    .frame(width: TabBarMetrics.iconContentFrame.width, height: TabBarMetrics.iconContentFrame.height)
                    .frame(width: TabBarMetrics.iconFrame.width, height: TabBarMetrics.iconFrame.height)
                Text(title)
                    .font(.system(size: TabBarMetrics.titleFontSize, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? activeAccent : GymTheme.label3)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var centerStartButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onStartPressed()
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    // Pulsing ring — draws the eye back to an unfinished workout, the way
                    // openGym's `@keyframes ping` does around its Resume button.
                    if isWorkoutActive {
                        Circle()
                            .stroke(GymTheme.orange, lineWidth: 2)
                            .frame(width: 44, height: 44)
                            .scaleEffect(resumePulse ? 1.45 : 1.0)
                            .opacity(resumePulse ? 0 : 0.7)
                            .animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false), value: resumePulse)
                    }

                    Circle()
                        .fill(isWorkoutActive ? GymTheme.orange : activeAccent)
                        .frame(width: 44, height: 44)
                        .shadow(color: (isWorkoutActive ? GymTheme.orange : activeAccent).opacity(0.35), radius: 8, y: 3)

                    Image(systemName: isWorkoutActive ? "timer" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black)
                }
                .offset(y: -8)

                Text(isWorkoutActive ? "Resume" : "Start")
                    .font(.system(size: TabBarMetrics.titleFontSize, weight: .bold))
                    .foregroundStyle(isWorkoutActive ? GymTheme.orange : activeAccent)
                    .offset(y: -8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onAppear {
            if isWorkoutActive { resumePulse = true }
        }
        .onChange(of: isWorkoutActive) { _, active in
            resumePulse = active
        }
    }
}
