import SwiftUI
import WebKit
import ExerciseCatalog

// MARK: - Animated GIF Player

struct AnimatedGifView: UIViewRepresentable {
    let url: URL

    /// Tracks which URL is currently loaded so `updateUIView` — called on *every*
    /// re-render of whatever contains this view, not just when `url` changes — doesn't
    /// reload the page every time. Without this guard, a screen with a ticking timer
    /// (the workout runner's elapsed-time counter, the rest timer) re-evaluates its body
    /// every second, and an unconditional `loadHTMLString` here made the GIF blank out
    /// and restart from frame one every single second.
    final class Coordinator {
        var loadedURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.layer.cornerRadius = 14
        webView.layer.masksToBounds = true
        // This is a static animated image, nothing inside it is interactive — without
        // this, WebKit's own gesture recognizers grab every tap before the SwiftUI
        // `Button` wrapping this view ever sees it, so tapping the media (or the
        // "Expand" pill layered on top of it) silently did nothing.
        webView.isUserInteractionEnabled = false
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { background-color: #ffffff; display: flex; justify-content: center; align-items: center; width: 100vw; height: 100vh; overflow: hidden; border-radius: 14px; }
        img { width: 100%; height: 100%; object-fit: contain; }
        </style>
        </head>
        <body>
        <img src="\(url.absoluteString)" />
        </body>
        </html>
        """
        uiView.loadHTMLString(html, baseURL: nil)
    }
}

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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.6)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: size, height: size)
                    case .failure:
                        ZStack {
                            GymTheme.surface2
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: size * 0.40))
                                .foregroundStyle(GymTheme.green)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
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
