import SwiftUI
import ExerciseCatalog

// MARK: - Exercise Thumbnail View

struct ExerciseThumbnailView: View {
    let urlString: String?
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 8

    init(urlString: String?, size: CGFloat = 52, cornerRadius: CGFloat = 8) {
        self.urlString = urlString
        self.size = size
        self.cornerRadius = cornerRadius
    }

    init(exercise: Exercise?, size: CGFloat = 52, cornerRadius: CGFloat = 8) {
        self.urlString = exercise?.imagePaths.first
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white)

            if let urlString, let url = URL(string: urlString) {
                CachedRemoteImage(url: url, maxPixelSize: size * 3)
            } else {
                ZStack {
                    GymTheme.surface2
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: size * 0.40))
                        .foregroundStyle(GymTheme.green)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
