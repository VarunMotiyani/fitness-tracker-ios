import Foundation

public enum ImportSource: String, Sendable, Codable, CaseIterable {
    case hevy = "Hevy"
    case strong = "Strong"
    case fitNotesIOS = "FitNotes (iOS)"
    case fitNotesAndroid = "FitNotes (Android)"
    case generic = "CSV"
}

public struct ImportedSet: Sendable, Codable, Equatable {
    public var weightKg: Double
    public var reps: Int
    public var rir: Double?
    public var rpe: Double?
    public var isWarmup: Bool
    public var durationSec: Int?
    public var note: String?

    public init(
        weightKg: Double,
        reps: Int,
        rir: Double? = nil,
        rpe: Double? = nil,
        isWarmup: Bool = false,
        durationSec: Int? = nil,
        note: String? = nil
    ) {
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.durationSec = durationSec
        self.note = note
    }
}

public struct ImportedExerciseEntry: Sendable, Codable, Equatable {
    public var exerciseName: String
    public var category: String?
    public var sets: [ImportedSet]

    public init(exerciseName: String, category: String? = nil, sets: [ImportedSet] = []) {
        self.exerciseName = exerciseName
        self.category = category
        self.sets = sets
    }
}

public struct ImportedWorkoutSession: Sendable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var durationSeconds: Int
    public var entries: [ImportedExerciseEntry]
    public var notes: String?

    public init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        durationSeconds: Int = 3600,
        entries: [ImportedExerciseEntry] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.durationSeconds = durationSeconds
        self.entries = entries
        self.notes = notes
    }
}

public enum ExternalAppImporter: Sendable {
    private static let lbToKg: Double = 0.45359237

    public static func detectSource(header: [String]) -> ImportSource {
        let normalized = header.map { normalizeHeader($0) }
        if normalized.contains("exercise title") && (normalized.contains("set index") || normalized.contains("set type")) {
            return .hevy
        }
        if normalized.contains("exercise name") && (normalized.contains("set order") || normalized.contains("workout name")) {
            return .strong
        }
        if normalized.contains("exercise") && normalized.contains("kind") {
            return .fitNotesIOS
        }
        if normalized.contains("exercise") && (normalized.contains("weight unit") || normalized.contains("category")) {
            return .fitNotesAndroid
        }
        return .generic
    }

