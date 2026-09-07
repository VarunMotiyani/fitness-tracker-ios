import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

public struct DemoSeedGenerator {
    struct RoutineDef {
        let name: String
        let exercises: [(id: String, name: String, muscle: MuscleGroup, baseWeight: Double, sets: Int, reps: Int)]
    }

    public static func seedDemoHistory(into context: ModelContext, catalog: CatalogStore) {
        let cal = Calendar.isoUTC
        let now = Date()

        // 1. Seed Bodyweight Entries (12 weeks, trending from 82.4 kg to 78.3 kg)
        for i in 0..<24 {
            let daysAgo = Double((23 - i) * 3)
            let date = cal.date(byAdding: .day, value: -Int(daysAgo), to: now) ?? now
            let fraction = Double(i) / 23.0
            let weight = 82.4 - (fraction * 4.1) + Double.random(in: -0.2...0.2)
            let entry = BodyweightEntryModel(date: date, kg: (weight * 10).rounded() / 10)
            context.insert(entry)
        }

        // 2. Define Starter Routines (Push, Pull, Legs)
        let pushRoutine = RoutineDef(
            name: "Push Day",
            exercises: [
                (id: "0025", name: "Barbell Bench Press", muscle: .chest, baseWeight: 60.0, sets: 4, reps: 8),
                (id: "0047", name: "Incline Dumbbell Press", muscle: .chest, baseWeight: 45.0, sets: 3, reps: 10),
                (id: "0426", name: "Overhead Barbell Press", muscle: .shoulders, baseWeight: 40.0, sets: 4, reps: 8),
                (id: "0334", name: "Dumbbell Lateral Raise", muscle: .shoulders, baseWeight: 12.0, sets: 4, reps: 15),
                (id: "0241", name: "Cable Triceps Pushdown", muscle: .triceps, baseWeight: 25.0, sets: 3, reps: 12),
                (id: "0251", name: "Chest Dips", muscle: .chest, baseWeight: 0.0, sets: 3, reps: 10)
            ]
        )

        let pullRoutine = RoutineDef(
            name: "Pull Day",
            exercises: [
                (id: "2330", name: "Barbell Bent Over Row", muscle: .back, baseWeight: 50.0, sets: 4, reps: 8),
                (id: "0027", name: "Lat Pulldown", muscle: .back, baseWeight: 50.0, sets: 4, reps: 10),
                (id: "1323", name: "Face Pull", muscle: .traps, baseWeight: 25.0, sets: 4, reps: 15),
                (id: "0031", name: "Barbell Bicep Curl", muscle: .biceps, baseWeight: 30.0, sets: 3, reps: 10),
                (id: "0313", name: "Incline Dumbbell Curl", muscle: .biceps, baseWeight: 12.0, sets: 3, reps: 12)
            ]
        )

        let legsRoutine = RoutineDef(
            name: "Legs Day",
            exercises: [
                (id: "0043", name: "Barbell Back Squat", muscle: .quads, baseWeight: 80.0, sets: 4, reps: 8),
                (id: "0085", name: "Romanian Deadlift", muscle: .hamstrings, baseWeight: 75.0, sets: 4, reps: 8),
                (id: "0739", name: "Leg Press", muscle: .quads, baseWeight: 140.0, sets: 3, reps: 12),
                (id: "0585", name: "Leg Extension", muscle: .quads, baseWeight: 50.0, sets: 3, reps: 15),
                (id: "0586", name: "Lying Leg Curl", muscle: .hamstrings, baseWeight: 45.0, sets: 3, reps: 12),
                (id: "0605", name: "Standing Calf Raise", muscle: .calves, baseWeight: 60.0, sets: 4, reps: 15)
            ]
        )

        // 3. Seed 12 Weeks of Sessions (Mon, Wed, Fri)
        let totalWeeks = 12
        for week in 0..<totalWeeks {
            let weekProgression = Double(week) * 1.25

            // Monday: Push
            if let monDate = cal.date(byAdding: .day, value: -((totalWeeks - 1 - week) * 7 + 4), to: now) {
                let session = makeCompletedSession(routine: pushRoutine, date: monDate, weightDelta: weekProgression, week: week)
                context.insert(session)
            }

            // Wednesday: Pull
            if let wedDate = cal.date(byAdding: .day, value: -((totalWeeks - 1 - week) * 7 + 2), to: now) {
                let session = makeCompletedSession(routine: pullRoutine, date: wedDate, weightDelta: weekProgression, week: week)
                context.insert(session)
            }

            // Friday: Legs
            if week < totalWeeks - 1 || cal.component(.weekday, from: now) >= 6 {
                if let friDate = cal.date(byAdding: .day, value: -((totalWeeks - 1 - week) * 7), to: now) {
                    let session = makeCompletedSession(routine: legsRoutine, date: friDate, weightDelta: weekProgression, week: week)
                    context.insert(session)
                }
            }
        }

        // 4. Seed Personal Records
        context.insert(PersonalRecordModel(typeRaw: "weight", exerciseID: "0025", value: 85.0, atLoadKg: 85.0, reps: 8, date: now.addingTimeInterval(-2*86400), sessionID: UUID()))
        context.insert(PersonalRecordModel(typeRaw: "weight", exerciseID: "0043", value: 110.0, atLoadKg: 110.0, reps: 8, date: now.addingTimeInterval(-9*86400), sessionID: UUID()))
        context.insert(PersonalRecordModel(typeRaw: "weight", exerciseID: "2330", value: 75.0, atLoadKg: 75.0, reps: 8, date: now.addingTimeInterval(-5*86400), sessionID: UUID()))

        try? context.save()
    }

    private static func makeCompletedSession(
        routine: RoutineDef,
        date: Date,
        weightDelta: Double,
        week: Int
    ) -> CompletedSessionModel {
        let weekday = Calendar.isoUTC.component(.weekday, from: date)
        let session = CompletedSessionModel(
            startedAt: date,
            weekdayRaw: weekday,
            timeOfDayMinutes: 600,
            plannedDurationMin: 60,
            energyRaw: "normal",
            timeAvailableMin: 60,
            plannedSessionID: nil
        )
        session.finishedAt = date.addingTimeInterval(3300)
        session.actualDurationMin = 55
        session.overallNote = "Solid execution and progressive overload."

        for (order, ex) in routine.exercises.enumerated() {
            let entry = CompletedEntryModel(
                exerciseID: ex.id,
                performedOrder: order
            )
            entry.stateRaw = EntryState.done.rawValue

            let finalWeight = ex.baseWeight > 0 ? (ex.baseWeight + weightDelta) : 0
            for s in 0..<ex.sets {
                let rpe: Double = (week == 5) ? 6.0 : (s == ex.sets - 1 ? 9.0 : 8.0)
                let set = LoggedSetModel(
                    targetReps: ex.reps,
                    targetLoadKg: finalWeight,
                    actualReps: ex.reps,
                    actualLoadKg: finalWeight,
                    startedAt: date.addingTimeInterval(Double(s * 120)),
                    completedAt: date.addingTimeInterval(Double(s * 120 + 45)),
                    restBeforeSec: 90
                )
                set.rpe = rpe
                set.isWarmup = s == 0 && ex.baseWeight > 40
                entry.sets.append(set)
            }
            session.entries.append(entry)
        }

        return session
    }
}
