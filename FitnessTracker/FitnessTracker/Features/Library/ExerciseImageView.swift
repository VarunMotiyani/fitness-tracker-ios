import SwiftUI

struct ExerciseImageView: View {
    let urlString: String?
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(GymTheme.surface2)

            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.7)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    case .failure:
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: size * 0.42))
                            .foregroundStyle(GymTheme.green)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(GymTheme.green)
            }
        }
        .frame(width: size, height: size)
    }
}
