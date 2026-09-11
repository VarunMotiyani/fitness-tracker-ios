import SwiftUI
import SwiftData
import LLMKit

extension AdapterKind {
    var label: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .openRouter: "OpenRouter"
        case .gemini: "Gemini"
        case .appleOnDevice: "On-device (Apple)"
        case .vertexAI: "Vertex AI (GCP)"
        case .bedrock: "Bedrock (AWS)"
        }
    }
}

enum ProviderProfileEditLayoutMetrics {
    static let persistentBottomBarClearance = 80
}

/// Well-known OpenAI-compatible hosts, so picking one fills in the base URL
/// instead of asking the user to know/paste it. `.custom` keeps the old
/// free-text field for any endpoint not in this short list (self-hosted
/// vLLM/Ollama on a non-default port, an internal proxy, etc.).
enum KnownOpenAICompatibleHost: String, CaseIterable, Identifiable {
    case openAI, groq, together, deepSeek, fireworks, mistral, ollamaLocal, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI: "OpenAI"
        case .groq: "Groq"
        case .together: "Together AI"
        case .deepSeek: "DeepSeek"
        case .fireworks: "Fireworks AI"
        case .mistral: "Mistral"
        case .ollamaLocal: "Ollama (local)"
        case .custom: "Custom"
        }
    }

    /// nil for `.custom` — that case keeps whatever the user typed.
    var baseURL: String? {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .together: "https://api.together.xyz/v1"
        case .deepSeek: "https://api.deepseek.com/v1"
        case .fireworks: "https://api.fireworks.ai/inference/v1"
        case .mistral: "https://api.mistral.ai/v1"
        case .ollamaLocal: "http://localhost:11434/v1"
        case .custom: nil
        }
    }

    static func matching(baseURL: String?) -> KnownOpenAICompatibleHost {
        guard let baseURL, !baseURL.isEmpty else { return .openAI }
        return allCases.first { $0.baseURL == baseURL } ?? .custom
    }
}

/// Vertex AI's `baseURL` is `.../projects/<project>/locations/<location>/publishers/google/models/`.
/// Asking for the two short values that actually vary, rather than the full
/// URL, matches every other adapter's "model + key only" shape.
enum VertexAIURL {
    static func build(project: String, location: String) -> String? {
        let project = project.trimmingCharacters(in: .whitespaces)
        let location = location.trimmingCharacters(in: .whitespaces)
        guard !project.isEmpty, !location.isEmpty else { return nil }
        return "https://\(location)-aiplatform.googleapis.com/v1/projects/\(project)/locations/\(location)/publishers/google/models/"
    }

    /// Best-effort reverse parse for pre-filling an existing profile's fields.
    static func parse(_ baseURL: String?) -> (project: String, location: String) {
        guard let baseURL,
              let projectsRange = baseURL.range(of: "/projects/"),
              let locationsRange = baseURL.range(of: "/locations/", range: projectsRange.upperBound..<baseURL.endIndex)
        else { return ("", "us-central1") }
        let project = String(baseURL[projectsRange.upperBound..<locationsRange.lowerBound])
        let afterLocations = baseURL[locationsRange.upperBound...]
        let location = afterLocations.prefix { $0 != "/" }
        return (project, location.isEmpty ? "us-central1" : String(location))
    }
}

