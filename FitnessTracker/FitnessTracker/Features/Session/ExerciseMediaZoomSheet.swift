import SwiftUI
import ExerciseCatalog

public struct ExerciseMediaZoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let exercise: Exercise?

    @State private var scale: CGFloat = 1.0

    public init(exercise: Exercise?) {
        self.exercise = exercise
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let ex = exercise {
                        if let firstImage = ex.imagePaths.first, let url = URL(string: firstImage) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(height: 260)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 300)
                                        .scaleEffect(scale)
                                        .gesture(
                                            MagnificationGesture()
                                                .onChanged { scale = $0 }
                                                .onEnded { _ in withAnimation { scale = 1.0 } }
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .padding(16)
                            .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Instructions")
                                .font(.headline)
                                .foregroundStyle(GymTheme.label)

                            ForEach(Array(ex.instructions.enumerated()), id: \.offset) { idx, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(idx + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(GymTheme.green)
                                        .frame(width: 22, height: 22)
                                        .background(GymTheme.green.opacity(0.15), in: Circle())

                                    Text(step)
                                        .font(.subheadline)
                                        .foregroundStyle(GymTheme.label2)
                                }
                            }
                        }
                        .padding(16)
                        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(16)
            }
            .background(GymTheme.bg.ignoresSafeArea())
            .navigationTitle(exercise?.name ?? "Exercise Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
