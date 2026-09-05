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
    case share

    var id: String {
        switch self {
        case .dayAssign(let idx): return "dayAssign_\(idx)"
        case .editRoutine(let d): return "editRoutine_\(d.id)"
        case .share: return "share"
        }
    }
}

struct PlanView: View {
    let plan: WeeklyPlan
    let catalog: CatalogStore
    var onStartSession: (PlannedSession) -> Void

    @AppStorage("gym_custom_routines_json") private var routinesJSON: String = ""
    @AppStorage("gym_week_schedule_json") private var scheduleJSON: String = ""

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
        activeProviderProfile.flatMap { try? LLMProviderFactory.make(from: $0) }
    }

    private let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Big Title Header (openGym Parity)
                headerSection

                // 1. Week Schedule Section (Individual Day Cards)
                scheduleSection

                // 2. Routines Section
                routinesSection

                // 3. Weekly Volume Targets from AI
                targetsSection
            }
            .padding(.top, 8)
            .padding(.bottom, 90) // Pad for custom tab bar
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
        }
    }

    // MARK: - Subviews

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
                let planned = convertToPlannedSession(routine)
                onStartSession(planned)
            } label: {
                Text("Start")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GymTheme.bg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(GymTheme.green, in: Capsule())
            }
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
