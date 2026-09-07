import SwiftUI
import Metrics

public struct PlateMathSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var targetWeight: Double
    @State private var selectedBar: BarType
    @State private var unitString: String
    public var onApply: ((Double) -> Void)?
    
    public init(initialWeight: Double = 60.0, barType: BarType = .olympicBarbell, unitString: String = "kg", onApply: ((Double) -> Void)? = nil) {
        _targetWeight = State(initialValue: max(0, initialWeight))
        _selectedBar = State(initialValue: barType)
        _unitString = State(initialValue: unitString)
        self.onApply = onApply
    }
    
    private var result: PlateLoadingResult {
        let barWeight = unitString == "lb" ? selectedBar.defaultWeightLb : selectedBar.defaultWeightKg
        let plates = unitString == "lb" ? PlateMath.standardLbPlates : PlateMath.standardKgPlates
        return PlateMath.calculate(
            totalWeight: targetWeight,
            barWeight: barWeight,
            availablePlates: plates,
            unitString: unitString
        )
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Bar Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Barbell Type")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Bar Type", selection: $selectedBar) {
                        ForEach(BarType.allCases, id: \.self) { bar in
                            Text(bar.displayName).tag(bar)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                    .padding(10)
                    .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
                
                // Target Weight Stepper
                VStack(spacing: 8) {
                    Text("Total Load on Bar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        Button {
                            if targetWeight >= 2.5 { targetWeight -= 2.5 }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title)
                        }
                        
                        Text("\(String(format: "%.1f", targetWeight)) \(unitString)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .frame(minWidth: 160)
                        
                        Button {
                            targetWeight += 2.5
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                        }
                    }
                }
                
                // Plate Math Visual Stack
                VStack(spacing: 12) {
                    Text(result.summary)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Visual Bar & Plates
                    HStack(spacing: 4) {
                        // Bar sleeve
                        Rectangle()
                            .fill(Color.gray)
                            .frame(width: 40, height: 16)
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: 8, height: 28)
                            }
                        
                        // Plates on sleeve
                        if result.platesPerSide.isEmpty {
                            Text("No plates needed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        } else {
                            ForEach(Array(result.platesPerSide.enumerated()), id: \.offset) { _, plate in
                                plateVisual(weight: plate)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    
                    Button("Apply Weight") {
                        onApply?(targetWeight)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    @ViewBuilder
    private func plateVisual(weight: Double) -> some View {
        let height: CGFloat = max(35, min(75, CGFloat(weight) * 2.8))
        let color: Color = plateColor(weight: weight)
        
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: 18, height: height)
            .overlay {
                Text(String(format: "%.0f", weight))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-90))
            }
    }
    
    private func plateColor(weight: Double) -> Color {
        switch weight {
        case 25: return .red
        case 20: return .blue
        case 15: return .yellow
        case 10: return .green
        case 5: return .white.opacity(0.9)
        case 2.5: return .black
        default: return .gray
        }
    }
}
