import SwiftUI
import SwiftData

/// Lists every configured ``ProviderProfile`` for the AI coach.
struct ProviderProfileListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ProviderProfile.createdAt) private var profiles: [ProviderProfile]

    var body: some View {
        List {
            if profiles.isEmpty {
                ContentUnavailableView(
                    "No Providers",
                    systemImage: "cpu",
                    description: Text("Without a provider the rule engine is used. Add one to enable the AI coach."))
            }

            ForEach(profiles) { profile in
                NavigationLink {
                    ProviderProfileEditView(profile: profile)
                } label: {
                    row(profile)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Providers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    ProviderProfileEditView(profile: nil)
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Add on-device (free)", action: addOnDevice)
            }
        }
    }

    private func row(_ profile: ProviderProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                Text(profile.adapterKind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if profile.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Active")
            }
        }
    }

    private func addOnDevice() {
        let profile = ProviderProfile(
            displayName: "On-device (Apple)",
            adapterKind: .appleOnDevice,
            baseURL: nil,
            modelID: "system",
            apiKeyRef: nil,
            supportsVision: false,
            pricePerMTokIn: 0,
            pricePerMTokOut: 0,
            pricePerMTokCached: 0)
        context.insert(profile)
        try? context.save()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let profile = profiles[index]
            if let ref = profile.apiKeyRef {
                try? KeychainStore.delete(account: ref)
            }
            context.delete(profile)
        }
        try? context.save()
    }
}
