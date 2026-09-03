import SwiftUI

public struct IconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var selectedIcon: String

    public let icons = [
        "figure.strengthtraining.traditional",
        "figure.core.training",
        "figure.run",
        "dumbbell.fill",
        "figure.walk",
        "figure.cross.training",
        "figure.highintensity.intervaltraining",
        "flame.fill",
        "bolt.fill",
        "heart.fill",
        "trophy.fill",
        "timer",
        "figure.cooldown",
        "scalemass.fill",
        "medal.fill",
        "star.fill"
    ]

    public init(selectedIcon: Binding<String>) {
        self._selectedIcon = selectedIcon
    }

    private let columns = [
        GridItem(.adaptive(minimum: 60), spacing: 16)
    ]

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(icons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                            dismiss()
                        } label: {
                            VStack {
                                Image(systemName: icon)
                                    .font(.system(size: 26))
                                    .foregroundStyle(selectedIcon == icon ? GymTheme.green : GymTheme.label)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        selectedIcon == icon ? GymTheme.green.opacity(0.2) : GymTheme.surface2,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(selectedIcon == icon ? GymTheme.green : Color.clear, lineWidth: 2)
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(GymTheme.bg.ignoresSafeArea())
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
