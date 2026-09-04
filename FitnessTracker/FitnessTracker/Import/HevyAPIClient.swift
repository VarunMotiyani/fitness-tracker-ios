import Foundation
import FitnessDomain

public enum HevyAPIError: LocalizedError, Sendable {
    case emptyKey
    case unauthorized
    case rateLimited
    case httpError(Int)
    case decodingError

    public var errorDescription: String? {
        switch self {
        case .emptyKey: return "Hevy API key cannot be empty."
        case .unauthorized: return "Invalid API key or unauthorized access."
        case .rateLimited: return "Hevy API rate limit reached. Please try again in a few moments."
        case .httpError(let code): return "Hevy API error: HTTP \(code)"
        case .decodingError: return "Failed to parse data from Hevy."
        }
    }
}

public struct HevyImportProgress: Sendable {
    public let stage: String
    public let loaded: Int
    public let page: Int
    public let pageCount: Int
}

public final class HevyAPIClient: Sendable {
    private let baseURL = URL(string: "https://api.hevyapp.com")!

    public init() {}

    public func fetchAccount(
        apiKey: String,
        onProgress: (@Sendable (HevyImportProgress) -> Void)? = nil
    ) async throws -> (workouts: [ImportedWorkoutSession], bodyweights: [ImportedBodyweight]) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw HevyAPIError.emptyKey }

        // 1. Fetch Exercise Templates
        let templates = try await fetchPages(
            path: "/v1/exercise_templates",
            apiKey: key,
            resultKey: "exercise_templates",
            pageSize: 100,
            stage: "Exercise Templates",
            onProgress: onProgress
        )

        var templateIdToName: [String: String] = [:]
        for t in templates {
            if let id = t["id"] as? String, let title = t["title"] as? String {
                templateIdToName[id] = title
            }
        }

        // 2. Fetch Workouts
        let workoutDicts = try await fetchPages(
            path: "/v1/workouts",
            apiKey: key,
            resultKey: "workouts",
            pageSize: 10,
            stage: "Workouts",
            onProgress: onProgress
        )

        var importedSessions: [ImportedWorkoutSession] = []
        let isoFormatter = ISO8601DateFormatter()

        for w in workoutDicts {
            let title = (w["title"] as? String) ?? "Workout"
            let startTimeStr = (w["start_time"] as? String) ?? ""
            let parsedDate = isoFormatter.date(from: startTimeStr) ?? Date()
            let notes = w["description"] as? String

            var exerciseEntries: [ImportedExerciseEntry] = []
            if let exList = w["exercises"] as? [[String: Any]] {
                for ex in exList {
                    let templateId = (ex["exercise_template_id"] as? String) ?? ""
                    let exerciseName = templateIdToName[templateId] ?? (ex["title"] as? String) ?? "Exercise"

                    var sets: [ImportedSet] = []
                    if let rawSets = ex["sets"] as? [[String: Any]] {
                        for s in rawSets {
                            let weightKg = (s["weight_kg"] as? Double) ?? 0.0
                            let reps = (s["reps"] as? Int) ?? 0
                            let rpe = s["rpe"] as? Double
                            let rir = rpe != nil ? max(0, 10.0 - rpe!) : nil
                            let setType = (s["set_type"] as? String)?.lowercased() ?? "normal"
                            let isWarmup = setType.contains("warm")

                            sets.append(ImportedSet(
                                weightKg: weightKg,
                                reps: reps,
                                rir: rir,
                                rpe: rpe,
                                isWarmup: isWarmup
                            ))
                        }
                    }

                    if !sets.isEmpty {
                        exerciseEntries.append(ImportedExerciseEntry(exerciseName: exerciseName, sets: sets))
                    }
                }
            }

            importedSessions.append(ImportedWorkoutSession(
                title: title,
                date: parsedDate,
                durationSeconds: 3600,
                entries: exerciseEntries,
                notes: notes
            ))
        }

        // 3. Fetch Body Measurements
        var importedBodyweights: [ImportedBodyweight] = []
        do {
            let measurements = try await fetchPages(
                path: "/v1/body_measurements",
                apiKey: key,
                resultKey: "body_measurements",
                pageSize: 10,
                stage: "Body Measurements",
                onProgress: onProgress
            )
            for m in measurements {
                if let weightKg = m["weight_kg"] as? Double, let dateStr = m["created_at"] as? String {
                    let d = isoFormatter.date(from: dateStr) ?? Date()
                    importedBodyweights.append(ImportedBodyweight(date: d, weightKg: weightKg, source: "Hevy"))
                }
            }
        } catch {
            // Older accounts may not have measurements
        }

        return (importedSessions.sorted { $0.date < $1.date }, importedBodyweights.sorted { $0.date < $1.date })
    }

    private func fetchPages(
        path: String,
        apiKey: String,
        resultKey: String,
        pageSize: Int,
        stage: String,
        onProgress: (@Sendable (HevyImportProgress) -> Void)?
    ) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []
        var page = 1
        var pageCount = 1

        while page <= pageCount {
            var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "pageSize", value: "\(pageSize)")
            ]

            guard let url = components.url else { break }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HevyAPIError.httpError(0)
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw HevyAPIError.unauthorized
            }
            if httpResponse.statusCode == 429 {
                throw HevyAPIError.rateLimited
            }
            if httpResponse.statusCode != 200 {
                throw HevyAPIError.httpError(httpResponse.statusCode)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HevyAPIError.decodingError
            }

            pageCount = max(1, (json["page_count"] as? Int) ?? 1)
            let batch = (json[resultKey] as? [[String: Any]]) ?? []
            items.append(contentsOf: batch)

            onProgress?(HevyImportProgress(stage: stage, loaded: items.count, page: page, pageCount: pageCount))
            if batch.isEmpty { break }
            page += 1
        }

        return items
    }
}
