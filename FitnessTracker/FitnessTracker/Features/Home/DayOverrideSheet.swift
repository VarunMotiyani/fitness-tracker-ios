import SwiftUI
import SwiftData
import FitnessDomain
import Metrics
import RuleEngine

enum WorkoutDayPresentation {
    static func title(for session: PlannedSession) -> String {
        switch session.order {
        case 0: "Push Day"
        case 1: "Pull Day"
        case 2: "Legs Day"
        default: session.focusMuscles.map(\.label).joined(separator: ", ")
        }
    }

    static func planLabel(for session: PlannedSession) -> String {
        "Planned workout"
    }
}

struct DayOverrideSheet: View {
    let date: Date
    let plan: WeeklyPlan
    var onSelectSession: (PlannedSession?) -> Void
    var onSaveOverride: ((String?) -> Void)?
    var onSavedCheckin: ((DailyCheckinModel) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DailyCheckinModel.date, order: .reverse)
    private var dailyCheckins: [DailyCheckinModel]

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var showCheckinSheet = false
    @State private var showChangeOptions = false
    @State private var sheetDetent: PresentationDetent = .height(500)

    init(
        date: Date,
        plan: WeeklyPlan,
        onSavedCheckin: ((DailyCheckinModel) -> Void)? = nil,
        onSaveOverride: ((String?) -> Void)? = nil,
        onSelectSession: @escaping (PlannedSession?) -> Void
    ) {
        self.date = date
        self.plan = plan
        self.onSavedCheckin = onSavedCheckin
        self.onSaveOverride = onSaveOverride
        self.onSelectSession = onSelectSession
    }

    private var plannedSession: PlannedSession? {
        WorkoutScheduleStore.plannedSession(for: date, in: plan)
    }

    private var hasDayOverride: Bool {
        WorkoutScheduleStore.dayPlan[Scheduling.isoDateKey(date, calendar: .appWeek)] != nil
    }

    private var isToday: Bool {
        Calendar.appWeek.isDate(date, inSameDayAs: .now)
    }

    private var isPast: Bool {
        let cal = Calendar.appWeek
        let startOfDate = cal.startOfDay(for: date)
        let startOfToday = cal.startOfDay(for: .now)
        return startOfDate < startOfToday
    }

    private var dayCheckin: DailyCheckinModel? {
        dailyCheckins.first { Calendar.appWeek.isDate($0.date, inSameDayAs: date) }
    }

    private var checkinSummaryText: String {
        guard let checkin = dayCheckin else {
            return "Share sleep and soreness so your coach can adapt."
        }
        var parts: [String] = []
        if let sleep = checkin.sleepQuality {
            parts.append("Sleep: \(sleep)/10")
        }
        if let sore = checkin.soreness {
            parts.append("Soreness: \(sore)/10")
        }
        if let note = checkin.note, !note.isEmpty {
            parts.append(note)
        }
        return parts.isEmpty ? "Sleep and soreness saved" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var checkinSection: some View {
        if isToday {
            Button {
                showCheckinSheet = true
            } label: {
                checkinCardContent(isEditable: true)
            }
            .buttonStyle(.plain)
        } else if isPast, dayCheckin != nil {
            checkinCardContent(isEditable: false)
        }
    }

    @ViewBuilder
    private func checkinCardContent(isEditable: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: dayCheckin == nil ? "heart.text.square.fill" : "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(dayCheckin == nil ? GymTheme.violet : activeAccent)
                .frame(width: 40, height: 40)
                .background((dayCheckin == nil ? GymTheme.violet : activeAccent).opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(dayCheckin == nil ? "How are you feeling?" : (isToday ? "Today’s check-in" : "Daily check-in"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GymTheme.label)

                Text(checkinSummaryText)
                    .font(.system(size: 13))
                    .foregroundStyle(GymTheme.label2)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isEditable {
                Text(dayCheckin == nil ? "Check in" : "Update")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(activeAccent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var plannedWorkoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR PLAN")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(GymTheme.label3)

            if let session = plannedSession {
                HStack(spacing: 14) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(activeAccent, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(WorkoutDayPresentation.planLabel(for: session).uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(activeAccent)
                        Text(WorkoutDayPresentation.title(for: session))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(GymTheme.label)
                        Text("\(session.items.count) exercises")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(GymTheme.label2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 16))
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GymTheme.label2)
                        .frame(width: 48, height: 48)
                        .background(GymTheme.surface3, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("PLANNED DAY")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(GymTheme.label3)
                        Text("Rest day")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(GymTheme.label)
                        Text("Recovery is part of the plan")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(GymTheme.label2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 16))
            }

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showChangeOptions.toggle()
                    sheetDetent = showChangeOptions ? .large : .height(500)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(showChangeOptions ? "Hide workout choices" : (plannedSession == nil ? "Add a workout" : "Change workout"))
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Image(systemName: showChangeOptions ? "chevron.up" : "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(activeAccent)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(activeAccent.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(plannedSession == nil ? "Add a workout" : "Change workout")
            .accessibilityValue(showChangeOptions ? "Workout choices shown" : "Workout choices hidden")

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                onSaveOverride?("rest")
                onSelectSession(nil)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Rest today")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Text("Skip this day")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GymTheme.label3)
                }
                .foregroundStyle(GymTheme.label2)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rest today, skip this day")
        }
    }

    @ViewBuilder
    private var changeWorkoutSection: some View {
        if showChangeOptions {
            VStack(alignment: .leading, spacing: 10) {
                Text("CHOOSE A DIFFERENT WORKOUT")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(GymTheme.label3)

                Text("This replaces the plan for \(date.formatted(.dateTime.weekday(.wide))).")
                    .font(.system(size: 13.5))
                    .foregroundStyle(GymTheme.label2)

                ForEach(plan.sessions.sorted { $0.order < $1.order }) { session in
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        onSaveOverride?(WorkoutScheduleStore.routineID(for: session, in: plan))
                        onSelectSession(session)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: 40, height: 40)
                                .background(activeAccent, in: RoundedRectangle(cornerRadius: 11))
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(WorkoutDayPresentation.title(for: session))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(GymTheme.label)
                                Text("\(session.items.count) exercises")
                                    .font(.system(size: 13))
                                    .foregroundStyle(GymTheme.label2)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(GymTheme.label3)
                                .accessibilityHidden(true)
                        }
                        .padding(12)
                        .frame(minHeight: 64)
                        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(WorkoutDayPresentation.title(for: session))")
                }

                if hasDayOverride {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        onSaveOverride?(nil)
                        onSelectSession(nil)
                        dismiss()
                    } label: {
                        Label("Use weekly plan again", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(GymTheme.label2)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header with generous top padding below drag indicator
                VStack(alignment: .leading, spacing: 4) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(GymTheme.label)

                    Text(isToday ? "Today’s schedule" : "Your plan for this day")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.60))
                }
                .padding(.top, 28)

                plannedWorkoutSection

                checkinSection

                changeWorkoutSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(GymTheme.bgElevated.ignoresSafeArea())
        .presentationDetents([.height(500), .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCheckinSheet) {
            CheckinEntryView { checkin in
                onSavedCheckin?(checkin)
            }
        }
    }
}