/// Create (`profile == nil`) or edit a single ``ProviderProfile``.
struct ProviderProfileEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allProfiles: [ProviderProfile]

    let profile: ProviderProfile?

    @State private var displayName: String
    @State private var kind: AdapterKind
    @State private var modelID: String
    @State private var baseURL: String
    @State private var apiKey: String = ""
    @State private var supportsVision: Bool
    @State private var priceIn: Double
    @State private var priceOut: Double
    @State private var priceCached: Double
    @State private var keychainError: String?
    @State private var saveError: String?
    @State private var openRouterModels: [OpenRouterProvider.Model] = []
    @State private var showingOpenRouterModelPicker = false
    @State private var fallbackProfileID: UUID?
    @State private var toolCallingOverride: ProviderCapabilities.ToolCalling?
    @State private var hostPreset: KnownOpenAICompatibleHost
    @State private var gcpProjectID: String
    @State private var gcpLocation: String

    init(profile: ProviderProfile?) {
        self.profile = profile
        _displayName = State(initialValue: profile?.displayName ?? "")
        let kind = profile?.adapterKind ?? .openAICompatible
        _kind = State(initialValue: kind)
        _modelID = State(initialValue: profile?.modelID ?? "")
        let preset = kind == .openAICompatible ? KnownOpenAICompatibleHost.matching(baseURL: profile?.baseURL) : .openAI
        _hostPreset = State(initialValue: preset)
        _baseURL = State(initialValue: profile?.baseURL ?? preset.baseURL ?? "")
        let vertex = VertexAIURL.parse(profile?.baseURL)
        _gcpProjectID = State(initialValue: vertex.project)
        _gcpLocation = State(initialValue: vertex.location)
        _supportsVision = State(initialValue: profile?.supportsVision ?? false)
        _priceIn = State(initialValue: profile?.pricePerMTokIn ?? 0)
        _priceOut = State(initialValue: profile?.pricePerMTokOut ?? 0)
        _priceCached = State(initialValue: profile?.pricePerMTokCached ?? 0)
        _fallbackProfileID = State(initialValue: profile?.fallbackProfileID)
        _toolCallingOverride = State(initialValue: profile?.capToolCallingRaw
            .flatMap(ProviderCapabilities.ToolCalling.init(rawValue:)))
    }

    private var isEditing: Bool { profile != nil }

    private var showsAPIKeyField: Bool {
        kind != .appleOnDevice
    }

    private var showsModelIDField: Bool {
        kind != .appleOnDevice
    }

    private var baseURLFieldLabel: String {
        "Region (e.g. us-east-1)"
    }

    private var apiKeyFieldLabel: String {
        switch kind {
        case .gemini, .vertexAI: "API key"
        case .bedrock: "Credentials JSON"
        default: "API key (optional)"
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Display name", text: $displayName)
                Picker("Adapter", selection: $kind) {
                    ForEach(AdapterKind.allCases, id: \.self) { k in
                        Text(k.label).tag(k)
                    }
                }
                if kind == .openRouter {
                    Button {
                        showingOpenRouterModelPicker = true
                    } label: {
                        LabeledContent("Model") {
                            Text(openRouterModels.first(where: { $0.id == modelID })?.name ?? modelID)
                                .foregroundStyle(modelID.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                        }
                    }
                    if openRouterModels.isEmpty {
                        TextField("Model ID (offline fallback)", text: $modelID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else if !modelID.isEmpty {
                        Text("\(openRouterModels.first(where: { $0.id == modelID })?.contextLength.map(String.init) ?? "unknown") token context")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if showsModelIDField {
                    TextField("Model ID", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    LabeledContent("Model") {
                        Text("Apple system model")
                            .foregroundStyle(.secondary)
                    }
                }
                if kind == .openAICompatible {
                    Picker("Host", selection: $hostPreset) {
                        ForEach(KnownOpenAICompatibleHost.allCases) { host in
                            Text(host.label).tag(host)
                        }
                    }
                    if hostPreset == .custom {
                        TextField("Base URL", text: $baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                } else if kind == .vertexAI {
                    TextField("GCP Project ID", text: $gcpProjectID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Location (e.g. us-central1)", text: $gcpLocation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else if kind == .bedrock {
                    TextField(baseURLFieldLabel, text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            if showsAPIKeyField {
                Section {
                    SecureField(apiKeyFieldLabel, text: $apiKey)
                    if isEditing, profile?.apiKeyRef != nil {
                        Text("A key is already stored. Leave blank to keep it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if kind == .bedrock {
                        Text("{\"accessKeyId\":\"...\",\"secretAccessKey\":\"...\",\"sessionToken\":\"...\"} — sessionToken optional.")
                    } else if kind == .vertexAI {
                        Text("A short-lived OAuth2 access token (e.g. from `gcloud auth print-access-token`) — expires roughly hourly and needs re-pasting here when it does.")
                    }
                }
            }

            if kind != .appleOnDevice {
                Section("Pricing (USD per 1M tokens)") {
                    LabeledContent("Input") {
                        TextField("Input", value: $priceIn, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    LabeledContent("Output") {
                        TextField("Output", value: $priceOut, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    LabeledContent("Cached") {
                        TextField("Cached", value: $priceCached, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    Toggle("Supports vision", isOn: $supportsVision)
                }

                let others = allProfiles.filter { $0.id != profile?.id }
                if !others.isEmpty {
                    Section {
                        Picker("Fallback provider", selection: $fallbackProfileID) {
                            Text("None").tag(UUID?.none)
                            ForEach(others) { p in
                                Text(p.displayName).tag(UUID?.some(p.id))
                            }
                        }
                    } footer: {
                        Text("Used automatically when this provider fails after retries — e.g. an on-device profile when the network is down.")
                    }
                }

                Section {
                    Picker("Tool calling", selection: $toolCallingOverride) {
                        Text("Auto").tag(ProviderCapabilities.ToolCalling?.none)
                        Text("Native (function calling)").tag(ProviderCapabilities.ToolCalling?.some(.native))
                        Text("Prompt loop").tag(ProviderCapabilities.ToolCalling?.some(.viaPrompt))
                    }
                } footer: {
                    Text("Auto uses the adapter default. Set Native for a model that supports function calling (most OpenAI/Anthropic/Gemini models on OpenRouter); Prompt loop for smaller models.")
                }
            }

            if isEditing {
                Section {
                    Button("Set as active") { setActive() }
                        .disabled(profile?.isActive == true)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Provider" : "New Provider")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: kind) {
            guard kind == .openRouter else {
                openRouterModels = []
                return
            }
            do {
                openRouterModels = try await OpenRouterProvider.fetchModels()
            } catch {
                // The picker remains usable with the offline free-text field.
                openRouterModels = []
            }
        }
        .sheet(isPresented: $showingOpenRouterModelPicker) {
            OpenRouterModelPicker(models: openRouterModels, selection: $modelID)
        }
        .onChange(of: hostPreset) {
            if let url = hostPreset.baseURL { baseURL = url }
        }
        .onChange(of: modelID) {
            // OpenRouter's /models already reports live per-token pricing;
            // pre-fill Input/Output from it so users aren't retyping numbers
            // that are sitting right there in the picker. Still a plain
            // @State field afterward — free to override.
            guard kind == .openRouter, let model = openRouterModels.first(where: { $0.id == modelID }) else { return }
            priceIn = model.promptPrice * 1_000_000
            priceOut = model.completionPrice * 1_000_000
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: CGFloat(ProviderProfileEditLayoutMetrics.persistentBottomBarClearance))
        }
        .alert("Couldn't save the API key", isPresented: Binding(
            get: { keychainError != nil },
            set: { if !$0 { keychainError = nil } })) {
            Button("OK", role: .cancel) { keychainError = nil }
        } message: {
            Text(keychainError ?? "")
        }
        .alert("Couldn't save provider", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let resolvedBaseURL: String?
        switch kind {
        case .vertexAI:
            resolvedBaseURL = VertexAIURL.build(project: gcpProjectID, location: gcpLocation)
        case .openAICompatible, .bedrock:
            let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
            resolvedBaseURL = trimmed.isEmpty ? nil : trimmed
        case .openRouter, .gemini, .appleOnDevice:
            resolvedBaseURL = nil
        }

        let target: ProviderProfile
        if let profile {
            target = profile
            target.displayName = displayName
            target.adapterKindRaw = kind.rawValue
            target.modelID = kind == .appleOnDevice ? "system" : modelID
            target.baseURL = resolvedBaseURL
            target.supportsVision = supportsVision
            target.pricePerMTokIn = priceIn
            target.pricePerMTokOut = priceOut
            target.pricePerMTokCached = priceCached
        } else {
            target = ProviderProfile(
                displayName: displayName,
                adapterKind: kind,
                baseURL: resolvedBaseURL,
                modelID: modelID,
                apiKeyRef: nil,
                supportsVision: supportsVision,
                pricePerMTokIn: priceIn,
                pricePerMTokOut: priceOut,
                pricePerMTokCached: priceCached)
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            let ref = target.apiKeyRef ?? UUID().uuidString
            do {
                try KeychainStore.set(trimmedKey, account: ref)
                target.apiKeyRef = ref
            } catch {
                keychainError = "The key could not be written to the Keychain. Try again."
                return
            }
        }

        target.fallbackProfileID = fallbackProfileID
        target.capToolCallingRaw = toolCallingOverride?.rawValue

        // Insert only after the key write has succeeded, so a failed write
        // can't leave a key-less new profile behind via SwiftData autosave.
        if profile == nil {
            context.insert(target)
        }
        do {
            try context.save()
            dismiss()
        } catch {
            saveError = "Could not save provider: \(error.localizedDescription)"
        }
    }

    private func setActive() {
        guard let profile else { return }
        for other in allProfiles where other.isActive {
            other.isActive = false
        }
        profile.isActive = true
        _ = PersistenceReporter.attemptSave(context, operation: "activate provider")
    }
}

private struct OpenRouterModelPicker: View {
    @Environment(\.dismiss) private var dismiss
    let models: [OpenRouterProvider.Model]
    @Binding var selection: String
    @State private var searchText = ""

    private var filteredModels: [OpenRouterProvider.Model] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return models }
        return models.filter { $0.id.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filteredModels) { model in
                Button {
                    selection = model.id
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name)
                            .foregroundStyle(.primary)
                        Text(model.id)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Context \(model.contextLength.map(String.init) ?? "unknown") · $\(model.promptPrice * 1_000_000, format: .number.precision(.fractionLength(0...4)))/1M in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search OpenRouter models")
            .navigationTitle("Choose model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
