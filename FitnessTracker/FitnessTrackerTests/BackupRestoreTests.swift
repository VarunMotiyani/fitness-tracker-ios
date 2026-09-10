import Testing
import SwiftData
import Foundation
import FitnessDomain
@testable import FitnessTracker

@MainActor
struct BackupRestoreTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: UserProfile.self, StoredPlan.self, ProviderProfile.self, CustomExerciseModel.self, AICallRecord.self,
            CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self, ChatMessageModel.self,
            ChatSummaryModel.self, PendingCoachSuggestion.self, CoachNoteModel.self,
            WeeklySummaryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func backupRestoresProfileAndMeasurements() throws {
        let source = ModelContext(try container())
        let profile = UserProfile(goalRaw: "buildMuscle", experienceRaw: "intermediate", heightCm: 180,
            weightKg: 80, birthYear: 1990, sexRaw: "male", sessionsPerWeek: 4, sessionLengthMinutes: 60,
            availableEquipmentRaws: ["barbell"], excludedMuscleRaws: [], excludedExerciseIDs: [])
        profile.bodyFatPercent = 17.4
        source.insert(profile)
        source.insert(CustomExerciseModel(name: "Cable Fly", primaryMuscle: .chest, equipment: .cable))
        source.insert(BodyweightEntryModel(date: Date(timeIntervalSince1970: 1_700_000_000), kg: 80, morningKg: 79.5, nightKg: 80.5))
        try source.save()

        let data = try BackupRestoreService.exportData(context: source)
        let destination = ModelContext(try container())
        try BackupRestoreService.restore(data: data, into: destination)

        let profiles = try destination.fetch(FetchDescriptor<UserProfile>())
        let restored = try #require(profiles.first)
        #expect(restored.goalRaw == "buildMuscle")
        #expect(restored.bodyFatPercent == 17.4)
        let weights = try destination.fetch(FetchDescriptor<BodyweightEntryModel>())
        let weight = try #require(weights.first)
        #expect(weight.morningKg == 79.5)
        #expect(weight.nightKg == 80.5)
        let custom = try destination.fetch(FetchDescriptor<CustomExerciseModel>())
        #expect(custom.first?.name == "Cable Fly")
    }

    @Test func resetRemovesAllModelsAndOwnedPreferences() throws {
        let context = ModelContext(try container())
        context.insert(ChatMessageModel(role: "user", text: "hello"))
        context.insert(CoachNoteModel(kindRaw: "daily", text: "note"))
        try context.save()
        let defaults = UserDefaults(suiteName: "BackupRestoreTests.reset")!
        defaults.set(true, forKey: "gym_sound")

        try BackupRestoreService.reset(context: context, defaults: defaults)
        let messages = try context.fetch(FetchDescriptor<ChatMessageModel>())
        let notes = try context.fetch(FetchDescriptor<CoachNoteModel>())
        #expect(messages.isEmpty)
        #expect(notes.isEmpty)
        #expect(defaults.object(forKey: "gym_sound") == nil)
        defaults.removePersistentDomain(forName: "BackupRestoreTests.reset")
    }
}
