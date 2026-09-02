import SwiftUI
import WebKit

// MARK: - Animated GIF Player

struct AnimatedGifView: UIViewRepresentable {
    let url: URL

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
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
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
