import FitnessDomain

public struct VolumeBand: Sendable, Equatable {
    public let mev: Int
    public let mav: Int
    public let mrv: Int
    public init(mev: Int, mav: Int, mrv: Int) {
        self.mev = mev
        self.mav = mav
        self.mrv = mrv
    }
}

public enum VolumeLandmarks {

    public static func band(for muscle: MuscleGroup,
                            experience: ExperienceLevel) -> VolumeBand {
        switch experience {
        case .beginner:                 return beginner[muscle] ?? fallback
        case .intermediate, .advanced:  return intermediate[muscle] ?? fallback
        }
    }

    private static let fallback = VolumeBand(mev: 4, mav: 10, mrv: 16)

    private static let beginner: [MuscleGroup: VolumeBand] = [
        .chest:      VolumeBand(mev: 6,  mav: 12, mrv: 18),
        .back:       VolumeBand(mev: 8,  mav: 14, mrv: 20),
        .lowerBack:  VolumeBand(mev: 2,  mav: 6,  mrv: 10),
        .traps:      VolumeBand(mev: 0,  mav: 6,  mrv: 12),
        .shoulders:  VolumeBand(mev: 6,  mav: 12, mrv: 18),
        .biceps:     VolumeBand(mev: 5,  mav: 10, mrv: 16),
        .triceps:    VolumeBand(mev: 4,  mav: 10, mrv: 14),
        .forearms:   VolumeBand(mev: 0,  mav: 4,  mrv: 8),
        .quads:      VolumeBand(mev: 6,  mav: 12, mrv: 18),
        .hamstrings: VolumeBand(mev: 4,  mav: 10, mrv: 16),
        .glutes:     VolumeBand(mev: 0,  mav: 8,  mrv: 14),
        .calves:     VolumeBand(mev: 6,  mav: 12, mrv: 16),
        .abs:        VolumeBand(mev: 0,  mav: 10, mrv: 16),
    ]

    private static let intermediate: [MuscleGroup: VolumeBand] = [
        .chest:      VolumeBand(mev: 8,  mav: 16, mrv: 22),
        .back:       VolumeBand(mev: 10, mav: 18, mrv: 25),
        .lowerBack:  VolumeBand(mev: 2,  mav: 8,  mrv: 12),
        .traps:      VolumeBand(mev: 2,  mav: 10, mrv: 16),
        .shoulders:  VolumeBand(mev: 8,  mav: 16, mrv: 22),
        .biceps:     VolumeBand(mev: 6,  mav: 14, mrv: 20),
        .triceps:    VolumeBand(mev: 6,  mav: 12, mrv: 18),
        .forearms:   VolumeBand(mev: 2,  mav: 6,  mrv: 10),
        .quads:      VolumeBand(mev: 8,  mav: 16, mrv: 22),
        .hamstrings: VolumeBand(mev: 6,  mav: 13, mrv: 18),
        .glutes:     VolumeBand(mev: 4,  mav: 10, mrv: 16),
        .calves:     VolumeBand(mev: 8,  mav: 14, mrv: 18),
        .abs:        VolumeBand(mev: 4,  mav: 12, mrv: 20),
    ]
}
