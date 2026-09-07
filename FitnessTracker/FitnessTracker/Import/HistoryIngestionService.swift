import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

public final class HistoryIngestionService {
    private let modelContext: ModelContext
    private let catalog: CatalogStore

    public init(modelContext: ModelContext, catalog: CatalogStore) {
        self.modelContext = modelContext
        self.catalog = catalog
    }

    @MainActor
    public func ingest(
        sessions: [ImportedWorkoutSession],
        bodyweights: [ImportedBodyweight]
    ) throws -> (sessions: Int, bodyweights: Int) {
        let (sessionCount, _) = Self.ingestSessions(sessions, catalog: catalog, into: modelContext)
        let bwCount = Self.ingestBodyweights(bodyweights, into: modelContext)
        return (sessions: sessionCount, bodyweights: bwCount)
    }

    @MainActor
    public static func ingestSessions(
        _ sessions: [ImportedWorkoutSession],
        catalog: CatalogStore,
        into context: ModelContext
    ) -> (importedCount: Int, skippedCount: Int) {
        var imported = 0
        var skipped = 0

        let cal = Calendar.current

        for s in sessions {
            guard !s.entries.isEmpty else {
                skipped += 1
                continue
            }

            let weekday = cal.component(.weekday, from: s.date)
            let hour = cal.component(.hour, from: s.date)
            let minute = cal.component(.minute, from: s.date)
            let timeOfDayMin = hour * 60 + minute

            let sessionModel = CompletedSessionModel(
                id: s.id,
                startedAt: s.date,
                weekdayRaw: weekday,
                timeOfDayMinutes: timeOfDayMin,
                plannedDurationMin: s.durationSeconds / 60,
                energyRaw: "normal",
                timeAvailableMin: s.durationSeconds / 60,
                plannedSessionID: nil
            )
            sessionModel.finishedAt = s.date.addingTimeInterval(Double(s.durationSeconds))
            sessionModel.actualDurationMin = s.durationSeconds / 60
            sessionModel.outcomeRaw = SessionOutcome.complete.rawValue
            sessionModel.overallNote = s.notes

            context.insert(sessionModel)

            for (entryOrder, entry) in s.entries.enumerated() {
                // Find matching exercise in catalog
                let matchedEx = catalog.all.first {
                    $0.name.localizedCaseInsensitiveContains(entry.exerciseName)
                }
                let exerciseID = matchedEx?.id ?? sanitizeID(entry.exerciseName)

                let entryModel = CompletedEntryModel(exerciseID: exerciseID, performedOrder: entryOrder)
                entryModel.stateRaw = EntryState.done.rawValue
                entryModel.session = sessionModel

                context.insert(entryModel)
                sessionModel.entries.append(entryModel)

                for set in entry.sets {
                    let setStart = s.date
                    let setEnd = s.date.addingTimeInterval(45)

                    let setModel = LoggedSetModel(
                        targetReps: set.reps,
                        targetLoadKg: set.weightKg,
                        actualReps: set.reps,
                        actualLoadKg: set.weightKg,
                        startedAt: setStart,
                        completedAt: setEnd,
                        restBeforeSec: 90,
                        rpe: set.rpe,
                        rir: set.rir ?? (set.rpe != nil ? max(0, 10.0 - set.rpe!) : nil),
                        heldSec: set.durationSec,
                        isWarmup: set.isWarmup
                    )
                    setModel.entry = entryModel
                    context.insert(setModel)
                    entryModel.sets.append(setModel)
                }
            }

            imported += 1
        }

        try? context.save()
        return (importedCount: imported, skippedCount: skipped)
    }

    @MainActor
    public static func ingestBodyweights(
        _ bodyweights: [ImportedBodyweight],
        into context: ModelContext
    ) -> Int {
        var count = 0
        for b in bodyweights {
            let model = BodyweightEntryModel(date: b.date, kg: b.weightKg)
            context.insert(model)
            count += 1
        }
        try? context.save()
        return count
    }

    private static func sanitizeID(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }
}
