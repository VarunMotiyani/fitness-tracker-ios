import SwiftUI
import SwiftData

private extension AdapterKind {
    var label: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .gemini: "Gemini"
        case .appleOnDevice: "On-device (Apple)"
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
        kind == .openAICompatible || kind == .gemini
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
                if kind == .openAICompatible {
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }

            if showsAPIKeyField {
                Section {
                    SecureField(kind == .gemini ? "API key" : "API key (optional)", text: $apiKey)
                    if isEditing, profile?.apiKeyRef != nil {
                        Text("A key is already stored. Leave blank to keep it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

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

            if isEditing {
                Section {
                    Button("Set as active") { setActive() }
                        .disabled(profile?.isActive == true)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Provider" : "New Provider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let resolvedBaseURL = (kind == .openAICompatible && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
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
            context.insert(target)
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            let ref = target.apiKeyRef ?? UUID().uuidString
            try? KeychainStore.set(trimmedKey, account: ref)
            target.apiKeyRef = ref
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
