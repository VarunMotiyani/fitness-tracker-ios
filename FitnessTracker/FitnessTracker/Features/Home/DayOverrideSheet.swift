import SwiftUI
import FitnessDomain

struct DayOverrideSheet: View {
    let date: Date
    let plan: WeeklyPlan
    var onSelectSession: (PlannedSession?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSessionID: UUID?

    init(date: Date, plan: WeeklyPlan, currentSession: PlannedSession? = nil, onSelectSession: @escaping (PlannedSession?) -> Void) {
        self.date = date
        self.plan = plan
        self.onSelectSession = onSelectSession
        _selectedSessionID = State(initialValue: currentSession?.id)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(GymTheme.label)

                    Text("Weekly plan: Pull Day")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.60))
                }

                Text("Sick, missed a day or want a different session? Pick what to train instead.")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(Color(white: 0.60))
                    .lineSpacing(2)
                    .padding(.bottom, 4)

                // Split Routine Options
                VStack(spacing: 8) {
                    ForEach(plan.sessions.sorted { $0.order < $1.order }) { session in
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            selectedSessionID = session.id
                            onSelectSession(session)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(GymTheme.green)
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "dumbbell.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Session \(session.order + 1) · \(session.focusMuscles.map(\.label).joined(separator: ", "))")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(GymTheme.label)
                                    Text("\(session.items.count) exercises")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(white: 0.60))
                                }

                                Spacer()

                                if selectedSessionID == session.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(GymTheme.green)
                                }
                            }
                            .padding(12)
                            .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    // Rest / Skip Option
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        selectedSessionID = nil
                        onSelectSession(nil)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(white: 0.22))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "moon.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                            }

                            Text("Rest / skip this day")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(GymTheme.label)

                            Spacer()
                        }
                        .padding(12)
                        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    // Reset / Back to Weekly Plan Option
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        onSelectSession(nil)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(white: 0.22))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                            }

                            Text("Back to weekly plan")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(GymTheme.label)

                            Spacer()
                        }
                        .padding(12)
                        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .background(GymTheme.bgElevated.ignoresSafeArea())
        }
        .presentationDetents([.fraction(0.60), .medium])
        .presentationDragIndicator(.visible)
    }
}
