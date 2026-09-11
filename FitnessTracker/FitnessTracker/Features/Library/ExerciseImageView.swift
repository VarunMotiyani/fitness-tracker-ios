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
                CachedRemoteImage(url: url, maxPixelSize: size * 3)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(GymTheme.green)
            }
        }
        .frame(width: size, height: size)
    }
}
