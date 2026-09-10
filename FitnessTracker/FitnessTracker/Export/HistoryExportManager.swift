import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import RuleEngine

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
        let fileURL = tempDir.appendingPathComponent("trainsage-workout-history-\(dateStamp()).csv")
        try? csv.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    @MainActor
    public static func exportFullJSON(context: ModelContext, catalog: CatalogStore) -> URL? {
        guard let data = exportFullJSONData(context: context, catalog: catalog) else { return nil }
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("trainsage-backup-\(dateStamp()).json")
        try? data.write(to: fileURL)
        return fileURL
    }

    /// The same full-history payload `exportFullJSON` writes to disk for the
    /// Settings "Export backup" feature, returned as in-memory `Data` instead
    /// — the shape `QueryTrainingDataTool` reads (design spec §4.4). One
    /// payload, two callers, so the two never drift apart.
    public static func exportFullJSONData(context: ModelContext, catalog: CatalogStore) -> Data? {
        let sessions = (try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? []
        let bws = (try? context.fetch(FetchDescriptor<BodyweightEntryModel>())) ?? []
        let prs = (try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? []
        let observations = (try? context.fetch(FetchDescriptor<ObservationModel>())) ?? []
        let checkins = (try? context.fetch(FetchDescriptor<DailyCheckinModel>())) ?? []

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
                "plannedSessionID": s.plannedSessionID?.uuidString as Any,
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
                "morningKg": b.morningKg as Any,
                "nightKg": b.nightKg as Any,
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

        // Observations: the generic {kind, value, unit, timestamp} channel —
        // where InBody-style body-composition metrics land once the AI
        // coach layer's `measurementCandidates` starts writing to it.
        var observationsList: [[String: Any]] = []
        for o in observations where o.confirmed {
            observationsList.append([
                "kind": o.kind,
                "value": o.value,
                "unit": o.unit,
                "timestamp": df.string(from: o.timestamp),
                "sessionId": o.sessionID?.uuidString as Any,
                "entryExerciseId": o.entryExerciseID as Any
            ])
        }

        // Daily subjective check-ins: sleep quality, soreness, free-text note.
        var checkinsList: [[String: Any]] = []
        for c in checkins {
            checkinsList.append([
                "date": df.string(from: c.date),
                "sleepQuality": c.sleepQuality as Any,
                "soreness": c.soreness as Any,
                "note": c.note as Any
            ])
        }

        func itemPayload(_ item: PlannedItem) -> [String: Any] {
            [
                "exerciseID": item.exerciseID,
                "targetSets": item.targetSets,
                "repMin": item.targetReps.min,
                "repMax": item.targetReps.max,
                "targetLoadKg": item.targetLoadKg as Any,
                "restSeconds": item.restSeconds,
                "coachNote": item.coachNote
            ]
        }

        var scheduleList: [[String: Any]] = []
        if let weekStart = WorkoutScheduleStore.calendar.dateInterval(of: .weekOfYear, for: .now)?.start {
            let plan = (try? context.fetch(FetchDescriptor<StoredPlan>(sortBy: [SortDescriptor(\.generatedAt, order: .reverse)])))?.first.flatMap { try? $0.decodedPlan() }
            for offset in 0..<7 {
                guard let date = WorkoutScheduleStore.calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
                let key = Scheduling.isoDateKey(date, calendar: WorkoutScheduleStore.calendar)
                var row: [String: Any] = [
                    "date": key,
                    "state": WorkoutScheduleStore.effectiveRoutineID(for: date) == nil ? "rest" : (WorkoutScheduleStore.isRescheduled(for: date) ? "rescheduled" : "scheduled")
                ]
                if let session = plan.flatMap({ WorkoutScheduleStore.effectiveSession(for: date, in: $0) }) {
                    row["plannedSessionID"] = session.id.uuidString
                    row["plannedItems"] = session.items.map(itemPayload)
                }
                scheduleList.append(row)
            }
        }

        // Every active date-scoped exercise-list edit, so a manual one-day
        // change is visible to QueryTrainingDataTool and prompt context.
        let workoutOverrides: [[String: Any]] = WorkoutScheduleStore.dayWorkoutOverrides
            .sorted { $0.key < $1.key }
            .map { _, o in
                [
                    "date": o.dateKey,
                    "baseSessionID": o.baseSessionID.uuidString,
                    "origin": o.origin.rawValue,
                    "updatedAt": df.string(from: o.updatedAt),
                    "items": o.items.map(itemPayload)
                ]
            }

        let fullBackup: [String: Any] = [
            "appName": "TrainSage",
            "version": 3,
            "exportedAt": df.string(from: Date()),
            "workouts": sessionsList,
            "bodyweight": bwList,
            "personalRecords": prList,
            "observations": observationsList,
            "dailyCheckins": checkinsList,
            "schedule": [
                "recurringWeek": Dictionary(uniqueKeysWithValues: WorkoutScheduleStore.weekSchedule.map { (String($0.key), $0.value.uuidString) }),
                "dateOverrides": WorkoutScheduleStore.dayPlan,
                "workoutOverrides": workoutOverrides,
                "currentWeek": scheduleList
            ]
        ]

        return try? JSONSerialization.data(withJSONObject: fullBackup, options: .prettyPrinted)
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
