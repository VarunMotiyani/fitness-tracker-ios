import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import RuleEngine
import LLMKit

private enum ActivePlanSheet: Identifiable {
    case dayAssign(weekdayIndex: Int)
    case editRoutine(draft: RoutineDraft)
    case splitBrowser
    case share

    var id: String {
        switch self {
        case .dayAssign(let idx): return "dayAssign_\(idx)"
        case .editRoutine(let d): return "editRoutine_\(d.id)"
        case .splitBrowser: return "splitBrowser"
        case .share: return "share"
        }
    }
}

struct PlanView: View {
    let plan: WeeklyPlan
    let catalog: CatalogStore
    var onStartSession: (PlannedSession) -> Void
    var onSplitChanged: (SplitTemplate) -> Void = { _ in }

    @AppStorage("gym_custom_routines_json") private var routinesJSON: String = ""
    @AppStorage("gym_week_schedule_json") private var scheduleJSON: String = ""
    @AppStorage("gym_split_template_name") private var selectedSplitName: String = ""
    @Query(sort: \CompletedSessionModel.startedAt, order: .reverse)
    private var completedSessions: [CompletedSessionModel]

    @State private var routines: [RoutineDraft] = []
    @State private var weekSchedule: [Int: UUID] = [:] // 0=Mon .. 6=Sun
    @State private var activeSheet: ActivePlanSheet? = nil
    @State private var showChat = false

    // Same plain @Query + Swift-side filter as `SessionContainerView`'s
    // `activeProviderProfile` — a #Predicate boolean filter here is what hung
    // Settings/Root and Settings/Providers earlier this project.
    @Query private var allProviderProfiles: [ProviderProfile]
    private var activeProviderProfile: ProviderProfile? { allProviderProfiles.first { $0.isActive } }
    private var chatProvider: (any LLMProvider)? {
        activeProviderProfile.flatMap { try? LLMProviderFactory.make(from: $0, fallback: $0.resolvedFallback(in: allProviderProfiles)) }
    }

    private let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Big Title Header (openGym Parity)
                headerSection

                // Split styles are separate from the routine cards below: the
                // cards show the active plan, while this control lets athletes
                // discover and choose the full template catalog.
                splitSection

                // 1. Week Schedule Section (Individual Day Cards)
                scheduleSection

                // 2. Routines Section
                routinesSection

