import SwiftUI
import FitnessDomain

public struct ChartDataPoint: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let value: Double
    public let label: String?
    
    public init(date: Date, value: Double, label: String? = nil) {
        self.date = date
        self.value = value
        self.label = label
    }
}

public struct OpenGymLineChart: View {
    public let points: [ChartDataPoint]
    public let goal: Double?
    public let height: CGFloat
    public let lineColor: Color
    public let invertY: Bool
    public let tooltipText: String?
    public let yStepsOverride: [Double]?

    public init(
        points: [ChartDataPoint],
        goal: Double? = nil,
        height: CGFloat = 140,
        lineColor: Color = GymTheme.green,
        invertY: Bool = false,
        tooltipText: String? = nil,
        yStepsOverride: [Double]? = nil
    ) {
        self.points = points
        self.goal = goal
        self.height = height
        self.lineColor = lineColor
        self.invertY = invertY
        self.tooltipText = tooltipText
        self.yStepsOverride = yStepsOverride
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padL: CGFloat = 34
            let padR: CGFloat = 18
            let padT: CGFloat = 18
            let padB: CGFloat = 24

            let safePoints = points.isEmpty ? [
                ChartDataPoint(date: Date().addingTimeInterval(-60*86400), value: 82.5),
                ChartDataPoint(date: Date().addingTimeInterval(-45*86400), value: 81.8),
                ChartDataPoint(date: Date().addingTimeInterval(-30*86400), value: 80.4),
                ChartDataPoint(date: Date().addingTimeInterval(-15*86400), value: 79.6),
                ChartDataPoint(date: Date().addingTimeInterval(-5*86400), value: 79.1),
                ChartDataPoint(date: Date(), value: 78.7)
            ] : points

            let values = safePoints.map(\.value)
            let allVals = goal != nil ? values + [goal!] : values
            let rawMin = allVals.min() ?? 70.0
            let rawMax = allVals.max() ?? 85.0
            let pad = max(0.5, (rawMax - rawMin) * 0.18)
            let yMin = rawMin - pad
            let yMax = rawMax + pad

            let tMin = safePoints.first?.date.timeIntervalSince1970 ?? 0
            let tMax = safePoints.last?.date.timeIntervalSince1970 ?? (tMin + 1)

            let xFor: (Date) -> CGFloat = { d in
                let t = d.timeIntervalSince1970
                let frac = tMax == tMin ? 0.5 : CGFloat((t - tMin) / (tMax - tMin))
                return padL + frac * (w - padL - padR)
            }

            let yFor: (Double) -> CGFloat = { v in
                let frac = CGFloat((v - yMin) / (yMax - yMin))
                let standard = padT + (1.0 - frac) * (h - padT - padB)
                let inverted = padT + frac * (h - padT - padB)
                return invertY ? inverted : standard
            }

            ZStack {
                // 1. Gridlines and Y-axis labels
                let ySteps: [Double] = yStepsOverride ?? (invertY ? [2.0, 4.0] : [rawMax, (rawMax + rawMin) / 2.0, rawMin])
                ForEach(ySteps, id: \.self) { yVal in
                    let yPos = yFor(yVal)
                    Path { p in
                        p.move(to: CGPoint(x: padL, y: yPos))
                        p.addLine(to: CGPoint(x: w - padR, y: yPos))
                    }
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

                    Text(yVal == Double(Int(yVal)) ? String(format: "%.0f", yVal) : String(format: "%.1f", yVal))
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(Color(white: 0.50))
                        .position(x: padL - 16, y: yPos)
                }

                // 2. Goal dashed yellow line
                if let g = goal {
                    let yPos = yFor(g)
                    Path { p in
                        p.move(to: CGPoint(x: padL, y: yPos))
                        p.addLine(to: CGPoint(x: w - padR, y: yPos))
                    }
                    .stroke(GymTheme.yellow, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    Text(String(format: "%.0f", g))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GymTheme.yellow)
                        .position(x: w - padR - 2, y: yPos - 8)
                }

                // 3. Gradient Fill under curve
                Path { p in
                    guard let first = safePoints.first else { return }
                    p.move(to: CGPoint(x: xFor(first.date), y: h - padB))
                    p.addLine(to: CGPoint(x: xFor(first.date), y: yFor(first.value)))
                    for pt in safePoints.dropFirst() {
                        p.addLine(to: CGPoint(x: xFor(pt.date), y: yFor(pt.value)))
                    }
                    if let last = safePoints.last {
                        p.addLine(to: CGPoint(x: xFor(last.date), y: h - padB))
                    }
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [lineColor.opacity(0.30), lineColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // 4. Solid curve line
                Path { p in
                    guard let first = safePoints.first else { return }
                    p.move(to: CGPoint(x: xFor(first.date), y: yFor(first.value)))
                    for pt in safePoints.dropFirst() {
                        p.addLine(to: CGPoint(x: xFor(pt.date), y: yFor(pt.value)))
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // 5. Data Point Circles
                ForEach(safePoints) { pt in
                    Circle()
                        .fill(lineColor)
                        .frame(width: 6, height: 6)
                        .position(x: xFor(pt.date), y: yFor(pt.value))
                }

                // 6. Active Tooltip
                if let tip = tooltipText, let activePt = safePoints.dropFirst().first {
                    VStack(spacing: 0) {
                        Text(tip)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.16, green: 0.16, blue: 0.18), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .position(x: xFor(activePt.date) + 36, y: yFor(activePt.value) - 22)
                }

                // 7. X-axis month labels
                HStack {
                    Text("Jul")
                    Spacer()
                    Text("Aug")
                }
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color(white: 0.50))
                .padding(.horizontal, padL + 20)
                .position(x: w / 2, y: h - 8)
            }
        }
        .frame(height: height)
    }
}
