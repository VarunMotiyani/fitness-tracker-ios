import SwiftUI
import UIKit
import CryptoKit
import ImageIO

/// On-disk + in-memory cache for exercise thumbnails and GIF bytes.
///
/// SwiftUI's `AsyncImage` has no disk cache: every re-entry to a list re-fetched
/// every thumbnail over the network, which showed up as spinner flicker in
/// Library/Home/Session. This cache keeps bytes on disk (survives app relaunch)
/// and decoded stills in memory.
actor RemoteImageCache {
    static let shared = RemoteImageCache()

    /// Disk store cap. Trimmed oldest-file-first after every write that pushes
    /// the directory over this — the "LRU-trimmed disk cache" the perf plan
    /// called for, which the first pass of this file never actually added.
    private static let diskCapBytes = 150 * 1024 * 1024

    private let memory = NSCache<NSString, UIImage>()
    private let diskDir: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        diskDir = base.appendingPathComponent("RemoteImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: false)
        memory.totalCostLimit = 60 * 1024 * 1024  // 60 MB of decoded stills
    }

    // MARK: - Bytes (also used by the GIF renderer)

    func data(for url: URL) async throws -> Data {
        let file = diskFile(for: url)
        if let cached = try? Data(contentsOf: file) {
            return cached
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        // `URLSession.data(for:)` only throws on transport failure — a 404/500
        // still returns normally with the error page as the body. Writing that
        // to disk as if it were image bytes poisoned the cache permanently
        // (every future read served the same bad file, no retry). Only cache
        // an actual 2xx.
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try? data.write(to: file, options: .atomic)
        trimDiskCacheIfNeeded()
        return data
    }

    // MARK: - Decoded stills

    func image(for url: URL, maxPixelSize: CGFloat = 0) async -> UIImage? {
        // Resolution must be part of the key: the same URL is fetched at
        // thumbnail size in lists and full size in a detail view, and without
        // this the first caller to populate the cache "wins" for every caller
        // after it regardless of the size they actually asked for.
        let cacheKey = "\(url.absoluteString)#px\(Int(maxPixelSize))" as NSString
        if let hit = memory.object(forKey: cacheKey) {
            return hit
        }
        guard let data = try? await data(for: url) else { return nil }
        let image = Self.image(data: data, maxPixelSize: maxPixelSize)
        if let image {
            let bytes = Int(image.size.width) * Int(image.size.height) * 4
            memory.setObject(image, forKey: cacheKey, cost: Swift.max(bytes, 1))
        }
        return image
    }

    // MARK: - Helpers

    private func diskFile(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return diskDir.appendingPathComponent(name + ".bin")
    }

    /// Oldest-modified-first eviction once the directory crosses the cap.
    /// Runs after every write; cheap enough at this file count (thumbnails +
    /// GIF bytes, not thousands of entries) to just re-list the directory
    /// rather than keep a running index.
    private func trimDiskCacheIfNeeded() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: diskDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        else { return }
        let files = entries.compactMap { url -> (url: URL, date: Date, size: Int)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate, let size = values.fileSize
            else { return nil }
            return (url, date, size)
        }
        var total = files.reduce(0) { $0 + $1.size }
        guard total > Self.diskCapBytes else { return }
        for file in files.sorted(by: { $0.date < $1.date }) {
            guard total > Self.diskCapBytes else { break }
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
    }

    /// Decodes a still, downscaled to `maxPixelSize` on its longest side when a
    /// limit is given (full decode of a 2000px JPEG per thumbnail was the cost).
    /// Goes through `CGImageSourceCreateThumbnailAtIndex` with
    /// `kCGImageSourceCreateThumbnailWithTransform` rather than a raw
    /// `CGImageSourceCreateImageAtIndex` + manual `CGContext` draw — the raw
    /// path ignores a photo's EXIF orientation tag entirely (a camera photo
    /// shot rotated renders sideways/upside-down), where the thumbnail API
    /// bakes the correct rotation in as part of decoding.
    static func image(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize > 0 ? maxPixelSize : 4096,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}

/// `AsyncImage` replacement that reads through `RemoteImageCache`, so revisits
/// render instantly instead of re-downloading and flashing a spinner.
struct CachedRemoteImage: View {
    let url: URL
    var maxPixelSize: CGFloat = 0

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(GymTheme.green)
            } else {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .task(id: url) {
            failed = false
            image = await RemoteImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
            failed = image == nil
        }
    }
}

/// The free-exercise-db catalog ships each exercise as static poses (`0.jpg`,
/// `1.jpg`, …) instead of a real animated GIF — showing only the first one
/// left "Free" media permanently frozen on a single frame with no way to see
/// the motion. This auto-loops between them, the same visible effect as a
/// GIF, without needing one. A single URL just renders as a plain still.
struct CachedRemoteImageLoop: View {
    let urls: [URL]
    var maxPixelSize: CGFloat = 0
    var frameInterval: Duration = .seconds(0.6)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames: [UIImage] = []
    @State private var failed = false
    @State private var index = 0

    var body: some View {
        ZStack {
            if frames.isEmpty {
                if failed {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(GymTheme.green)
                } else {
                    ProgressView().scaleEffect(0.6)
                }
            } else {
                // All frames pre-decoded and stacked, faded by index — a
                // stable set of `Image` views with no identity change, so
                // the loop is a pure opacity cross-fade with nothing to
                // re-fetch/re-decode mid-animation. The earlier version
                // gave each frame a fresh `CachedRemoteImage` (via `.id`),
                // which reset its @State and re-awaited the cache on every
                // cycle — a real (if brief) re-fetch, not just a redraw,
                // which is what showed up as a stutter/flash under the fade.
                ForEach(frames.indices, id: \.self) { i in
                    Image(uiImage: frames[i])
                        .resizable()
                        .scaledToFit()
                        .opacity(i == index ? 1 : 0)
                }
            }
        }
        .task(id: urls) {
            frames = []
            failed = false
            index = 0
            var loaded: [UIImage] = []
            for url in urls {
                if let image = await RemoteImageCache.shared.image(for: url, maxPixelSize: maxPixelSize) {
                    loaded.append(image)
                }
            }
            frames = loaded
            failed = loaded.isEmpty
            guard loaded.count > 1, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: frameInterval)
                if Task.isCancelled { return }
                // Plain hard cut, no cross-fade: these are two structurally
                // different poses (not just a color/brightness change), so
                // blending them at partial opacity always shows both poses
                // overlapping mid-fade — a "double exposure" that reads as
                // ghosting, not motion. A clean cut looks like an intentional
                // frame flip; a fade between different content never does.
                index = (index + 1) % loaded.count
            }
        }
    }
}
