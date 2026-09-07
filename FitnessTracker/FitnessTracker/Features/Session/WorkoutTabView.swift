import SwiftUI
import FitnessDomain
import ExerciseCatalog

struct WorkoutTabView: View {
    let plan: WeeklyPlan
    let catalog: CatalogStore
    var onStartSession: (PlannedSession) -> Void

    init(plan: WeeklyPlan, catalog: CatalogStore, onStartSession: @escaping (PlannedSession) -> Void) {
        self.plan = plan
        self.catalog = catalog
        self.onStartSession = onStartSession
    }

    private var todaySession: PlannedSession? {
        plan.sessions.sorted { $0.order < $1.order }.first
    }

    private var otherSessions: [PlannedSession] {
        let sorted = plan.sessions.sorted { $0.order < $1.order }
        return sorted.count > 1 ? Array(sorted.dropFirst()) : []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start Workout")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(todaySession != nil ? "Today's prescribed routine is ready" : "Rest day, but you can start any routine")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.75))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Today's Routine Card
                if let today = todaySession {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("TODAY'S PLAN")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color(red: 0.19, green: 0.82, blue: 0.35))
                                Text("Session \(today.order + 1) · \(focusText(today))")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color(red: 0.19, green: 0.82, blue: 0.35))
                                .padding(10)
                                .background(Color(red: 0.17, green: 0.17, blue: 0.18), in: RoundedRectangle(cornerRadius: 10))
                        }

                        // Exercise list
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(today.items.enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Text(catalog.exercise(id: item.exerciseID)?.name ?? item.exerciseID)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color(white: 0.90))
                                    Spacer()
                                    Text("\(item.targetSets) × \(item.targetReps.min)–\(item.targetReps.max)")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color(white: 0.60))
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        Button {
                            onStartSession(today)
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start Workout")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .background(Color(red: 0.19, green: 0.82, blue: 0.35), in: RoundedRectangle(cornerRadius: 12))
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(Color(red: 0.11, green: 0.11, blue: 0.12), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(red: 0.19, green: 0.82, blue: 0.35).opacity(0.4), lineWidth: 1.5)
                    )
                    .padding(.horizontal, 16)
                }

                // Other Routines Section
                if !otherSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Other Routines")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)

                        ForEach(otherSessions) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Session \(session.order + 1) · \(focusText(session))")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text("\(session.items.count) exercises")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundStyle(Color(white: 0.70))
                                }
                                Spacer()
                                Button {
                                    onStartSession(session)
                                } label: {
                                    Text("Start")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(Color(red: 0.19, green: 0.82, blue: 0.35), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .background(Color(red: 0.11, green: 0.11, blue: 0.12), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func focusText(_ session: PlannedSession) -> String {
        session.focusMuscles.map(\.label).joined(separator: ", ")
    }
}
