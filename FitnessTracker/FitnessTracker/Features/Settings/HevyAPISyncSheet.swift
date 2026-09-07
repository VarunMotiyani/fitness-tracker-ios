import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog

struct HevyAPISyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let catalog: CatalogStore

    @AppStorage("hevy_api_key") private var savedApiKey: String = ""
    @State private var apiKey: String = ""
    @State private var isSyncing: Bool = false
    @State private var progressMessage: String = ""
    @State private var progressPercent: Double = 0.0
    @State private var errorMessage: String? = nil
    @State private var successSummary: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Import your complete training history, exercise templates, custom routines, and body measurements directly from Hevy using a Developer API key.")
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.label2)

                    Link("Get your Hevy API key ↗", destination: URL(string: "https://hevy.com/settings?developer")!)
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.green)
                }

                Section("Hevy Developer API Key") {
                    SecureField("Paste API Key here", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if isSyncing {
                    Section("Syncing...") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(progressMessage.isEmpty ? "Connecting to Hevy API..." : progressMessage)
                                .font(.caption)
                                .foregroundStyle(GymTheme.label)
                            ProgressView(value: progressPercent, total: 1.0)
                                .tint(GymTheme.green)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.red)
                    }
                }

                if let success = successSummary {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(GymTheme.green)
                            Text(success)
                                .font(.subheadline)
                                .foregroundStyle(GymTheme.label)
                        }
                    }
                }

                Section {
                    Button {
                        startSync()
                    } label: {
                        HStack {
                            Spacer()
                            Text(isSyncing ? "Syncing..." : "Start Import")
                                .fontWeight(.bold)
                                .foregroundStyle(isSyncing ? GymTheme.label3 : .black)
                            Spacer()
                        }
                    }
                    .listRowBackground(isSyncing ? GymTheme.surface2 : GymTheme.green)
                    .disabled(isSyncing || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Import from Hevy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(GymTheme.label2)
                }
            }
            .onAppear {
                apiKey = savedApiKey
            }
        }
    }

    private func startSync() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        savedApiKey = key
        isSyncing = true
        errorMessage = nil
        successSummary = nil
        progressPercent = 0.05
        progressMessage = "Connecting to Hevy API..."

        Task {
            let client = HevyAPIClient()
            do {
                let (workouts, bodyweights) = try await client.fetchAccount(apiKey: key) { progress in
                    Task { @MainActor in
                        progressMessage = "Fetched \(progress.stage): \(progress.loaded) items (page \(progress.page)/\(progress.pageCount))"
                        let stageFactor: Double = progress.stage.contains("Template") ? 0.3 : progress.stage.contains("Workout") ? 0.7 : 0.9
                        progressPercent = stageFactor
                    }
                }

                await MainActor.run {
                    progressMessage = "Ingesting workouts into database..."
                    let (importedWorkouts, _) = HistoryIngestionService.ingestSessions(workouts, catalog: catalog, into: context)
                    let importedWeights = HistoryIngestionService.ingestBodyweights(bodyweights, into: context)

                    progressPercent = 1.0
                    isSyncing = false
                    successSummary = "Successfully imported \(importedWorkouts) workouts and \(importedWeights) weight entries!"
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
