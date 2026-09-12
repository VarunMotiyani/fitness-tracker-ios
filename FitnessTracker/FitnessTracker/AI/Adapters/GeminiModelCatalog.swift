import Foundation

/// Supported low-latency Gemini Flash choices for the native Generate Content
/// adapter. Thinking is controlled independently with `thinkingLevel: low`.
enum GeminiModelCatalog {
    struct Option: Identifiable {
        let id: String
        let name: String
    }

    static let defaultModelID = "gemini-3.8-flash"
    static let options: [Option] = [
        Option(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash · low thinking"),
        Option(id: "gemini-3.7-flash", name: "Gemini 3.7 Flash · low thinking"),
    ]

    static func isSupported(_ modelID: String) -> Bool {
        options.contains { $0.id == modelID }
    }
}
