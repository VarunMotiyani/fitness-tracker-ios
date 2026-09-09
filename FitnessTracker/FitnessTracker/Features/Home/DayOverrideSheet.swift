import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
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

    static func planLabel(for session: PlannedSession, isCustomized: Bool = false) -> String {
        planLabel(isCustomized: isCustomized)
    }

    static func planLabel(isCustomized: Bool) -> String {
        isCustomized ? "Custom for today" : "Planned workout"
    }
}

enum DayEditorAction: Equatable {
    case plannedWorkout, changeWorkout, changeChoices, resetWorkout, checkIn, restToday
}

enum DayEditorActionOrder {
    static func visibleActions(showChangeOptions: Bool) -> [DayEditorAction] {
        showChangeOptions
            ? [.plannedWorkout, .changeWorkout, .changeChoices, .resetWorkout, .checkIn, .restToday]
            : [.plannedWorkout, .changeWorkout, .checkIn, .restToday]
    }
}

struct DayOverrideSheet: View {
    let date: Date
    let plan: WeeklyPlan
    let catalog: CatalogStore?
    var onSelectSession: (PlannedSession?) -> Void
    var onSaveOverride: ((String?) -> Void)?
    var onSavedCheckin: ((DailyCheckinModel) -> Void)?
    var onEditExerciseList: (ExerciseLibraryIntent) -> Void
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DailyCheckinModel.date, order: .reverse)
    private var dailyCheckins: [DailyCheckinModel]

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var showCheckinSheet = false
    @State private var showChangeOptions = false
    @State private var showExerciseEditor = false
    @State private var showRestConfirmation = false
    @State private var selectedExerciseForDetail: Exercise?
    @State private var workoutOverrideRevision = 0
    @State private var sheetDetent: PresentationDetent = .height(560)

    init(
        date: Date,
        plan: WeeklyPlan,
        catalog: CatalogStore? = nil,
        onSavedCheckin: ((DailyCheckinModel) -> Void)? = nil,
        onSaveOverride: ((String?) -> Void)? = nil,
        onEditExerciseList: @escaping (ExerciseLibraryIntent) -> Void = { _ in },
        onSelectSession: @escaping (PlannedSession?) -> Void
    ) {
        self.date = date
        self.plan = plan
        self.catalog = catalog
        self.onSavedCheckin = onSavedCheckin
        self.onSaveOverride = onSaveOverride
        self.onEditExerciseList = onEditExerciseList
        self.onSelectSession = onSelectSession
    }

    private var plannedSession: PlannedSession? {
        _ = workoutOverrideRevision
        return WorkoutScheduleStore.effectiveSession(for: date, in: plan)
    }

    private var hasWorkoutOverride: Bool {
        _ = workoutOverrideRevision
        return WorkoutScheduleStore.dayWorkoutOverride(for: date, in: plan) != nil
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

    private func exerciseName(for item: PlannedItem) -> String {
        catalog?.exercise(id: item.exerciseID)?.name ?? item.exerciseID
    }

    private func isCompatibleAlternative(_ candidate: PlannedSession, with current: PlannedSession?) -> Bool {
        guard let current else { return true }
        return !Set(candidate.focusMuscles).isDisjoint(with: Set(current.focusMuscles))
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
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showExerciseEditor.toggle()
                            sheetDetent = showExerciseEditor ? .large : .height(560)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: 48, height: 48)
                                .background(activeAccent, in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(WorkoutDayPresentation.planLabel(for: session, isCustomized: hasWorkoutOverride).uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(0.6)
                                    .foregroundStyle(activeAccent)
                                Text(WorkoutDayPresentation.title(for: session))
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(GymTheme.label)
                                Text("\(session.items.count) exercises · Tap to \(showExerciseEditor ? "hide" : "view")")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(GymTheme.label2)
                            }

                            Spacer(minLength: 0)
                            Image(systemName: showExerciseEditor ? "chevron.up" : "chevron.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(GymTheme.label3)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if showExerciseEditor {
                        VStack(spacing: 8) {
                            ForEach(session.items, id: \.exerciseID) { item in
                                let exercise = catalog?.exercise(id: item.exerciseID)
                                Button {
                                    selectedExerciseForDetail = exercise
                                } label: {
                                    HStack(spacing: 12) {
                                        ExerciseThumbnailView(exercise: exercise, size: 42, cornerRadius: 10)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(exerciseName(for: item))
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(GymTheme.label)
                                                .multilineTextAlignment(.leading)
                                            Text("\(item.targetSets) sets · \(item.targetReps.min)–\(item.targetReps.max) reps")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(GymTheme.label2)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(GymTheme.label3)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(GymTheme.surface3, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .disabled(exercise == nil)
                            }

                            Button {
                                onEditExerciseList(ExerciseLibraryIntent(date: date, session: session, action: .add))
                                dismiss()
                            } label: {
                                Label("Add exercise", systemImage: "plus.circle.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(activeAccent)
                                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            if hasWorkoutOverride {
                                Button {
                                    WorkoutScheduleStore.removeDayWorkoutOverride(for: date)
                                    workoutOverrideRevision += 1
                                } label: {
                                    Label("Reset today’s workout", systemImage: "arrow.counterclockwise")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(GymTheme.label2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
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

            changeWorkoutSection
        }
    }

    @ViewBuilder
    private var changeWorkoutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showChangeOptions.toggle()
                    sheetDetent = showChangeOptions ? .large : .height(560)
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
            }
            .buttonStyle(.plain)

            if showChangeOptions {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CHOOSE A COMPATIBLE WORKOUT")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(GymTheme.label3)

                    Text("This changes only \(date.formatted(.dateTime.weekday(.wide))).")
                        .font(.system(size: 13.5))
                        .foregroundStyle(GymTheme.label2)

                    ForEach(plan.sessions.filter { isCompatibleAlternative($0, with: plannedSession) }.sorted { $0.order < $1.order }) { session in
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
                .padding(12)
                .background(GymTheme.surface3)
            }
        }
        .background(activeAccent.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
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

                Button("Need recovery? Rest today", role: .destructive) {
                    showRestConfirmation = true
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GymTheme.label3)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(GymTheme.bgElevated.ignoresSafeArea())
        .presentationDetents([.height(560), .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCheckinSheet) {
            CheckinEntryView { checkin in
                onSavedCheckin?(checkin)
            }
        }
        .sheet(item: $selectedExerciseForDetail) { exercise in
            ExerciseDetailSheet(
                exercise: exercise,
                onReplaceForToday: {
                    guard let session = plannedSession else { return }
                    onEditExerciseList(ExerciseLibraryIntent(
                        date: date,
                        session: session,
                        action: .replace(existingExerciseID: exercise.id)
                    ))
                    dismiss()
                },
                onRemoveFromToday: {
                    let removed = WorkoutScheduleStore.removeExercise(exercise.id, on: date, in: plan)
                    if removed { workoutOverrideRevision += 1 }
                    return removed
                }
            )
        }
        .confirmationDialog("Rest today?", isPresented: $showRestConfirmation, titleVisibility: .visible) {
            Button("Rest today", role: .destructive) {
                onSaveOverride?("rest")
                onSelectSession(nil)
                dismiss()
            }
        } message: {
            Text("This skips only this date. Your weekly plan stays the same.")
        }
    }
}
