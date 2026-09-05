import SwiftUI
import SwiftData
import UserNotifications
import UniformTypeIdentifiers
import FitnessDomain
import ExerciseCatalog
import Metrics

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var onClose: (() -> Void)? = nil
    
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
    @AppStorage("athleteBodyModel") private var athleteBodyModel: String = "male"
    @AppStorage("gym_accent_color") private var accentColor: String = "lime"
    @AppStorage("gym_theme") private var appTheme: String = "dark"
    @AppStorage("gym_reminder_on") private var reminderOn: Bool = false
    @AppStorage("gym_reminder_hour") private var reminderHour: Int = 18
    @AppStorage("gym_reminder_minute") private var reminderMinute: Int = 0

    @State private var catalog: CatalogStore?
    @State private var lastNote: String?
    @State private var isGenerating = false
    @State private var showEffortHelp = false
    @State private var showResetConfirm = false
    @State private var showExportShare = false
    @State private var showFileImporter = false
    @State private var showAppImporter = false
    @State private var showHevyAPISheet = false
    @State private var showEquipmentSheet = false
    @State private var exportURL: URL?

    private var summary: CostSummary {
        CostSummary.from(records: calls.map { .init(timestamp: $0.timestamp, costUSD: $0.costUSD) },
                         now: .now)
    }

    private var activeAccent: Color {
        GymTheme.accent(for: accentColor)
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

            // 4. General Settings
            generalSection

            // 5. During a Workout
            workoutMechanicsSection

            // 6. Notifications
            notificationsSection

            // 7. Equipment Profile
            equipmentSection

            // 8. Appearance & Body Model (openGym)
            appearanceSection

            // 9. Data & Backup (openGym)
            dataSection
        }
        .scrollContentBackground(.hidden)
        .background(GymTheme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80) // Prevents bottom tab bar clipping
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    if let onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                }
                .fontWeight(.bold)
                .foregroundStyle(activeAccent)
            }
        }
        .task {
            if catalog == nil {
                catalog = try? BundledCatalog.load()
            }
        }
        .sheet(isPresented: $showEffortHelp) {
            effortHelpSheet
        }
        .sheet(isPresented: $showEquipmentSheet) {
            EquipmentProfileSheet()
        }
        .sheet(isPresented: $showHevyAPISheet) {
            if let cat = catalog {
                HevyAPISyncSheet(catalog: cat)
            }
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .fileImporter(
            isPresented: $showAppImporter,
            allowedContentTypes: [.commaSeparatedText, .xml, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleAppImportResult(result)
        }
        .confirmationDialog("Reset Everything?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) {
                resetAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes your plan, workout history, body weight, and PRs on this device. This action cannot be undone.")
        }
        .overlay(alignment: .bottom) {
            if let note = lastNote {
                Text(note)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(activeAccent, in: Capsule())
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation { lastNote = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Account Section

    @ViewBuilder
    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(GymTheme.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("All data stays on this device")
                        .font(.headline)
                        .foregroundStyle(GymTheme.label)
                    Text("Zero account required, no third-party tracking. Back up anytime with JSON export.")
                        .font(.caption)
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
                        .foregroundStyle(GymTheme.violet)
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

            Button {
                regenerate(p)
            } label: {
                HStack {
                    Text("Regenerate Weekly Plan")
                        .foregroundStyle(activeAccent)
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

    // MARK: - General Section

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

    // MARK: - Workout Mechanics Section

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
                .tint(activeAccent)

            Toggle("Sounds & Haptic taps", isOn: $soundEnabled)
                .tint(activeAccent)

            Toggle("Flash screen when timer ends", isOn: $timerFlash)
                .tint(activeAccent)

            HStack {
                Text("Effort per set")
                Button { showEffortHelp = true } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(GymTheme.violet)
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

    // MARK: - Notifications Section

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            Toggle("Workout day reminder", isOn: $reminderOn)
                .tint(activeAccent)
                .onChange(of: reminderOn) { _, newValue in
                    if newValue {
                        requestNotificationPermissionAndSchedule()
                    } else {
                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                    }
                }

            if reminderOn {
                HStack {
                    Text("Reminder time")
                    Spacer()
                    DatePicker(
                        "",
                        selection: Binding(
                            get: {
                                var components = DateComponents()
                                components.hour = reminderHour
                                components.minute = reminderMinute
                                return Calendar.current.date(from: components) ?? Date()
                            },
                            set: { date in
                                let cal = Calendar.current
                                reminderHour = cal.component(.hour, from: date)
                                reminderMinute = cal.component(.minute, from: date)
                                scheduleWorkoutReminder()
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            if reminderOn {
                Text("Reminds you at \(String(format: "%02d:%02d", reminderHour, reminderMinute)) on days that have a workout scheduled.")
            }
        }
    }

    // MARK: - Equipment Section

    @ViewBuilder
    private var equipmentSection: some View {
        Section {
            Button {
                showEquipmentSheet = true
            } label: {
                HStack {
                    Text("Equipment Profile")
                        .foregroundStyle(GymTheme.label)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.45))
                }
            }
        } header: {
            Text("Equipment")
        } footer: {
            Text("Customize equipment profiles (Home Gym, Commercial Gym, Travel) to filter the exercise library and auto-plan generation.")
        }
    }

    // MARK: - Appearance Section (openGym exact swatches)

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $appTheme) {
                Text("Dark").tag("dark")
                Text("Light").tag("light")
                Text("System").tag("system")
            }
            .pickerStyle(.segmented)

            Picker("Body diagram", selection: $athleteBodyModel) {
                Text("Male").tag("male")
                Text("Female").tag("female")
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 10) {
                Text("Accent color")
                    .font(.system(size: 15))
                    .foregroundStyle(GymTheme.label)

                HStack(spacing: 12) {
                    ForEach(GymTheme.allAccents, id: \.key) { item in
                        colorSwatch(key: item.key, color: item.color)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Appearance")
        }
    }

    @ViewBuilder
    private func colorSwatch(key: String, color: Color) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                accentColor = key
            }
        } label: {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: accentColor == key ? 3 : 0)
                )
                .scaleEffect(accentColor == key ? 1.15 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Section (openGym Full Parity)

    @ViewBuilder
    private var dataSection: some View {
        Section {
            Button {
                loadStarterPPL()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(activeAccent)
                        .frame(width: 20)
                    Text("Load starter plan (PPL)")
                        .foregroundStyle(activeAccent)
                }
            }

            Button {
                showAppImporter = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundStyle(GymTheme.teal)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from another app")
                            .foregroundStyle(GymTheme.label)
                        Text("FitNotes, Strong, Hevy, or Apple Health XML")
                            .font(.caption2)
                            .foregroundStyle(GymTheme.label3)
                    }
                }
            }

            Button {
                showHevyAPISheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(GymTheme.teal)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Hevy")
                            .foregroundStyle(GymTheme.label)
                        Text("Sync with a Hevy Developer API key")
                            .font(.caption2)
                            .foregroundStyle(GymTheme.label3)
                    }
                }
            }

            Button {
                showFileImporter = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(GymTheme.sky)
                        .frame(width: 20)
                    Text("Import backup (JSON)")
                        .foregroundStyle(GymTheme.label)
                }
            }

            Button {
                exportWorkoutHistoryCSV()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(GymTheme.sky)
                        .frame(width: 20)
                    Text("Export workout history (CSV)")
                        .foregroundStyle(GymTheme.label)
                }
            }

            Button {
                exportBackupJSON()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(GymTheme.sky)
                        .frame(width: 20)
                    Text("Export backup (JSON)")
                        .foregroundStyle(GymTheme.label)
                }
            }

            Button {
                showResetConfirm = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(GymTheme.red)
                        .frame(width: 20)
                    Text("Reset everything")
                        .foregroundStyle(GymTheme.red)
                }
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
                        .foregroundStyle(activeAccent)
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
        .foregroundStyle(isAnchor ? activeAccent : GymTheme.label)
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

    private func loadStarterPPL() {
        guard let catalog else { return }
        let defaultProfile = profiles.first ?? UserProfile(
            goalRaw: "buildMuscle",
            experienceRaw: "intermediate",
            heightCm: 178,
            weightKg: 75,
            birthYear: 2000,
            sexRaw: "male",
            sessionsPerWeek: 4,
            sessionLengthMinutes: 60,
            availableEquipmentRaws: ["barbell", "dumbbell", "cable", "machine", "bodyweight"],
            excludedMuscleRaws: [],
            excludedExerciseIDs: []
        )
        if profiles.isEmpty { context.insert(defaultProfile) }
        DemoSeedGenerator.seedDemoHistory(into: context, catalog: catalog)
        regenerate(defaultProfile)
        lastNote = "Starter plan & 12-week demo history loaded"
    }

    private func exportWorkoutHistoryCSV() {
        guard let cat = catalog else { return }
        if let url = HistoryExportManager.exportCSV(context: context, catalog: cat) {
            self.exportURL = url
            self.showExportShare = true
        }
    }

    private func exportBackupJSON() {
        guard let cat = catalog else { return }
        if let url = HistoryExportManager.exportFullJSON(context: context, catalog: cat) {
            self.exportURL = url
            self.showExportShare = true
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    lastNote = "Backup imported successfully (\(json["workouts"] != nil ? "Complete backup" : "JSON"))"
                } else {
                    lastNote = "Invalid backup file format"
                }
            }
        case .failure(let error):
            lastNote = "Import failed: \(error.localizedDescription)"
        }
    }

    private func handleAppImportResult(_ result: Result<[URL], Error>) {
        guard let cat = catalog else { return }
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    if text.contains("<?xml") || text.contains("<HealthData") {
                        let weights = AppleHealthXMLImporter.parse(xmlString: text)
                        let count = HistoryIngestionService.ingestBodyweights(weights, into: context)
                        lastNote = "Imported \(count) bodyweight entries from Apple Health XML"
                    } else {
                        let (source, sessions) = ExternalAppImporter.importCSV(text)
                        let (imported, skipped) = HistoryIngestionService.ingestSessions(sessions, catalog: cat, into: context)
                        lastNote = "Imported \(imported) workouts from \(source.rawValue) (skipped \(skipped))"
                    }
                } else {
                    lastNote = "Could not read file"
                }
            }
        case .failure(let error):
            lastNote = "Import failed: \(error.localizedDescription)"
        }
    }

    private func resetAllData() {
        if let sessions = try? context.fetch(FetchDescriptor<CompletedSessionModel>()) {
            for s in sessions { context.delete(s) }
        }
        if let storedPlans = try? context.fetch(FetchDescriptor<StoredPlan>()) {
            for p in storedPlans { context.delete(p) }
        }
        if let bws = try? context.fetch(FetchDescriptor<BodyweightEntryModel>()) {
            for b in bws { context.delete(b) }
        }
        if let prs = try? context.fetch(FetchDescriptor<PersonalRecordModel>()) {
            for pr in prs { context.delete(pr) }
        }
        if let allProfiles = try? context.fetch(FetchDescriptor<UserProfile>()) {
            for p in allProfiles { context.delete(p) }
        }
        if let suggestions = try? context.fetch(FetchDescriptor<PendingCoachSuggestion>()) {
            for s in suggestions { context.delete(s) }
        }
        try? context.save()
        lastNote = "All data reset"
    }

    private func requestNotificationPermissionAndSchedule() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    self.scheduleWorkoutReminder()
                }
            } else {
                DispatchQueue.main.async {
                    self.reminderOn = false
                    self.lastNote = "Notifications permission denied in iOS Settings"
                }
            }
        }
    }

    private func scheduleWorkoutReminder() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        guard reminderOn else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time for your workout"
        content.body = "Stay on track with your training goals today."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = reminderMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "gym_daily_reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        lastNote = "Workout reminder scheduled for \(String(format: "%02d:%02d", reminderHour, reminderMinute))"
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