    private static func normalizeHeader(_ h: String) -> String {
        h.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    public static func importCSV(_ csvText: String) -> (source: ImportSource, sessions: [ImportedWorkoutSession]) {
        let rows = CSVParser.parse(csvText)
        guard rows.count > 1 else { return (.generic, []) }

        let header = rows[0]
        let source = detectSource(header: header)
        let colMap = mapColumns(header: header)

        var sessionMap: [String: (title: String, date: Date, duration: Int, notes: String?, entries: [ImportedExerciseEntry])] = [:]
        var sessionOrder: [String] = []

        for rowIdx in 1..<rows.count {
            let row = rows[rowIdx]
            guard row.count > 0 else { continue }

            let exerciseName = getField(row, colMap["exercise"])?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !exerciseName.isEmpty else { continue }

            let dateStr = getField(row, colMap["date"]) ?? getField(row, colMap["startTime"]) ?? ""
            let parsedDate = parseDate(dateStr) ?? Date()

            let workoutTitle = getField(row, colMap["workoutName"])?.trimmingCharacters(in: .whitespaces) ?? "Workout"
            let category = getField(row, colMap["category"])

            // Weight & Reps
            let weightVal = Double(getField(row, colMap["weight"]) ?? getField(row, colMap["weightKg"]) ?? "0") ?? 0.0
            let weightLbVal = Double(getField(row, colMap["weightLb"]) ?? "0") ?? 0.0
            let unitStr = getField(row, colMap["weightUnit"])?.lowercased() ?? ""

            var finalWeightKg = weightVal
            if weightLbVal > 0 || unitStr.contains("lb") {
                finalWeightKg = (weightLbVal > 0 ? weightLbVal : weightVal) * lbToKg
            }

            let repsVal = Int(Double(getField(row, colMap["reps"]) ?? "0") ?? 0)

            // RPE / RIR
            let rpeVal = Double(getField(row, colMap["rpe"]) ?? "")
            let rirVal = Double(getField(row, colMap["rir"]) ?? "")

            // Warmup
            let setType = getField(row, colMap["setType"])?.lowercased() ?? ""
            let kind = getField(row, colMap["kind"])?.lowercased() ?? ""
            let isWarmup = setType.contains("warm") || setType == "w" || kind.contains("warm")

            let note = getField(row, colMap["note"])
            let seconds = Int(Double(getField(row, colMap["seconds"]) ?? getField(row, colMap["time"]) ?? "0") ?? 0)

            let importedSet = ImportedSet(
                weightKg: finalWeightKg,
                reps: repsVal,
                rir: rirVal,
                rpe: rpeVal,
                isWarmup: isWarmup,
                durationSec: seconds > 0 ? seconds : nil,
                note: note
            )

            // Session Key (group by day + workout title)
            let sessionKey = "\(ISO8601DateFormatter().string(from: parsedDate).prefix(10))_\(workoutTitle)"

            if sessionMap[sessionKey] == nil {
                sessionMap[sessionKey] = (title: workoutTitle, date: parsedDate, duration: 3600, notes: note, entries: [])
                sessionOrder.append(sessionKey)
            }

            guard var session = sessionMap[sessionKey] else { continue }

            if let lastEntryIdx = session.entries.indices.last, session.entries[lastEntryIdx].exerciseName.lowercased() == exerciseName.lowercased() {
                session.entries[lastEntryIdx].sets.append(importedSet)
            } else {
                let newEntry = ImportedExerciseEntry(exerciseName: exerciseName, category: category, sets: [importedSet])
                session.entries.append(newEntry)
            }
            sessionMap[sessionKey] = session
        }

        var results: [ImportedWorkoutSession] = []
        for key in sessionOrder {
            if let s = sessionMap[key], !s.entries.isEmpty {
                results.append(ImportedWorkoutSession(
                    title: s.title,
                    date: s.date,
                    durationSeconds: s.duration,
                    entries: s.entries,
                    notes: s.notes
                ))
            }
        }

        // Sort chronologically ascending
        results.sort { $0.date < $1.date }
        return (source, results)
    }

    private static func mapColumns(header: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        let patterns: [(String, [String])] = [
            ("exercise", ["exercise", "exercise name", "exercise title"]),
            ("date", ["date", "workout date"]),
            ("startTime", ["start time", "start date"]),
            ("endTime", ["end time"]),
            ("workoutName", ["workout name", "title", "workout"]),
            ("category", ["category", "body part", "muscle group"]),
            ("weightKg", ["weight kg"]),
            ("weightLb", ["weight lbs", "weight lb"]),
            ("weight", ["weight"]),
            ("weightUnit", ["weight unit", "unit"]),
            ("reps", ["reps", "repetitions"]),
            ("rpe", ["rpe", "rpe rating"]),
            ("rir", ["rir", "reps in reserve"]),
            ("distanceKm", ["distance km"]),
            ("distance", ["distance"]),
            ("seconds", ["seconds", "duration seconds", "set duration sec"]),
            ("time", ["time", "duration"]),
            ("setType", ["set type"]),
            ("kind", ["kind"]),
            ("note", ["comment", "comments", "notes", "note", "workout notes"])
        ]

        for (idx, col) in header.enumerated() {
            let norm = normalizeHeader(col)
            for (field, aliases) in patterns {
                if map[field] == nil && aliases.contains(norm) {
                    map[field] = idx
                    break
                }
            }
        }
        return map
    }

    private static func getField(_ row: [String], _ colIdx: Int?) -> String? {
        guard let idx = colIdx, idx >= 0 && idx < row.count else { return nil }
        let val = row[idx].trimmingCharacters(in: .whitespacesAndNewlines)
        return val.isEmpty ? nil : val
    }

    private static func parseDate(_ str: String) -> Date? {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd",
            "MM/dd/yyyy HH:mm",
            "MM/dd/yyyy",
            "dd/MM/yyyy HH:mm",
            "dd/MM/yyyy"
        ]
        for f in formats {
            let df = DateFormatter()
            df.dateFormat = f
            df.locale = Locale(identifier: "en_US_POSIX")
            if let d = df.date(from: str) {
                return d
            }
        }
        return nil
    }
}
