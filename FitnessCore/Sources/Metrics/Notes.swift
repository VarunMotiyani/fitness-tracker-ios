import Foundation

public enum Notes {
    public static let maxLength = 500

    public static func standing(exerciseID: String, exNotes: [String: String]) -> String? {
        guard let raw = exNotes[exerciseID] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func pinned(exerciseID: String, sessions: [CompletedSessionSnapshot]) -> (note: String, date: Date)? {
        let sorted = sessions.sorted { $0.date > $1.date }
        for s in sorted {
            if let entry = s.entries.first(where: { $0.exerciseID == exerciseID && $0.notePin }),
               let note = entry.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (note: note.trimmingCharacters(in: .whitespacesAndNewlines), date: s.date)
            }
        }
        return nil
    }

    public static func clamp(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxLength {
            return String(trimmed.prefix(maxLength))
        }
        return trimmed
    }
}
