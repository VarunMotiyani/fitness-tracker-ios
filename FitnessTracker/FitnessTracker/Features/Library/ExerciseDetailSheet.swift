import SwiftUI
import FitnessDomain
import ExerciseCatalog

struct ExerciseDetailSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @State private var showAnimation = true

    private var stillURL: URL? {
        if let first = exercise.imagePaths.first, first.hasSuffix(".jpg") || first.hasSuffix(".png") {
            return URL(string: first)
        }
        return exercise.imagePaths.compactMap { URL(string: $0) }.first
    }

    private var gifURL: URL? {
        if let gifPath = exercise.imagePaths.first(where: { $0.hasSuffix(".gif") }) {
            return URL(string: gifPath)
        }
        return exercise.imagePaths.count > 1 ? URL(string: exercise.imagePaths[1]) : stillURL
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Media Player Banner (GIF / Still Photo)
                    ZStack(alignment: .bottomTrailing) {
                        if showAnimation, let gifURL {
                            AnimatedGifView(url: gifURL)
                                .frame(height: 240)
                                .frame(maxWidth: .infinity)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else if let stillURL {
                            AsyncImage(url: stillURL) { phase in
                                switch phase {
                                case .empty:
                                    ZStack {
                                        Color.white
                                        ProgressView()
                                    }
                                    .frame(height: 240)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 240)
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                case .failure:
                                    ZStack {
                                        Color.black.opacity(0.3)
                                        Image(systemName: "dumbbell.fill")
                                            .font(.system(size: 40))
                                            .foregroundStyle(GymTheme.green)
                                    }
                                    .frame(height: 240)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        } else {
                            ZStack {
                                GymTheme.surface2
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(GymTheme.green)
                            }
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        // GIF / Photo toggle button
                        if gifURL != nil {
                            Button {
                                showAnimation.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showAnimation ? "pause.circle.fill" : "play.circle.fill")
                                    Text(showAnimation ? "GIF" : "Still")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(GymTheme.green)
                            }
                            .padding(10)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Title and Badges
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exercise.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(GymTheme.label)

                        HStack(spacing: 8) {
                            tagChip(title: exercise.primaryMuscle.label, color: GymTheme.green)
                            tagChip(title: exercise.equipment.label, color: GymTheme.blue)
                            tagChip(title: exercise.difficulty.rawValue.capitalized, color: GymTheme.orange)
                        }
                    }

                    // Secondary Muscles
                    if !exercise.secondaryMuscles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Secondary muscles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(white: 0.55))

                            HStack(spacing: 6) {
                                ForEach(exercise.secondaryMuscles, id: \.self) { m in
                                    tagChip(title: m.label, color: Color(white: 0.40))
                                }
                            }
                        }
                    }

                    // Instructions Steps
                    if !exercise.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Instructions")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(GymTheme.label)

                            ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { idx, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(idx + 1)")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(GymTheme.green)
                                        .frame(width: 22, height: 22)
                                        .background(GymTheme.green.opacity(0.18), in: Circle())

                                    Text(step)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(Color(white: 0.85))
                                        .lineSpacing(3)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .background(GymTheme.bgElevated.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(white: 0.5))
                            .font(.system(size: 20))
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func tagChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
    }
}
