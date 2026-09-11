import SwiftUI
import UIKit
import ImageIO
import Combine

/// Native animated-GIF renderer. Replaces a WKWebView that loaded an `<img>`
/// per instance — a WebKit process plus HTML layout per GIF on screen was the
/// single biggest render cost on the exercise detail and session screens.
/// Frames are decoded off the main actor through `GifFrameCache`, downscaled
/// once, then played back by a `TimelineView`.
struct AnimatedGifView: View {
    let url: URL
    var maxPixelSize: CGFloat = 420

    @State private var plan: GifPlaybackPlan?
    @State private var failed = false

    var body: some View {
        Group {
            if let plan, let first = plan.frames.first {
                if plan.frames.count == 1 {
                    Image(uiImage: first)
                        .resizable()
                        .scaledToFit()
                } else {
                    GifFrameTimelineView(frames: plan.frames, frameDelay: plan.frameDelay)
                }
            } else if failed {
                Image(systemName: "photo")
                    .foregroundStyle(GymTheme.label3)
            } else {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .task(id: url) {
            failed = false
            plan = nil
            do {
                let data = try await RemoteImageCache.shared.data(for: url)
                let decoded = await GifFrameCache.shared.plan(for: url, data: data, maxPixelSize: maxPixelSize)
                if let decoded {
                    plan = decoded
                } else {
                    failed = true
                }
            } catch {
                failed = true
            }
        }
    }
}

struct GifPlaybackPlan {
    let frames: [UIImage]
    let frameDelay: TimeInterval
}

/// Decodes and memoizes GIF frame sets off the main actor. Manual LRU: a few
/// dozen frames per plan, at most `maxPlans` plans alive at once.
actor GifFrameCache {
    static let shared = GifFrameCache()

    private var plans: [URL: GifPlaybackPlan] = [:]
    private var keysInOrder: [URL] = []
    private let maxPlans = 8

    func plan(for url: URL, data: Data, maxPixelSize: CGFloat) -> GifPlaybackPlan? {
        let cacheKey = URL(string: url.absoluteString + "#px\(Int(maxPixelSize))") ?? url
        if let hit = plans[cacheKey] {
            keysInOrder.removeAll { $0 == cacheKey }
            keysInOrder.append(cacheKey)
            return hit
        }
        guard let decoded = Self.decode(data: data, maxPixelSize: maxPixelSize) else { return nil }
        plans[cacheKey] = decoded
        keysInOrder.append(cacheKey)
        while keysInOrder.count > maxPlans {
            plans.removeValue(forKey: keysInOrder.removeFirst())
        }
        return decoded
    }

    /// Hard cap on decoded frames — an unusually long GIF (a real one can run
    /// past 150 frames) would otherwise hold every one as a decoded `UIImage`
    /// at once. Sampling evenly across the source keeps full-loop playback
    /// timing instead of just truncating to the first 40 frames.
    private static let maxDecodedFrames = 40

    private static func decode(data: Data, maxPixelSize: CGFloat) -> GifPlaybackPlan? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let sourceCount = CGImageSourceGetCount(source)
        guard sourceCount > 0 else { return nil }
        let stride = Swift.max(1, sourceCount / maxDecodedFrames)

        var frames: [UIImage] = []
        var totalDelay: Double = 0
        for index in 0..<sourceCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }

            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gifProperties?[kCGImagePropertyGIFDelayTime] as? NSNumber).map { $0.doubleValue } ?? 0.1
            totalDelay += delay < 0.02 ? 0.1 : delay

            guard index % stride == 0 else { continue }

            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let scale = Swift.min(1, maxPixelSize / Swift.max(width, height))
            if scale < 1 {
                let newSize = CGSize(width: width * scale, height: height * scale)
                let renderer = UIGraphicsImageRenderer(size: newSize)
                frames.append(renderer.image { context in
                    context.cgContext.draw(cgImage, in: CGRect(origin: .zero, size: newSize))
                })
            } else {
                frames.append(UIImage(cgImage: cgImage))
            }
        }
        guard let first = frames.first else { return nil }
        guard frames.count > 1 else { return GifPlaybackPlan(frames: [first], frameDelay: 1) }

        // `totalDelay` already covers every source frame (sampled or not), so
        // dividing by the kept-frame count gives the right per-shown-frame
        // delay to preserve the source GIF's real loop duration.
        let frameDelay = Swift.max(0.04, totalDelay / Double(frames.count))
        return GifPlaybackPlan(frames: frames, frameDelay: frameDelay)
    }
}


/// Plays the decoded frames at a fixed cadence. Owns the tick, so only this
/// tiny view redraws per frame \u2014 not the hosting screen.
private struct GifFrameTimelineView: View {
    let frames: [UIImage]
    let frameDelay: TimeInterval
    private let ticker: Publishers.Autoconnect<Timer.TimerPublisher>
    @State private var index: Int = 0

    init(frames: [UIImage], frameDelay: TimeInterval) {
        self.frames = frames
        let clamped = Swift.max(0.04, frameDelay)
        self.frameDelay = clamped
        self.ticker = Timer.publish(every: clamped, on: .main, in: .common).autoconnect()
    }

    var body: some View {
        Image(uiImage: frames.indices.contains(index) ? frames[index] : frames[0])
            .resizable()
            .scaledToFit()
            .onReceive(ticker) { _ in
                index = (index + 1) % frames.count
            }
    }
}
