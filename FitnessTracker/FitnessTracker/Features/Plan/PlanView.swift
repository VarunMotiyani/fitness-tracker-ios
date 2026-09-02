import SwiftUI
import FitnessDomain
import ExerciseCatalog

struct PlanView: View {
    let plan: WeeklyPlan
    let catalog: CatalogStore
    var onStartSession: (PlannedSession) -> Void

    private let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Plan")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(GymTheme.label)
                    Text("Your weekly routine")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(GymTheme.label2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // 1. Week Schedule Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("WEEK SCHEDULE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GymTheme.label3)
                        .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { idx in
                            let dayName = dayNames[idx]
                            let sessionForDay = plan.sessions.first { $0.order == idx }

                            HStack {
                                Text(dayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(GymTheme.label)
                                Spacer()
                                if let session = sessionForDay {
                                    Button {
                                        onStartSession(session)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Circle().fill(GymTheme.green).frame(width: 6, height: 6)
                                            Text("Session \(session.order + 1)")
                                                .font(.system(size: 12, weight: .bold))
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        .foregroundStyle(GymTheme.green)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(GymTheme.green.opacity(0.16), in: Capsule())
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Text("Rest")
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundStyle(GymTheme.label3)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(GymTheme.label4)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            if idx < 6 {
                                Divider()
                                    .background(Color.white.opacity(0.06))
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                }

                // 2. Split Routines Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ROUTINES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(GymTheme.label3)
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 8) {
                        ForEach(plan.sessions.sorted { $0.order < $1.order }) { session in
                            Button {
                                onStartSession(session)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(GymTheme.surface2)
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "dumbbell.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(GymTheme.green)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Session \(session.order + 1) · \(focusText(session))")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(GymTheme.label)
                                        Text("\(session.items.count) exercises")
                                            .font(.system(size: 12))
                                            .foregroundStyle(GymTheme.label2)
                                    }

                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(GymTheme.label3)
                                }
                                .padding(12)
                                .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // 3. Weekly Volume Targets
                VStack(alignment: .leading, spacing: 8) {
                    Text("WEEKLY VOLUME TARGETS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GymTheme.label3)
                        .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        ForEach(Array(plan.weeklyVolumeTargets.enumerated()), id: \.element.muscle) { idx, target in
                            HStack {
                                Text(target.muscle.label)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(GymTheme.label)
                                Spacer()
                                Text("\(target.targetSets) sets / wk")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(GymTheme.label2)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            if idx < plan.weeklyVolumeTargets.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.06))
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 80)
        }
        .background(GymTheme.bg.ignoresSafeArea())
    }

    private func focusText(_ session: PlannedSession) -> String {
        session.focusMuscles.map(\.label).joined(separator: ", ")
    }
}