                // 3. Weekly Volume Targets from AI
                targetsSection
            }
            .padding(.top, 8)
            .padding(.bottom, 100) // Pad for custom tab bar
        }
        .background(GymTheme.bg.ignoresSafeArea())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .dayAssign(let weekdayIdx):
                DayAssignSheet(
                    weekdayName: dayNames[weekdayIdx],
                    routines: routines,
                    currentRoutineID: weekSchedule[weekdayIdx],
                    onAssign: { assignedID in
                        if let assignedID {
                            weekSchedule[weekdayIdx] = assignedID
                        } else {
                            weekSchedule.removeValue(forKey: weekdayIdx)
                        }
                        saveSchedule()
                    }
                )
            case .editRoutine(let draft):
                RoutineEditView(
                    routine: Binding(
                        get: { draft },
                        set: { updated in
                            if let idx = routines.firstIndex(where: { $0.id == updated.id }) {
                                routines[idx] = updated
                                saveRoutines()
                            }
                        }
                    ),
                    catalog: catalog,
                    onSave: { saved in
                        if let idx = routines.firstIndex(where: { $0.id == saved.id }) {
                            routines[idx] = saved
                            saveRoutines()
                        }
                        activeSheet = nil
                    },
                    onDelete: { routineID in
                        routines.removeAll { $0.id == routineID }
                        saveRoutines()
                        activeSheet = nil
                    }
                )
            case .splitBrowser:
                SplitTemplateBrowserSheet(
                    selectedTemplateName: selectedSplitName,
                    onApply: { template in
                        selectedSplitName = template.name
                        onSplitChanged(template)
                    }
                )
            case .share:
                PlanShareSheet(
                    routines: routines,
                    onImport: { importedRoutines in
                        self.routines = importedRoutines
                        saveRoutines()
                    }
                )
            }
        }
        .sheet(isPresented: $showChat) {
            ChatView(catalog: catalog, provider: chatProvider, activeProfile: activeProviderProfile, onClose: { showChat = false })
        }
        .onAppear {
            loadRoutines()
            loadSchedule()
            WorkoutScheduleStore.refresh(completedSessions: completedSessions, plan: plan)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var splitSection: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            activeSheet = .splitBrowser
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GymTheme.green)
                    .frame(width: 40, height: 40)
                    .background(GymTheme.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Training split")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GymTheme.label)
                    Text(selectedSplitName.isEmpty ? "Explore 17 evidence-based templates" : selectedSplitName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GymTheme.label2)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                Text("Browse")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GymTheme.green)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GymTheme.green)
            }
            .padding(14)
            .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityLabel("Training split")
        .accessibilityValue(selectedSplitName.isEmpty ? "No split selected" : selectedSplitName)
        .accessibilityHint("Browse and choose from all available split templates")
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plan")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(GymTheme.label)

                Text("Your weekly routine")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(white: 0.65))
            }

            Spacer()

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                showChat = true
            } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(white: 0.70))
                    .frame(width: 38, height: 38)
                    .background(GymTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                activeSheet = .share
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GymTheme.green)
                    .frame(width: 38, height: 38)
                    .background(GymTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Week schedule")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GymTheme.label)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { idx in
                    let dayName = dayNames[idx]
                    let routineID = weekSchedule[idx]
                    let assignedRoutine = routines.first { $0.id == routineID }

                    Button {
                        activeSheet = .dayAssign(weekdayIndex: idx)
                    } label: {
                        HStack {
                            Text(dayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(GymTheme.label)
                            Spacer()
                            if let routine = assignedRoutine {
                                HStack(spacing: 6) {
                                    Image(systemName: routine.iconName)
                                        .font(.system(size: 11))
                                    Text(routine.name)
                                        .font(.system(size: 12, weight: .bold))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundStyle(GymTheme.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(GymTheme.green.opacity(0.16), in: Capsule())
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
                        .padding(.vertical, 14)
                        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Routines")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GymTheme.label)
                Spacer()
                Button {
                    let newR = RoutineDraft(name: "New Routine", exercises: [])
                    routines.append(newR)
                    saveRoutines()
                    activeSheet = .editRoutine(draft: newR)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GymTheme.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(GymTheme.green.opacity(0.16), in: Capsule())
                }
            }
            .padding(.horizontal, 16)

            if routines.isEmpty {
                VStack(spacing: 12) {
                    Text("No routines found.")
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.label3)

                    Button {
                        routines = StarterRoutines.ppl()
                        saveRoutines()
                    } label: {
                        Text("Load Starter Plan (PPL)")
                            .font(.subheadline.bold())
                            .foregroundStyle(GymTheme.bg)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(GymTheme.green, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(routines) { routine in
                        routineCard(routine)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func routineCard(_ routine: RoutineDraft) -> some View {
        let cardAction = RoutineCardAction.action(for: routine)

        HStack(spacing: 12) {
            Button {
                activeSheet = .editRoutine(draft: routine)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: routine.iconName)
                        .font(.system(size: 20))
                        .foregroundStyle(GymTheme.green)
                        .frame(width: 44, height: 44)
                        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(routine.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(GymTheme.label)
                        Text("\(routine.exercises.count) exercises")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(GymTheme.label3)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                switch cardAction {
                case .edit:
                    activeSheet = .editRoutine(draft: routine)
                case .start:
                    onStartSession(convertToPlannedSession(routine))
                }
            } label: {
                Text(cardAction == .start ? "Start" : "Add exercises")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GymTheme.bg)
                    .padding(.horizontal, cardAction == .start ? 16 : 12)
                    .padding(.vertical, 8)
                    .background(GymTheme.green, in: Capsule())
            }
            .accessibilityHint(cardAction == .start ? "Start this routine" : "Open the routine editor to add exercises")
        }
        .padding(14)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var targetsSection: some View {
        if !plan.weeklyVolumeTargets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Weekly volume targets")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GymTheme.label)
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    ForEach(Array(plan.weeklyVolumeTargets.enumerated()), id: \.offset) { idx, target in
                        HStack {
                            Text(target.muscle.rawValue.capitalized)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(GymTheme.label)
                            Spacer()
                            Text("\(target.targetSets) sets")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(GymTheme.green)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

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
    }

    // MARK: - Persistence & Mapping

    private func loadRoutines() {
        if !routinesJSON.isEmpty,
           let data = routinesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([RoutineDraft].self, from: data) {
            routines = decoded
        } else {
            routines = StarterRoutines.ppl()
            saveRoutines()
        }
    }

    private func saveRoutines() {
        if let data = try? JSONEncoder().encode(routines),
           let str = String(data: data, encoding: .utf8) {
            routinesJSON = str
        }
    }

    private func loadSchedule() {
        if !scheduleJSON.isEmpty,
           let data = scheduleJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Int: UUID].self, from: data) {
            weekSchedule = decoded
        } else {
            if routines.count >= 3 {
                weekSchedule = [
                    0: routines[0].id,
                    2: routines[1].id,
                    4: routines[2].id
                ]
            }
            saveSchedule()
        }
    }

    private func saveSchedule() {
        if let data = try? JSONEncoder().encode(weekSchedule),
           let str = String(data: data, encoding: .utf8) {
            scheduleJSON = str
            WorkoutScheduleStore.saveWeekSchedule(weekSchedule)
        }
    }

    private func convertToPlannedSession(_ draft: RoutineDraft) -> PlannedSession {
        let items: [PlannedItem] = draft.exercises.enumerated().map { _, ex in
            let minR = ex.repsMin ?? ex.reps
            let maxR = ex.repsMax ?? ex.reps
            let repRange = RepRange(min: minR, max: max(minR, maxR))
            let load: Double? = ex.weightKg > 0 ? ex.weightKg : nil

            return PlannedItem(
                exerciseID: ex.exerciseID,
                targetSets: ex.sets,
                targetReps: repRange,
                targetLoadKg: load,
                restSeconds: ex.restSec ?? 90,
                coachNote: ex.coachNote
            )
        }

        let muscles = Array(Set(draft.exercises.compactMap {
            catalog.exercise(id: $0.exerciseID)?.primaryMuscle
        }))

        return PlannedSession(
            id: UUID(),
            order: 0,
            focusMuscles: muscles,
            items: items
        )
    }
}

private struct SplitTemplateBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedTemplateName: String
    let onApply: (SplitTemplate) -> Void
    @State private var query = ""
    @State private var selection: String?

    init(selectedTemplateName: String, onApply: @escaping (SplitTemplate) -> Void) {
        self.selectedTemplateName = selectedTemplateName
        self.onApply = onApply
        _selection = State(initialValue: selectedTemplateName.isEmpty ? nil : selectedTemplateName)
    }

    private var matchingTemplates: [SplitTemplate] {
        SplitTemplateBrowser.templates(matching: query)
    }

    private var dayCounts: [Int] {
        Array(Set(matchingTemplates.map(\.sessionCount))).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Choose how you train")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(GymTheme.label)
                        Text("Pick a split that matches your schedule. You can still edit every routine and exercise afterward.")
                            .font(.system(size: 14))
                            .foregroundStyle(GymTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                ForEach(dayCounts, id: \.self) { count in
                    let templates = matchingTemplates.filter { $0.sessionCount == count }
                    Section("\(count)-day splits") {
                        ForEach(templates, id: \.name) { template in
                            templateRow(template)
                        }
                    }
                }

                if matchingTemplates.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(GymTheme.bg.ignoresSafeArea())
            .searchable(text: $query, prompt: "Search splits")
            .navigationTitle("Training splits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GymTheme.label2)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let selectedTemplate = matchingTemplates.first(where: { $0.name == selection }) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onApply(selectedTemplate)
                        dismiss()
                    } label: {
                        Text("Use \(selectedTemplate.name)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(GymTheme.green, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(GymTheme.bg.opacity(0.96))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func templateRow(_ template: SplitTemplate) -> some View {
        Button {
            selection = template.name
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName(for: template))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GymTheme.green)
                    .frame(width: 38, height: 38)
                    .background(GymTheme.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GymTheme.label)
                    Text(focusSummary(for: template))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(GymTheme.label2)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                if selection == template.name {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(GymTheme.green)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(GymTheme.label4)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(template.name)
        .accessibilityValue(selection == template.name ? "Selected" : "Not selected")
        .listRowBackground(GymTheme.surface)
    }

    private func focusSummary(for template: SplitTemplate) -> String {
        let labels = template.sessionFocuses.prefix(4).map { muscles -> String in
            switch WorkoutFocus.classify(muscles: Set(muscles)) {
            case .push: "Push"
            case .pull: "Pull"
            case .legs: "Legs"
            case .upper: "Upper"
            case .lower: "Lower"
            case .fullBody: "Full body"
            case .chestBack: "Chest + back"
            case .shouldersArms: "Shoulders + arms"
            case .arms: "Arms"
            case .posteriorChain: "Posterior chain"
            case .quadGlute: "Quads + glutes"
            case .hamstringGlute: "Hamstrings + glutes"
            case .core: "Core"
            case .conditioning: "Conditioning"
            case .power: "Power"
            case .mobilityRecovery: "Mobility"
            case .custom: "Custom"
            }
        }
        let suffix = template.sessionCount > 4 ? " + more" : ""
        return labels.joined(separator: " · ") + suffix
    }

    private func iconName(for template: SplitTemplate) -> String {
        let first = template.sessionFocuses.first.map { WorkoutFocus.classify(muscles: Set($0)) }
        switch first {
        case .some(.legs), .some(.lower), .some(.quadGlute), .some(.hamstringGlute):
            return "figure.run"
        case .some(.pull), .some(.posteriorChain), .some(.chestBack):
            return "figure.rower"
        case .some(.conditioning):
            return "figure.outdoor.cycle"
        case .some(.mobilityRecovery):
            return "figure.flexibility"
        default:
            return "figure.strengthtraining.traditional"
        }
    }
}
