import SwiftUI
import FitnessDomain
import ExerciseCatalog

struct ExerciseDetailSheet: View {
    let exercise: Exercise
    var selectionTitle: String?
    var onSelectForToday: (() -> Bool)?
    var onReplaceForToday: (() -> Void)?
    var onRemoveFromToday: (() -> Bool)?
    var isCustom: Bool = false
    var onEditCustom: (() -> Void)?
    var onDeleteCustom: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showAnimation = true
    @State private var showRemoveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var selectionError: String?

    /// Every non-GIF image path, in catalog order. The free-exercise-db catalog
    /// (no real `.gif` for ~90% of its entries) ships each exercise as 2 static
    /// poses here — looping between them beats freezing on the first forever.
    private var stillURLs: [URL] {
        exercise.imagePaths
            .filter { !$0.lowercased().hasSuffix(".gif") }
            .compactMap { URL(string: $0) }
    }

    private var gifURL: URL? {
        if let gifPath = exercise.imagePaths.first(where: { $0.lowercased().hasSuffix(".gif") }) {
            return URL(string: gifPath)
        }
        return nil
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
                        } else if !stillURLs.isEmpty {
                            CachedRemoteImageLoop(urls: stillURLs, maxPixelSize: 720)
                                .frame(maxWidth: .infinity)
                                .frame(height: 240)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
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
                                        .font(.caption.weight(.bold))
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
                            .font(.title.weight(.bold))
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
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(white: 0.60))

                            HStack(spacing: 6) {
                                ForEach(exercise.secondaryMuscles, id: \.self) { m in
                                    tagChip(title: m.label, color: Color(white: 0.60))
                                }
                            }
                        }
                    }

                    // Instructions Steps
                    if !exercise.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Instructions")
                                .font(.body.weight(.bold))
                                .foregroundStyle(GymTheme.label)

                            ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { idx, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(idx + 1)")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(GymTheme.green)
                                        .frame(width: 22, height: 22)
                                        .background(GymTheme.green.opacity(0.18), in: Circle())

                                    Text(step)
                                        .font(.subheadline.weight(.regular))
                                        .foregroundStyle(Color(white: 0.85))
                                        .lineSpacing(3)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    if let selectionTitle, let onSelectForToday {
                        Button {
                            if onSelectForToday() {
                                dismiss()
                            } else {
                                selectionError = "That exercise is already in today’s workout."
                            }
                        } label: {
                            Text(selectionTitle)
                                .font(.body.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(GymTheme.green, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    if let onReplaceForToday {
                        Button {
                            onReplaceForToday()
                        } label: {
                            Label("Replace exercise", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(GymTheme.green)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(GymTheme.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    if onRemoveFromToday != nil {
                        Button("Remove from today", role: .destructive) {
                            showRemoveConfirmation = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if isCustom {
                        Divider().padding(.vertical, 4)
                        HStack(spacing: 12) {
                            Button {
                                onEditCustom?()
                                dismiss()
                            } label: {
                                Label("Edit exercise", systemImage: "pencil")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(GymTheme.green)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(GymTheme.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                            }
                            Button {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                            }
                        }
                        .buttonStyle(.plain)
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
                            .font(.title3)
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
        .alert("Couldn’t add exercise", isPresented: Binding(
            get: { selectionError != nil },
            set: { if !$0 { selectionError = nil } }
        )) {
            Button("OK", role: .cancel) { selectionError = nil }
        } message: {
            Text(selectionError ?? "")
        }
        .confirmationDialog("Remove from today?", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove exercise", role: .destructive) {
                if onRemoveFromToday?() == true {
                    dismiss()
                }
            }
        } message: {
            Text("This changes only today’s workout. Your recurring plan stays the same.")
        }
        .confirmationDialog("Delete custom exercise?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete exercise", role: .destructive) {
                onDeleteCustom?()
                dismiss()
            }
        } message: {
            Text("It will be removed from your library. Existing workout history is kept.")
        }
    }

    @ViewBuilder
    private func tagChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
    }
}
