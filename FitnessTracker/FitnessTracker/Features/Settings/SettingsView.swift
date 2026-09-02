import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @Query private var profiles: [UserProfile]
    @Query(sort: \StoredPlan.generatedAt, order: .reverse) private var plans: [StoredPlan]
    @Query private var allProviderProfiles: [ProviderProfile]
    private var activeProfiles: [ProviderProfile] { allProviderProfiles.filter(\.isActive) }
    @Query(sort: \AICallRecord.timestamp) private var calls: [AICallRecord]

    // App Preferences (AppStorage)
    @AppStorage("gym_weight_unit") private var weightUnit: String = "kg"
    @AppStorage("gym_week_start") private var weekStart: String = "monday"
    @AppStorage("gym_rest_sec") private var restSec: Int = 90
    @AppStorage("gym_rest_pause_sec") private var restPauseSec: Int = 15
    @AppStorage("gym_keep_awake") private var keepAwake: Bool = true
    @AppStorage("gym_sound") private var soundEnabled: Bool = true
    @AppStorage("gym_timer_flash") private var timerFlash: Bool = false
    @AppStorage("gym_effort_mode") private var effortMode: String = "rir"
    @AppStorage("gym_body_diagram") private var bodyDiagram: String = "male"
    @AppStorage("gym_accent_color") private var accentColor: String = "lime"
    @AppStorage("gym_theme") private var appTheme: String = "dark"

    @State private var catalog: CatalogStore?
    @State private var lastNote: String?
    @State private var isGenerating = false
    @State private var showEffortHelp = false
    @State private var showResetConfirm = false
    @State private var showExportShare = false
    @State private var exportURL: URL?

    private var summary: CostSummary {
        CostSummary.from(records: calls.map { .init(timestamp: $0.timestamp, costUSD: $0.costUSD) },
                         now: .now)
    }

    var body: some View {
        Form {
            // 1. Account & Local-First Storage
            accountSection

            // 2. AI Coach & Intelligence
            aiCoachSection

            // 3. Athlete Profile
            if let p = profiles.first {
                profileSection(p)
            }

            // 4. General Settings (openGym)
            generalSection

            // 5. During a Workout (openGym Live Mechanics)
            workoutMechanicsSection

            // 6. Appearance & Body Model (openGym)
            appearanceSection

            // 7. Data & Backup (openGym)
            dataSection
        }
        .scrollContentBackground(.hidden)
        .background(GymTheme.bg.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .fontWeight(.bold)
                    .foregroundStyle(GymTheme.green)
            }
        }
        .sheet(isPresented: $showEffortHelp) {
            effortHelpSheet
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .confirmationDialog(
            "Reset everything?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) { resetAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes your plan, workouts and body weight on this device. This cannot be undone.")
        }
        .overlay(alignment: .top) {
            if let lastNote {
                Text(lastNote)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: lastNote)
        .task(id: lastNote) {
            guard lastNote != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            lastNote = nil
        }
        .task {
            if catalog == nil { catalog = try? BundledCatalog.load() }
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
        .onChange(of: keepAwake) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
    }

    // MARK: - Account Section

    @ViewBuilder
    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(GymTheme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All data stays on this device")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GymTheme.label)
                    Text("Local-first SwiftData storage — no mandatory account, export backups anytime.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.60))
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Your Data")
        }
    }

    // MARK: - AI Coach Section

    @ViewBuilder
    private var aiCoachSection: some View {
        Section {
            NavigationLink {
                ProviderProfileListView()
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(GymTheme.purple)
                    Text("AI Providers & Keys")
                    Spacer()
                    Text(activeProfiles.first?.displayName ?? "Rule Engine")
                        .foregroundStyle(Color(white: 0.60))
                }
            }

            HStack {
                Text("This month")
                Spacer()
                Text(summary.monthToDateUSD.formatted(.currency(code: "USD")))
                    .foregroundStyle(Color(white: 0.60))
            }

            HStack {
                Text("AI calls logged")
                Spacer()
                Text("\(summary.callCount)")
                    .foregroundStyle(Color(white: 0.60))
            }
        } header: {
            Text("AI Coach & Providers")
        } footer: {
            Text("Configure local models (Ollama) or hosted endpoints (OpenAI, Gemini, Anthropic) with custom rate limits and zero lock-in.")
        }
    }

    // MARK: - Profile Section

    @ViewBuilder
    private func profileSection(_ p: UserProfile) -> some View {
        Section {
            LabeledContent("Goal", value: p.goalRaw.capitalized)
            LabeledContent("Experience", value: p.experienceRaw.capitalized)
            LabeledContent("Sessions / week", value: "\(p.sessionsPerWeek)")
            LabeledContent("Session length", value: "\(p.sessionLengthMinutes) min")
            LabeledContent("Equipment items", value: "\(p.availableEquipmentRaws.count)")

            Button {
                regenerate(p)
            } label: {
                HStack {
                    Text("Regenerate Weekly Plan")
                    Spacer()
                    if isGenerating {
                        ProgressView()
                    }
                }
            }
            .disabled(isGenerating)
        } header: {
            Text("Athlete Profile")
        }
    }

    // MARK: - General Section (openGym)

    @ViewBuilder
    private var generalSection: some View {
        Section {
            Picker("Weight unit", selection: $weightUnit) {
                Text("kg").tag("kg")
                Text("lb").tag("lb")
            }
            .pickerStyle(.segmented)

            Picker("Week starts on", selection: $weekStart) {
                Text("Monday").tag("monday")
                Text("Sunday").tag("sunday")
            }
            .pickerStyle(.segmented)
        } header: {
            Text("General")
        } footer: {
            Text("Switching units changes future displays and calculations.")
        }
    }

    // MARK: - Workout Mechanics Section (openGym)

    @ViewBuilder
    private var workoutMechanicsSection: some View {
        Section {
            Picker("Rest timer default", selection: $restSec) {
                Text("Off").tag(0)
                Text("60s").tag(60)
                Text("90s").tag(90)
                Text("120s").tag(120)
                Text("150s").tag(150)
                Text("180s").tag(180)
            }

            Picker("Rest-pause rest", selection: $restPauseSec) {
                Text("10s").tag(10)
                Text("15s").tag(15)
                Text("20s").tag(20)
                Text("30s").tag(30)
            }

            Toggle("Keep screen awake", isOn: $keepAwake)

            Toggle("Sounds & Haptic taps", isOn: $soundEnabled)

            Toggle("Flash screen when timer ends", isOn: $timerFlash)

            HStack {
                Text("Effort per set")
                Button { showEffortHelp = true } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(GymTheme.purple)
                }
                .buttonStyle(.plain)
                Spacer()
                Picker("", selection: $effortMode) {
                    Text("Off").tag("none")
                    Text("RIR").tag("rir")
                    Text("RPE").tag("rpe")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 170)
            }
        } header: {
            Text("During a Workout")
        } footer: {
            Text("The screen stays awake during workouts so you never have to unlock between heavy sets.")
        }
    }

    // MARK: - Appearance Section (openGym)

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            Picker("Body diagram", selection: $bodyDiagram) {
                Text("Male").tag("male")
                Text("Female").tag("female")
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Accent color")
                Spacer()
                HStack(spacing: 8) {
                    colorSwatch(key: "lime", color: GymTheme.green)
                    colorSwatch(key: "orange", color: GymTheme.orange)
                    colorSwatch(key: "yellow", color: GymTheme.yellow)
                    colorSwatch(key: "blue", color: GymTheme.blue)
                    colorSwatch(key: "purple", color: GymTheme.purple)
                }
            }
        } header: {
            Text("Appearance")
        }
    }

    @ViewBuilder
    private func colorSwatch(key: String, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 24, height: 24)
            .overlay(
                Circle().stroke(Color.white, lineWidth: accentColor == key ? 2.5 : 0)
            )
            .onTapGesture {
                accentColor = key
            }
    }

    // MARK: - Data Section (openGym)

    @ViewBuilder
    private var dataSection: some View {
        Section {
            Button("Load Starter Plan (PPL)") {
                if let p = profiles.first { regenerate(p) }
            }

            Button("Export backup (JSON)") {
                exportBackupJSON()
            }

            Button("Reset everything", role: .destructive) {
                showResetConfirm = true
            }
        } header: {
            Text("Data & Backups")
        }
    }

    // MARK: - Effort Help Sheet

    private var effortHelpSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Effort per set")
                    .font(.title2.bold())
                    .foregroundStyle(GymTheme.label)

                Text("How hard a set was, logged next to weight and reps. Two scales for the same judgement, counted from opposite ends.")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.70))

                VStack(spacing: 0) {
                    HStack {
                        Text("RIR").frame(width: 44, alignment: .leading)
                        Text("RPE").frame(width: 44, alignment: .leading)
                        Text("How it felt").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color(white: 0.50))
                    .padding(.bottom, 8)

                    Divider().background(Color.white.opacity(0.1))

                    effortRow(rir: "0", rpe: "10", feel: "Nothing left — went to failure", isAnchor: false)
                    effortRow(rir: "1", rpe: "9", feel: "One more rep in the tank", isAnchor: false)
                    effortRow(rir: "2", rpe: "8", feel: "Two more reps", isAnchor: true)
                    effortRow(rir: "3", rpe: "7", feel: "Three more reps", isAnchor: false)
                    effortRow(rir: "4+", rpe: "≤6", feel: "Easy — warm-up territory", isAnchor: false)
                }
                .padding(14)
                .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))

                Text("RIR counts the reps you left in reserve; RPE reads the same effort off a 10-point scale (RPE ≈ 10 − RIR).")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.60))

                Spacer()
            }
            .padding(20)
            .background(GymTheme.bgElevated.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showEffortHelp = false }
                        .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func effortRow(rir: String, rpe: String, feel: String, isAnchor: Bool) -> some View {
        HStack {
            Text(rir).frame(width: 44, alignment: .leading).font(.system(size: 14, weight: .bold))
            Text(rpe).frame(width: 44, alignment: .leading).font(.system(size: 14, weight: .bold))
            Text(feel).frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 13))
        }
        .foregroundStyle(isAnchor ? GymTheme.green : GymTheme.label)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func regenerate(_ profile: UserProfile) {
        guard let catalog, !isGenerating else { return }
        let userContext = profile.makeUserContext()
        let activeProfile = activeProfiles.first
        isGenerating = true
        Task {
            defer { isGenerating = false }
            let outcome = await generateAndStore(context: userContext,
                                                 activeProfile: activeProfile,
                                                 catalog: catalog,
                                                 modelContext: context)
            lastNote = outcome.note
        }
    }

    private func exportBackupJSON() {
        let fetchSessions = FetchDescriptor<CompletedSessionModel>()
        let fetchPlans = FetchDescriptor<StoredPlan>()
        let fetchBW = FetchDescriptor<BodyweightEntryModel>()
        
        let sessions = (try? context.fetch(fetchSessions)) ?? []
        let plans = (try? context.fetch(fetchPlans)) ?? []
        let bws = (try? context.fetch(fetchBW)) ?? []

        let exportDict: [String: Any] = [
            "version": 2,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "sessionsCount": sessions.count,
            "plansCount": plans.count,
            "bodyweightCount": bws.count
        ]

        if let data = try? JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted) {
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("opengym-backup-\(ISO8601DateFormatter().string(from: Date())).json")
            try? data.write(to: fileURL)
            self.exportURL = fileURL
            self.showExportShare = true
        }
    }

    private func resetAllData() {
        try? context.delete(model: CompletedSessionModel.self)
        try? context.delete(model: StoredPlan.self)
        try? context.delete(model: BodyweightEntryModel.self)
        try? context.delete(model: PersonalRecordModel.self)
        try? context.delete(model: UserProfile.self)
        try? context.save()
        dismiss()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
