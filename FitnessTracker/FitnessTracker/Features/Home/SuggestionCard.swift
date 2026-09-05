import SwiftUI
import SwiftData
import ExerciseCatalog

/// One AI-derived `PendingCoachSuggestion` awaiting your review (design spec
/// §3/§4) — proposed by Ask Coach or the coverage-gap detector. Accept applies
/// the mutation to the target `PlannedSession` via `SuggestionApplier`; Skip
/// marks it resolved without touching the plan. `resolvedAt == nil` means
/// still pending, matching `PendingObservationCard`'s confirmed/dismissed shape.
struct SuggestionCard: View {
    let suggestion: PendingCoachSuggestion
    let catalog: CatalogStore
    let onAccept: () -> Void
    let onSkip: () -> Void

    private var exerciseName: String {
        catalog.exercise(id: suggestion.exerciseID)?.name ?? suggestion.exerciseID
    }

    private var summary: String {
        switch suggestion.kind {
        case "exerciseSwap":
            let replacementName = suggestion.replacementExerciseID
                .flatMap { catalog.exercise(id: $0)?.name } ?? suggestion.replacementExerciseID ?? "?"
            return "Swap \(exerciseName) → \(replacementName)"
        case "addExercise":
            let repsSuffix: String
            if let min = suggestion.targetRepsMin, let max = suggestion.targetRepsMax {
                repsSuffix = ", \(min)-\(max) reps"
            } else {
                repsSuffix = ""
            }
            let setsSuffix = suggestion.targetSets.map { ", \($0) sets" } ?? ""
            return "Add \(exerciseName)\(setsSuffix)\(repsSuffix)"
        case "setChange":
            var parts: [String] = []
            if let sets = suggestion.targetSets { parts.append("\(sets) sets") }
            if suggestion.targetRepsMin != nil || suggestion.targetRepsMax != nil {
                parts.append("\(suggestion.targetRepsMin ?? 0)-\(suggestion.targetRepsMax ?? 0) reps")
            }
            if let load = suggestion.targetLoadKg { parts.append("\(Int(load))kg") }
            return "Adjust \(exerciseName): " + parts.joined(separator: ", ")
        default:
            return "Adjust \(exerciseName)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COACH SUGGESTS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(GymTheme.label3)

            Text(summary)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GymTheme.label)

            Text(suggestion.rationale)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(GymTheme.label2)

            HStack(spacing: 12) {
                Button {
                    onAccept()
                } label: {
                    Text("Accept")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(GymTheme.lime, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onSkip()
                } label: {
                    Text("Skip")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GymTheme.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(GymTheme.red.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
