import SwiftData

/// The one real model list for the app's default SwiftData store. Shared so
/// `FitnessTrackerApp`'s `.modelContainer(for:)` and anything that needs its
/// own `ModelContainer` pointed at the same on-disk store (the background
/// refresh task, which has no SwiftUI environment to inherit one from) can't
/// drift apart into two different schemas for the same store.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self,
        CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
        BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
        PersonalRecordModel.self, CoachMemoryModel.self,
        ChatMessageModel.self, ChatSummaryModel.self,
        PendingCoachSuggestion.self,
        CoachNoteModel.self, WeeklySummaryModel.self,
        CustomExerciseModel.self,
    ]
}
