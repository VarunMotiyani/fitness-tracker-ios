import SwiftUI
import SwiftData

extension AdapterKind {
    var label: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .gemini: "Gemini"
        case .appleOnDevice: "On-device (Apple)"
        case .vertexAI: "Vertex AI (GCP)"
        case .bedrock: "Bedrock (AWS)"
        }
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
    }

    private var isEditing: Bool { profile != nil }

    private var showsAPIKeyField: Bool {
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
                TextField("Model ID", text: $modelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
            target.modelID = modelID
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
