import SwiftUI
import FitnessDomain
import ExerciseCatalog
import Metrics

/// First screen of the session runner: pick today's energy and how much time
/// you have, then kick off `SessionRunner.start` via `onStart`.
struct SessionStartView: View {
    let planned: PlannedSession
    let catalog: CatalogStore
    let onStart: (EnergyRating, Int) -> Void

    /// Defaults to `.normal`; the selected value is passed straight to `onStart`.
    @State private var energy: EnergyRating = .normal
    /// Defaults to 60 min (a middle-of-the-road session), independent of the
    /// estimate shown in the header.
    @State private var minutes: Int = 60
    @State private var showsCustomTime = false

    private let timeChips = [45, 60, 90]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                energySection
                timeSection
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onStart(energy, minutes)
            } label: {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .navigationTitle("Session \(planned.order + 1)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session \(planned.order + 1)")
                .font(.largeTitle.bold())
            if !planned.focusMuscles.isEmpty {
                Text(planned.focusMuscles.map(\.label).joined(separator: ", "))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text("\(planned.items.count) exercises  ·  ~\(estimatedMinutes) min")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Energy

    private var energySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How's your energy?")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(EnergyRating.allCases, id: \.self) { rating in
                    energyButton(rating)
                }
            }
        }
    }

    private func energyButton(_ rating: EnergyRating) -> some View {
        let selected = energy == rating
        return Button {
            energy = rating
        } label: {
            VStack(spacing: 8) {
                Text(energyEmoji(rating))
                    .font(.largeTitle)
                Text(energyLabel(rating))
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func energyEmoji(_ rating: EnergyRating) -> String {
        switch rating {
        case .beat:   "😮‍💨"
        case .normal: "🙂"
        case .great:  "🔥"
        }
    }

    private func energyLabel(_ rating: EnergyRating) -> String {
        switch rating {
        case .beat:   "Beat"
        case .normal: "Normal"
        case .great:  "Great"
        }
    }

    // MARK: - Time

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time available")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(timeChips, id: \.self) { value in
                    timeChip(title: "\(value)", selected: !showsCustomTime && minutes == value) {
                        showsCustomTime = false
                        minutes = value
                    }
                }
                timeChip(title: "Custom", selected: showsCustomTime) {
                    showsCustomTime = true
                }
            }
            if showsCustomTime {
                Stepper("\(minutes) min", value: $minutes, in: 30...150, step: 5)
                    .padding(.top, 4)
            }
        }
    }

    private func timeChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                )
                .overlay(
                    Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Estimate

    /// Same formula the finalizer uses: 40s work + rest per set, summed, to minutes.
    private var estimatedMinutes: Int {
        let seconds = planned.items.reduce(0.0) { $0 + Double($1.targetSets) * (40 + Double($1.restSeconds)) }
        return Int((seconds / 60).rounded())
    }
}

#Preview {
    let planned = PlannedSession(
        id: UUID(),
        order: 0,
        focusMuscles: [.chest, .triceps, .shoulders],
        items: [
            PlannedItem(exerciseID: "bench-press", targetSets: 4,
                        targetReps: RepRange(min: 6, max: 8), targetLoadKg: 60,
                        restSeconds: 150, coachNote: "Controlled tempo."),
            PlannedItem(exerciseID: "incline-db-press", targetSets: 3,
                        targetReps: RepRange(min: 8, max: 12), targetLoadKg: 24,
                        restSeconds: 120, coachNote: "Full stretch at the bottom."),
            PlannedItem(exerciseID: "cable-fly", targetSets: 3,
                        targetReps: RepRange(min: 12, max: 15), targetLoadKg: nil,
                        restSeconds: 75, coachNote: "Squeeze and hold."),
        ]
    )
    return NavigationStack {
        SessionStartView(planned: planned, catalog: CatalogStore(exercises: [])) { _, _ in }
    }
}
