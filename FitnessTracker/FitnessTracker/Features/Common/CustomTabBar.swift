import SwiftUI

public enum AppTab: Int, CaseIterable {
    case home = 0
    case plan = 1
    case start = 2
    case stats = 3
    case exercises = 4
}

struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    let isWorkoutActive: Bool
    let onStartPressed: () -> Void

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
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(selectedTab == tab ? GymTheme.green : GymTheme.label3)
                Text(title)
                    .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? GymTheme.green : GymTheme.label3)
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
                    Circle()
                        .fill(isWorkoutActive ? GymTheme.orange : GymTheme.green)
                        .frame(width: 44, height: 44)
                        .shadow(color: (isWorkoutActive ? GymTheme.orange : GymTheme.green).opacity(0.35), radius: 8, y: 3)

                    Image(systemName: isWorkoutActive ? "timer" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black)
                }
                .offset(y: -8)

                Text(isWorkoutActive ? "Resume" : "Start")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isWorkoutActive ? GymTheme.orange : GymTheme.green)
                    .offset(y: -8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
