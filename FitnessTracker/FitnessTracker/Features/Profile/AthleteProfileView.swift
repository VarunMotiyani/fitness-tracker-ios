import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import RuleEngine
import LLMKit

/// The athlete-owned source of truth for training inputs and current body
/// composition. InBody ingestion will write this same snapshot after review.
struct AthleteProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allProviderProfiles: [ProviderProfile]
    @Query(sort: \BodyweightEntryModel.date, order: .reverse) private var bodyweightEntries: [BodyweightEntryModel]

    let profile: UserProfile
    let catalog: CatalogStore?
    var onOpenPlan: (() -> Void)?

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    @State private var showEditor = false
    @State private var needsPlanRegeneration = false
    @State private var isGenerating = false
    @State private var statusMessage: String?
    @State private var showAllMeasurements = false

    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }
    private var activeProvider: ProviderProfile? { allProviderProfiles.first { $0.isActive } }
    /// Logged weigh-ins are the current-weight source of truth. The persisted
    /// profile value remains a fallback for a new athlete with no history.
    private var currentWeightKg: Double { bodyweightEntries.first?.kg ?? profile.weightKg }
    private var currentBMI: Double? {
        guard profile.heightCm > 0, currentWeightKg > 0 else { return nil }
        let heightM = profile.heightCm / 100
        return currentWeightKg / (heightM * heightM)
    }
    private var hasAdditionalMeasurements: Bool {
        [profile.bodyFatMassKg, profile.fatFreeMassKg, profile.totalBodyWaterL,
         profile.proteinKg, profile.mineralKg, profile.visceralFatLevel,
         profile.inBodyScore, profile.waistHipRatio, profile.phaseAngleDegrees]
            .contains { $0 != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroCard
                    trainingSetupCard
                    bodyCompositionSection
                    planActions
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(GymTheme.bg.ignoresSafeArea())
            .navigationTitle("Athlete Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GymTheme.label2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit profile") { showEditor = true }
                        .fontWeight(.bold)
                        .foregroundStyle(activeAccent)
                }
            }
            .sheet(isPresented: $showEditor) {
                AthleteProfileEditorView(profile: profile, currentWeightKg: currentWeightKg) { planInputsChanged in
                    needsPlanRegeneration = needsPlanRegeneration || planInputsChanged
                    statusMessage = "Profile saved"
                }
            }
            .overlay(alignment: .bottom) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(activeAccent, in: Capsule())
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task(id: statusMessage) {
                guard statusMessage != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                statusMessage = nil
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 56, height: 56)
                    .background(activeAccent, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("YOUR TRAINING FOUNDATION")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GymTheme.label3)
                    Text(goalLabel)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(GymTheme.label)
                    Text("\(experienceLabel) · \(profile.sessionsPerWeek) sessions/week")
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.label2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                heroMetric(title: "CURRENT WEIGHT", value: weightText, symbol: "scalemass.fill")
                heroMetric(title: "SESSION TIME", value: "\(profile.sessionLengthMinutes) min", symbol: "clock.fill")
                heroMetric(title: "BMI", value: currentBMI.map { String(format: "%.1f", $0) } ?? "—", symbol: "chart.line.uptrend.xyaxis")
            }
        }
        .padding(18)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private func heroMetric(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(activeAccent)
                .accessibilityHidden(true)
            Text(value)
                .font(.body.weight(.bold)).fontDesign(.rounded)
                .foregroundStyle(GymTheme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(GymTheme.label3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 14))
    }

    private var trainingSetupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("Training setup", subtitle: "These settings shape your next plan")

            profileRow("Goal", value: goalLabel, symbol: "scope")
            divider
            profileRow("Experience", value: experienceLabel, symbol: "figure.run")
            divider
            profileRow("Training capacity", value: "\(profile.sessionsPerWeek) × \(profile.sessionLengthMinutes) min", symbol: "calendar")
            divider
            profileRow("Split style", value: profile.splitTemplateName ?? "Auto", symbol: "square.grid.2x2.fill")
            divider
            profileRow("Equipment", value: equipmentSummary, symbol: "dumbbell.fill")

            if !profile.excludedMuscleRaws.isEmpty {
                divider
                profileRow("Training around", value: excludedMuscleSummary, symbol: "cross.case.fill")
            }
        }
        .padding(18)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var bodyCompositionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Body composition", subtitle: "Your current snapshot")

            if profile.bodyFatPercent == nil && profile.skeletalMuscleMassKg == nil && profile.basalMetabolicRateKcal == nil {
                Button { showEditor = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(activeAccent)
                            .frame(width: 42, height: 42)
                            .background(activeAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Add your measurements")
                                .font(.headline)
                                .foregroundStyle(GymTheme.label)
                            Text("Track body fat, skeletal muscle, water, BMR and more.")
                                .font(.subheadline)
                                .foregroundStyle(GymTheme.label2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(GymTheme.label3)
                            .accessibilityHidden(true)
                    }
                    .padding(16)
                    .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add body-composition measurements")
                .accessibilityHint("Opens the profile editor")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    compositionMetric("Weight", value: weightText, symbol: "scalemass.fill", tint: activeAccent)
                    compositionMetric("Body fat", value: profile.bodyFatPercent.map { String(format: "%.1f%%", $0) } ?? "—", symbol: "percent", tint: GymTheme.orange)
                    compositionMetric("Skeletal muscle", value: profile.skeletalMuscleMassKg.map { String(format: "%.1f kg", $0) } ?? "—", symbol: "figure.strengthtraining.traditional", tint: GymTheme.sky)
                    compositionMetric("BMR", value: profile.basalMetabolicRateKcal.map { "\(Int($0.rounded())) kcal" } ?? "—", symbol: "flame.fill", tint: GymTheme.red)
                }

                if hasAdditionalMeasurements {
                    DisclosureGroup(isExpanded: $showAllMeasurements) {
                        VStack(spacing: 0) {
                            measurementRow("Body fat mass", profile.bodyFatMassKg, unit: "kg")
                            measurementRow("Fat-free mass", profile.fatFreeMassKg, unit: "kg")
                            measurementRow("Total body water", profile.totalBodyWaterL, unit: "L")
                            measurementRow("Protein", profile.proteinKg, unit: "kg")
                            measurementRow("Minerals", profile.mineralKg, unit: "kg")
                            measurementRow("Visceral fat level", profile.visceralFatLevel, unit: "")
                            measurementRow("InBody score", profile.inBodyScore, unit: "/100")
                            measurementRow("Waist–hip ratio", profile.waistHipRatio, unit: "")
                            measurementRow("Phase angle", profile.phaseAngleDegrees, unit: "°")
                        }
                        .padding(.top, 10)
                    } label: {
                        Text(showAllMeasurements ? "Hide detailed measurements" : "View detailed measurements")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(activeAccent)
                    }
                    .tint(activeAccent)
                    .padding(16)
                    .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    private var planActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Your plan", subtitle: needsPlanRegeneration ? "Your training setup has changed" : "Make the week fit your life")

            Button {
                regeneratePlan()
            } label: {
                HStack(spacing: 10) {
                    if isGenerating { ProgressView().tint(.black) }
                    Image(systemName: "sparkles")
                        .accessibilityHidden(true)
                    Text(isGenerating ? "Updating your plan…" : "Regenerate weekly plan")
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                        .accessibilityHidden(true)
                }
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(activeAccent, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(isGenerating || catalog == nil)
            .opacity(catalog == nil ? 0.45 : 1)
            .accessibilityHint(catalog == nil ? "The exercise catalog is still loading." : "Builds a new weekly plan from this profile.")

            Button {
                dismiss()
                onOpenPlan?()
            } label: {
                HStack {
                    Image(systemName: "calendar.badge.gearshape")
                        .foregroundStyle(activeAccent)
                        .accessibilityHidden(true)
                    Text("Manage routines and schedule")
                        .foregroundStyle(GymTheme.label)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GymTheme.label3)
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .padding(16)
                .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(GymTheme.label)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(GymTheme.label2)
        }
    }

    private func profileRow(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(activeAccent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(.body)
                .foregroundStyle(GymTheme.label)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(GymTheme.label2)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Divider().overlay(Color.white.opacity(0.10))
    }

    private func compositionMetric(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(GymTheme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(GymTheme.label3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func measurementRow(_ title: String, _ value: Double?, unit: String) -> some View {
        if let value {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.label2)
                Spacer()
                Text(measurementText(value, unit: unit))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GymTheme.label)
            }
            .padding(.vertical, 9)
        }
    }

    private func measurementText(_ value: Double, unit: String) -> String {
        let number = value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    private var weightText: String { String(format: "%.1f kg", currentWeightKg) }
    private var goalLabel: String { (Goal(rawValue: profile.goalRaw) ?? .generalFitness).label }
    private var experienceLabel: String { (ExperienceLevel(rawValue: profile.experienceRaw) ?? .beginner).label }
    private var equipmentSummary: String {
        let labels = profile.availableEquipmentRaws.compactMap { Equipment(rawValue: $0)?.label }
        return labels.isEmpty ? "Not set" : labels.count <= 2 ? labels.joined(separator: ", ") : "\(labels.prefix(2).joined(separator: ", ")) +\(labels.count - 2)"
    }
    private var excludedMuscleSummary: String {
        profile.excludedMuscleRaws.compactMap { MuscleGroup(rawValue: $0)?.label }.joined(separator: ", ")
    }

    private func regeneratePlan() {
        guard let catalog, !isGenerating else { return }
        isGenerating = true
        Task {
            defer { isGenerating = false }
            let outcome = await generateAndStore(
                context: profile.makeUserContext(), activeProfile: activeProvider,
                catalog: catalog, modelContext: context)
            needsPlanRegeneration = false
            statusMessage = outcome.note
        }
    }
}

private struct AthleteProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let profile: UserProfile
    let currentWeightKg: Double
    let onSaved: (Bool) -> Void

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    @State private var draft: AthleteProfileDraft
    @State private var validationMessage: String?
    @State private var isSaving = false

    private let birthYears = Array((1950...2010).reversed())
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    init(profile: UserProfile, currentWeightKg: Double, onSaved: @escaping (Bool) -> Void) {
        self.profile = profile
        self.currentWeightKg = currentWeightKg
        self.onSaved = onSaved
        var initialDraft = AthleteProfileDraft(profile: profile)
        initialDraft.weightKg = currentWeightKg
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    LabeledContent("Height") {
                        HStack(spacing: 6) {
                            TextField("", value: $draft.heightCm, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("cm").foregroundStyle(GymTheme.label3)
                        }
                    }
                    LabeledContent("Current weight") {
                        HStack(spacing: 6) {
                            TextField("", value: $draft.weightKg, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("kg").foregroundStyle(GymTheme.label3)
                        }
                    }
                    Picker("Birth year", selection: $draft.birthYear) {
                        ForEach(birthYears, id: \.self) { Text(String($0)).tag($0) }
                    }
                    Picker("Sex", selection: $draft.sexRaw) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                        Text("Prefer not to say").tag("unspecified")
                    }
                }

                Section("Training") {
                    Picker("Goal", selection: $draft.goalRaw) {
                        ForEach(Goal.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Experience", selection: $draft.experienceRaw) {
                        ForEach(ExperienceLevel.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                    Stepper("Sessions per week: \(draft.sessionsPerWeek)", value: $draft.sessionsPerWeek, in: 2...7)
                    NavigationLink {
                        splitStyleEditor
                    } label: {
                        HStack {
                            Text("Split style")
                            Spacer()
                            Text(draft.splitTemplateName)
                                .foregroundStyle(GymTheme.label2)
                                .lineLimit(1)
                        }
                    }
                    Picker("Session length", selection: $draft.sessionLengthMinutes) {
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                        Text("90 min").tag(90)
                    }
                    NavigationLink("Equipment") { equipmentEditor }
                    NavigationLink("Areas to avoid") { limitationEditor }
                }

                Section("Core composition") {
                    optionalField("Body fat (%)", keyPath: \.bodyFatPercent)
                    optionalField("Skeletal muscle mass (kg)", keyPath: \.skeletalMuscleMassKg)
                    optionalField("Body fat mass (kg)", keyPath: \.bodyFatMassKg)
                    optionalField("Fat-free mass (kg)", keyPath: \.fatFreeMassKg)
                }

                Section("InBody-compatible measurements") {
                    optionalField("Total body water (L)", keyPath: \.totalBodyWaterL)
                    optionalField("Protein (kg)", keyPath: \.proteinKg)
                    optionalField("Minerals (kg)", keyPath: \.mineralKg)
                    optionalField("Basal metabolic rate (kcal)", keyPath: \.basalMetabolicRateKcal)
                    optionalField("Visceral fat level", keyPath: \.visceralFatLevel)
                    optionalField("InBody score", keyPath: \.inBodyScore)
                    optionalField("Waist–hip ratio", keyPath: \.waistHipRatio)
                    optionalField("Phase angle (°)", keyPath: \.phaseAngleDegrees)
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(GymTheme.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GymTheme.bg.ignoresSafeArea())
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GymTheme.label2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .fontWeight(.bold)
                        .foregroundStyle(activeAccent)
                        .disabled(isSaving)
                }
            }
        }
    }

    private var equipmentEditor: some View {
        List(Equipment.allCases, id: \.self) { item in
            Button {
                toggle(item.rawValue, in: &draft.availableEquipmentRaws)
            } label: {
                selectionRow(item.label, selected: draft.availableEquipmentRaws.contains(item.rawValue))
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Equipment")
    }

    private var limitationEditor: some View {
        List(MuscleGroup.allCases, id: \.self) { muscle in
            Button {
                toggle(muscle.rawValue, in: &draft.excludedMuscleRaws)
            } label: {
                selectionRow(muscle.label, selected: draft.excludedMuscleRaws.contains(muscle.rawValue))
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Areas to avoid")
    }

    private var splitStyleEditor: some View {
        List {
            Section {
                Button {
                    draft.splitTemplateName = "Auto"
                } label: {
                    selectionRow("Auto (recommended)", selected: draft.splitTemplateName == "Auto")
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Auto chooses a balanced split from your training days and experience.")
            }

            Section("Styles") {
                ForEach(SplitTemplateLibrary.all, id: \.name) { template in
                    Button {
                        draft.splitTemplateName = template.name
                    } label: {
                        selectionRow("\(template.name) · \(template.sessionCount) days",
                                     selected: draft.splitTemplateName == template.name)
                    }
                    .buttonStyle(.plain)
                    .disabled(template.sessionCount != draft.sessionsPerWeek)
                }
            }
            Section {
                Text("Styles are shown for reference, but only splits matching your sessions per week can be selected. Change that number in Training to see other styles.")
                    .font(.footnote)
                    .foregroundStyle(GymTheme.label2)
            }
        }
        .navigationTitle("Split style")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func selectionRow(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(GymTheme.label)
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(activeAccent)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .frame(minHeight: 44)
    }

    private func optionalField(_ label: String, keyPath: WritableKeyPath<AthleteProfileDraft, Double?>) -> some View {
        LabeledContent(label) {
            TextField("—", text: optionalNumberBinding(keyPath))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
        }
    }

    private func optionalNumberBinding(_ keyPath: WritableKeyPath<AthleteProfileDraft, Double?>) -> Binding<String> {
        Binding(
            get: {
                guard let value = draft[keyPath: keyPath] else { return "" }
                return value.formatted(.number.precision(.fractionLength(0...1)))
            },
            set: { text in
                let normalized = text.replacingOccurrences(of: ",", with: ".")
                draft[keyPath: keyPath] = normalized.isEmpty ? nil : Double(normalized)
            }
        )
    }

    private func toggle(_ rawValue: String, in values: inout [String]) {
        if let index = values.firstIndex(of: rawValue) { values.remove(at: index) }
        else { values.append(rawValue) }
    }

    private func save() {
        validationMessage = draft.validationError
        guard validationMessage == nil else { return }
        isSaving = true
        let planInputsChanged = draft.changesPlanInput(comparedTo: profile)
        do {
            try AthleteProfileStore.apply(draft, to: profile, in: context)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSaved(planInputsChanged)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            isSaving = false
        }
    }
}
