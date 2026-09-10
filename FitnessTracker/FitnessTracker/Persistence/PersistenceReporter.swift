import Foundation
import SwiftData
import OSLog

/// Makes persistence failures observable instead of silently discarding them.
@MainActor
enum PersistenceReporter {
    private static let logger = Logger(subsystem: "com.varunmotiyani.TrainSage", category: "Persistence")

    @discardableResult
    static func attemptSave(_ context: ModelContext, operation: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            logger.error("Persistence failed during \(operation, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
