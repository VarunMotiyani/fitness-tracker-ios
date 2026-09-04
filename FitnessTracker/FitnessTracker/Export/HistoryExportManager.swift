import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

public enum HistoryExportManager {
    @MainActor
    public static func exportCSV(context: ModelContext, catalog: CatalogStore) -> URL? {
        guard let sessions = try? context.fetch(FetchDescriptor<CompletedSessionModel>(sortBy: [SortDescriptor(\.startedAt, order: .forward)])) else {
            return nil
        }

        var csv = "Date,Workout Name,Exercise Name,Set Order,Weight (kg),Reps,RIR,RPE,Rest Time (sec),Warmup,Notes\n"
        let df = ISO8601DateFormatter()

        for s in sessions {
            let dateStr = df.string(from: s.startedAt)
            let workoutTitle = escapeCSV(s.overallNote ?? "Workout")

            for entry in s.entries.sorted(by: { $0.performedOrder < $1.performedOrder }) {
                let exName = escapeCSV(catalog.exercise(id: entry.exerciseID)?.name ?? entry.exerciseID)

                for (setIdx, set) in entry.sets.sorted(by: { $0.startedAt < $1.startedAt }).enumerated() {
                    let weightStr = String(format: "%.1f", set.actualLoadKg)
                    let repsStr = "\(set.actualReps)"
                    let rirStr = set.rir != nil ? String(format: "%.1f", set.rir!) : ""
                    let rpeStr = set.rpe != nil ? String(format: "%.1f", set.rpe!) : ""
                    let restStr = "\(set.restBeforeSec)"
                    let warmupStr = set.isWarmup ? "true" : "false"
                    let noteStr = escapeCSV(entry.note ?? "")

                    let row = "\(dateStr),\(workoutTitle),\(exName),\(setIdx + 1),\(weightStr),\(repsStr),\(rirStr),\(rpeStr),\(restStr),\(warmupStr),\(noteStr)\n"
                    csv.append(row)
                }
            }
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("pulseai-workout-history-\(dateStamp()).csv")
        try? csv.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    @MainActor
    public static func exportFullJSON(context: ModelContext, catalog: CatalogStore) -> URL? {
        let sessions = (try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? []
        let bws = (try? context.fetch(FetchDescriptor<BodyweightEntryModel>())) ?? []
        let prs = (try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? []

        var sessionsList: [[String: Any]] = []
        let df = ISO8601DateFormatter()

        for s in sessions {
            var entriesList: [[String: Any]] = []
            for e in s.entries.sorted(by: { $0.performedOrder < $1.performedOrder }) {
                let exName = catalog.exercise(id: e.exerciseID)?.name ?? e.exerciseID
                var setsList: [[String: Any]] = []
                for set in e.sets.sorted(by: { $0.startedAt < $1.startedAt }) {
                    setsList.append([
                        "weightKg": set.actualLoadKg,
                        "reps": set.actualReps,
                        "rir": set.rir as Any,
                        "rpe": set.rpe as Any,
                        "isWarmup": set.isWarmup,
                        "restBeforeSec": set.restBeforeSec
                    ])
                }
                entriesList.append([
                    "exerciseId": e.exerciseID,
                    "exerciseName": exName,
                    "performedOrder": e.performedOrder,
                    "note": e.note as Any,
                    "sets": setsList
                ])
            }

            sessionsList.append([
                "id": s.id.uuidString,
                "startedAt": df.string(from: s.startedAt),
                "finishedAt": s.finishedAt != nil ? df.string(from: s.finishedAt!) : "",
                "durationMin": s.actualDurationMin,
                "outcome": s.outcomeRaw ?? "completed",
                "notes": s.overallNote as Any,
                "entries": entriesList
            ])
        }

        var bwList: [[String: Any]] = []
        for b in bws {
            bwList.append([
                "weightKg": b.kg,
                "loggedAt": df.string(from: b.date)
            ])
        }

        var prList: [[String: Any]] = []
        for p in prs {
            prList.append([
                "exerciseId": p.exerciseID,
                "achievedAt": df.string(from: p.date),
                "weightKg": p.atLoadKg,
                "reps": p.reps,
                "kind": p.typeRaw
            ])
        }

        let fullBackup: [String: Any] = [
            "appName": "PulseAI",
            "version": 2,
            "exportedAt": df.string(from: Date()),
            "workouts": sessionsList,
            "bodyweight": bwList,
            "personalRecords": prList
        ]

        if let data = try? JSONSerialization.data(withJSONObject: fullBackup, options: .prettyPrinted) {
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("pulseai-backup-\(dateStamp()).json")
            try? data.write(to: fileURL)
            return fileURL
        }
        return nil
    }

    private static func escapeCSV(_ str: String) -> String {
        if str.contains(",") || str.contains("\"") || str.contains("\n") {
            let escaped = str.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return str
    }

    private static func dateStamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}
