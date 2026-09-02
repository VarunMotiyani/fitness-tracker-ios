import SwiftUI
import FitnessDomain
import Metrics

public enum MuscleMapDisplayMode {
    case fatigue([MuscleGroup: MuscleRecoveryStatus])
    case volume([MuscleGroup: Int])
    case highlight([MuscleGroup])
}

public struct MuscleMapView: View {
    public let mode: MuscleMapDisplayMode
    public var onMuscleTapped: ((MuscleGroup) -> Void)? = nil

    @State private var highlightedMuscle: MuscleGroup? = nil

    public init(mode: MuscleMapDisplayMode, onMuscleTapped: ((MuscleGroup) -> Void)? = nil) {
        self.mode = mode
        self.onMuscleTapped = onMuscleTapped
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Dual Side-by-Side Body Canvas (Front + Back)
            HStack(spacing: 12) {
                bodySideView(orientation: .front, title: "ANTERIOR")
                bodySideView(orientation: .back, title: "POSTERIOR")
            }
            .frame(height: 290)
            .padding(12)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12), in: RoundedRectangle(cornerRadius: 14))

            // Highlighted Detail Card or Legend
            if let selected = highlightedMuscle {
                HStack(spacing: 8) {
                    Circle()
                        .fill(colorFor(muscle: selected))
                        .frame(width: 10, height: 10)
                    Text(selected.rawValue.capitalized)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(statusDetail(for: selected))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.75))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 0.17, green: 0.17, blue: 0.18), in: RoundedRectangle(cornerRadius: 10))
            } else {
                legendView
            }
        }
    }

    @ViewBuilder
    private func bodySideView(orientation: BodyOrientation, title: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(white: 0.5))

            GeometryReader { geo in
                let vbX: CGFloat = orientation == .front ? 0 : 718
                let vbY: CGFloat = 95
                let vbW: CGFloat = 727
                let vbH: CGFloat = 1280

                let scale = min(geo.size.width / vbW, geo.size.height / vbH)
                let drawnW = vbW * scale
                let drawnH = vbH * scale
                let dx = (geo.size.width - drawnW) / 2.0
                let dy = (geo.size.height - drawnH) / 2.0

                Canvas { ctx, size in
                    // Transform coordinate space to SVG viewBox
                    ctx.translateBy(x: dx, y: dy)
                    ctx.scaleBy(x: scale, y: scale)
                    ctx.translateBy(x: -vbX, y: -vbY)

                    // 1. Draw inert silhouette (head, hands, feet, etc.)
                    let inertPaths = BodyVectorData.inertSilhouettePaths(orientation: orientation)
                    for d in inertPaths {
                        let path = SVGPathParser.parse(d)
                        ctx.fill(path, with: .color(Color(red: 0.22, green: 0.22, blue: 0.24)))
                    }

                    // 2. Draw muscle regions
                    for muscle in MuscleGroup.allCases {
                        let paths = BodyVectorData.pathsFor(muscle: muscle, orientation: orientation)
                        let color = colorFor(muscle: muscle)
                        for d in paths {
                            let path = SVGPathParser.parse(d)
                            ctx.fill(path, with: .color(color))
                            if highlightedMuscle == muscle {
                                ctx.stroke(path, with: .color(.white), lineWidth: 3 / scale)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    // Determine which muscle was tapped in SVG space
                    let svgX = (location.x - dx) / scale + vbX
                    let svgY = (location.y - dy) / scale + vbY
                    let tapPoint = CGPoint(x: svgX, y: svgY)

                    for muscle in MuscleGroup.allCases {
                        let paths = BodyVectorData.pathsFor(muscle: muscle, orientation: orientation)
                        for d in paths {
                            let p = SVGPathParser.parse(d)
                            if p.contains(tapPoint) {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                highlightedMuscle = muscle
                                onMuscleTapped?(muscle)
                                return
                            }
                        }
                    }
                    highlightedMuscle = nil
                }
            }
        }
    }

    private func colorFor(muscle: MuscleGroup) -> Color {
        switch mode {
        case .fatigue(let statuses):
            guard let status = statuses[muscle] else { return Color(red: 0.22, green: 0.22, blue: 0.24) }
            switch status.state {
            case .ready:
                return Color(red: 0.19, green: 0.82, blue: 0.35) // #30d158 Apple Green
            case .recovering:
                return Color(red: 1.0, green: 0.62, blue: 0.04) // #ff9f0a Apple Orange
            case .fatigued:
                return Color(red: 1.0, green: 0.27, blue: 0.23) // #ff453a Apple Red
            }
        case .volume(let setsMap):
            let count = setsMap[muscle] ?? 0
            if count == 0 { return Color(red: 0.22, green: 0.22, blue: 0.24) }
            if count < 6 { return Color(red: 0.19, green: 0.82, blue: 0.35).opacity(0.45) }
            if count < 12 { return Color(red: 0.19, green: 0.82, blue: 0.35).opacity(0.75) }
            return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .highlight(let muscles):
            return muscles.contains(muscle) ? Color(red: 0.19, green: 0.82, blue: 0.35) : Color(red: 0.22, green: 0.22, blue: 0.24)
        }
    }

    private func statusDetail(for muscle: MuscleGroup) -> String {
        switch mode {
        case .fatigue(let statuses):
            guard let status = statuses[muscle] else { return "Untrained" }
            let pct = Int((1.0 - status.fatigueScore) * 100)
            return "\(status.state.label) · \(pct)% recovered"
        case .volume(let setsMap):
            let count = setsMap[muscle] ?? 0
            return "\(count) sets completed this week"
        case .highlight(let muscles):
            return muscles.contains(muscle) ? "Targeted today" : "Resting"
        }
    }

    private var legendView: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 0.19, green: 0.82, blue: 0.35)).frame(width: 8, height: 8)
                Text("Ready").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.75))
            }
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1.0, green: 0.62, blue: 0.04)).frame(width: 8, height: 8)
                Text("Recovering").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.75))
            }
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1.0, green: 0.27, blue: 0.23)).frame(width: 8, height: 8)
                Text("Fatigued").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.75))
            }
        }
    }
}
