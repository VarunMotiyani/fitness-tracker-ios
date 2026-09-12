import Foundation
import UIKit

enum CustomExercisePhotoStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("CustomExercisePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func save(_ data: Data, id: UUID) throws -> String {
        let filename = "\(id.uuidString).jpg"
        // PhotosPicker can return HEIC/PNG bytes. Normalize to a predictable,
        // iOS-readable JPEG before storing it, while still preserving unusual
        // formats if UIKit cannot decode the payload.
        let payload = UIImage(data: data)?.jpegData(compressionQuality: 0.86) ?? data
        try payload.write(to: directory.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    static func url(for filename: String?) -> URL? {
        guard let filename else { return nil }
        // Backups are user-imported JSON. Keep path resolution inside our
        // private directory even if a malformed backup contains `../`.
        guard filename.range(of: #"^[A-F0-9-]+\.jpg$"#, options: .regularExpression) != nil else { return nil }
        let url = directory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(filename: String?) {
        guard let url = url(for: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
