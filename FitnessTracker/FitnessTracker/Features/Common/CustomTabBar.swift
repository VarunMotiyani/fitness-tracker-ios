import SwiftUI

public enum AppTab: Int, CaseIterable {
    case home = 0
    case plan = 1
    case start = 2
    case stats = 3
    case exercises = 4
    case coach = 5
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
        HStack(spacing: 0) {
            // 1. Home
            tabButton(tab: .home, title: "Home", icon: "house.fill")

            // 2. Plan
            tabButton(tab: .plan, title: "Plan", icon: "calendar")

            // 3. Center FAB (Start / Resume)
            centerStartButton

            // 4. Stats
            tabButton(tab: .stats, title: "Stats", icon: "chart.bar.xaxis")

            // 5. Exercises
            tabButton(tab: .exercises, title: "Exercises", icon: "dumbbell.fill")

            // 6. Coach
            tabButton(tab: .coach, title: "Coach", icon: "bubble.left.and.bubble.right.fill")
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
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(selectedTab == tab ? activeAccent : GymTheme.label3)
                Text(title)
                    .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
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
                    .font(.system(size: 10, weight: .bold))
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
