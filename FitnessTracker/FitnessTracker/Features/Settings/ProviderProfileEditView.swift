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
    @State private var openRouterModels: [OpenRouterProvider.Model] = []
    @State private var showingOpenRouterModelPicker = false
    @State private var fallbackProfileID: UUID?
    @State private var toolCallingOverride: ProviderCapabilities.ToolCalling?

    init(profile: ProviderProfile?) {
        self.profile = profile
        _displayName = State(initialValue: profile?.displayName ?? "")
        _kind = State(initialValue: profile?.adapterKind ?? .openAICompatible)
        _modelID = State(initialValue: profile?.modelID ?? "")
        _baseURL = State(initialValue: profile?.baseURL ?? "")
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

    private var showsBaseURLField: Bool {
        kind == .openAICompatible || kind == .vertexAI || kind == .bedrock
    }

    private var baseURLFieldLabel: String {
        kind == .bedrock ? "Region (e.g. us-east-1)" : "Base URL"
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
                if showsBaseURLField {
                    TextField(baseURLFieldLabel, text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(kind == .bedrock ? .default : .URL)
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let resolvedBaseURL = (showsBaseURLField && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
            ? baseURL.trimmingCharacters(in: .whitespaces)
            : nil

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
        try? context.save()
        dismiss()
    }

    private func setActive() {
        guard let profile else { return }
        for other in allProfiles where other.isActive {
            other.isActive = false
        }
        profile.isActive = true
        try? context.save()
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
                        Text("Context \(model.contextLength.map(String.init) ?? "unknown") · $\(model.promptPrice, format: .number.precision(.fractionLength(0...8)))/$1M in")
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
