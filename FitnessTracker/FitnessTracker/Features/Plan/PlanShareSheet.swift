import SwiftUI
import UniformTypeIdentifiers

public struct PlanShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let routines: [RoutineDraft]
    public let onImport: ([RoutineDraft]) -> Void

    @State private var showingImporter = false
    @State private var importError: String?

    public init(routines: [RoutineDraft], onImport: @escaping ([RoutineDraft]) -> Void) {
        self.routines = routines
        self.onImport = onImport
    }

    private var shareJSON: String {
        guard let data = try? JSONEncoder().encode(routines),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Export") {
                    ShareLink(item: shareJSON) {
                        Label("Share Plan as JSON", systemImage: "square.and.arrow.up")
                            .foregroundStyle(GymTheme.green)
                    }
                }

                Section("Import") {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Plan from File", systemImage: "square.and.arrow.down")
                            .foregroundStyle(GymTheme.sky)
                    }
                }

                if let importError {
                    Section {
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(GymTheme.red)
                    }
                }
            }
            .navigationTitle("Share & Backup Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first, url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let data = try Data(contentsOf: url)
                        let imported = try JSONDecoder().decode([RoutineDraft].self, from: data)
                        onImport(imported)
                        dismiss()
                    } catch {
                        importError = "Failed to parse plan file: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
        }
        .presentationDetents([.medium])
    }
}
