import SwiftUI
import FitnessDomain
import Metrics

struct DayOverrideSheet: View {
    let date: Date
    let plan: WeeklyPlan
    var onSelectSession: (PlannedSession?) -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var selectedSessionID: UUID?

    init(date: Date, plan: WeeklyPlan, currentSession: PlannedSession? = nil, onSelectSession: @escaping (PlannedSession?) -> Void) {
        self.date = date
        self.plan = plan
        self.onSelectSession = onSelectSession
        _selectedSessionID = State(initialValue: currentSession?.id)
    }

    private var weeklyPlanName: String {
        let cal = Calendar.isoUTC
        let weekday = cal.component(.weekday, from: date)
        // Monday = 2 in Gregorian, 1 in ISO
        let dayIdx = (weekday + 5) % 7
        let orderedSessions = plan.sessions.sorted { $0.order < $1.order }
        if dayIdx < orderedSessions.count {
            let s = orderedSessions[dayIdx]
            if s.order == 0 { return "Push Day" }
            if s.order == 1 { return "Pull Day" }
            if s.order == 2 { return "Legs Day" }
            return s.focusMuscles.map(\.label).joined(separator: ", ")
        }
        return "Rest"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header with generous top padding below drag indicator
                VStack(alignment: .leading, spacing: 4) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(GymTheme.label)

                    Text("Weekly plan: \(weeklyPlanName)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.60))
                }
                .padding(.top, 28)

                Text("Sick, missed a day or want a different session? Pick what to train instead.")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(Color(white: 0.55))
                    .lineSpacing(2)
                    .padding(.bottom, 4)

                // Split Routine Options
                VStack(spacing: 8) {
                    ForEach(plan.sessions.sorted { $0.order < $1.order }) { session in
                        let sessionName: String = {
                            if session.order == 0 { return "Session 1 · Push Day" }
                            if session.order == 1 { return "Session 2 · Pull Day" }
                            if session.order == 2 { return "Session 3 · Legs Day" }
                            return "Session \(session.order + 1) · \(session.focusMuscles.map(\.label).joined(separator: ", "))"
                        }()

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
                                        .fill(activeAccent)
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "dumbbell.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.black)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sessionName)
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
                                        .foregroundStyle(activeAccent)
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
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(GymTheme.bgElevated.ignoresSafeArea())
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
    }
}
