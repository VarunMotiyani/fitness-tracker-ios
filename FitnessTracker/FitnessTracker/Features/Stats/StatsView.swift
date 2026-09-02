import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

struct StatsView: View {
    @Environment(\.modelContext) private var context
    let plan: WeeklyPlan
    let catalog: CatalogStore

    @Query(sort: \PersonalRecordModel.date, order: .reverse)
    private var prRecords: [PersonalRecordModel]

    @Query(sort: \CompletedSessionModel.startedAt, order: .reverse)
    private var completedSessions: [CompletedSessionModel]

    @State private var selectedMode: MapMode = .fatigue
    @State private var effortPeriod: EffortPeriod = .ninetyDays

    enum MapMode: String, CaseIterable {
        case balance = "Muscle balance"
        case fatigue = "Fatigue"
        case strength = "Strength"
    }

    enum EffortPeriod: String, CaseIterable {
        case thirty = "30d"
        case ninetyDays = "90d"
        case oneYear = "1Y"
        case all = "All"
    }

    private var recoveryStatuses: [MuscleGroup: MuscleRecoveryStatus] {
        let sessions = completedSessions.filter { $0.finishedAt != nil }.map { $0.toSnapshot() }
        return RecoveryModel.computeRecovery(from: sessions, catalog: catalog, now: .now)
    }

    private var activityDays: [Date: (count: Int, volume: Double)] {
        var map: [Date: (count: Int, volume: Double)] = [:]
        let cal = Calendar.isoUTC

        for s in completedSessions where s.finishedAt != nil {
            let day = cal.startOfDay(for: s.startedAt)
            var sessionVol: Double = 0
            for entry in s.entries where !entry.skipped {
                for set in entry.sets where !set.isWarmup {
                    sessionVol += (set.actualLoadKg * Double(set.actualReps))
                }
            }
            let prev = map[day] ?? (count: 0, volume: 0)
            map[day] = (count: prev.count + 1, volume: prev.volume + sessionVol)
        }
        return map
    }

    init(plan: WeeklyPlan, catalog: CatalogStore) {
        self.plan = plan
        self.catalog = catalog
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Top Heatmap contribution strip
                ActivityHeatmapView(activityDays: activityDays)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Mode Segmented Control
                Picker("View", selection: $selectedMode) {
                    ForEach(MapMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                // Dual Body Map Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fatigue")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GymTheme.label)
                        .padding(.horizontal, 4)

                    MuscleMapView(mode: .fatigue(recoveryStatuses))

                    Text("Fatigue shows how recently each muscle was trained. High means rest.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(GymTheme.label3)
                        .padding(.horizontal, 4)
                }
                .padding(14)
                .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)

                // Effort Section
                effortSection

                // PRs Section
                prSection
            }
            .padding(.bottom, 80)
        }
        .background(GymTheme.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private var effortSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Effort · how close to failure")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GymTheme.label2)
                Spacer()
            }

            // Period segmented picker
            Picker("Period", selection: $effortPeriod) {
                ForEach(EffortPeriod.allCases, id: \.self) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("2.5 RIR")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(GymTheme.label)
                    Text("average effort")
                        .font(.system(size: 12))
                        .foregroundStyle(GymTheme.label3)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("78%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(GymTheme.yellow)
                    Text("at RIR 3 or harder")
                        .font(.system(size: 12))
                        .foregroundStyle(GymTheme.label3)
                }
            }
        }
        .padding(14)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var prSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Personal Records")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GymTheme.label)
                .padding(.horizontal, 16)

            if prRecords.isEmpty {
                Text("No PRs recorded yet. Finish a workout to set records!")
                    .font(.system(size: 13))
                    .foregroundStyle(GymTheme.label3)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(prRecords.prefix(6).enumerated()), id: \.element.persistentModelID) { idx, pr in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(catalog.exercise(id: pr.exerciseID)?.name ?? pr.exerciseID)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(GymTheme.label)
                                Text(pr.date.formatted(.dateTime.month().day()))
                                    .font(.system(size: 11))
                                    .foregroundStyle(GymTheme.label3)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f kg", pr.value))
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundStyle(GymTheme.green)
                                Text(pr.typeRaw.capitalized)
                                    .font(.system(size: 11))
                                    .foregroundStyle(GymTheme.label2)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if idx < min(5, prRecords.count - 1) {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
        }
    }
}
