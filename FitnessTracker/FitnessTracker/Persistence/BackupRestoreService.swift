import Foundation
import SwiftData
import FitnessDomain

/// Single, versioned local backup boundary. Credentials are never serialized;
/// provider secrets remain in Keychain.
@MainActor
enum BackupRestoreService {
    enum BackupError: LocalizedError {
        case invalidFormat
        case unsupportedVersion(Int)
        case saveFailed(Error)
        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "This file is not a valid TrainSage backup."
            case .unsupportedVersion(let version): return "Backup version \(version) is not supported."
            case .saveFailed(let error): return "Could not save restored data: \(error.localizedDescription)"
            }
        }
    }

    static let preferenceKeys = [
        "gym_weight_unit", "gym_week_start", "gym_rest_sec", "gym_rest_pause_sec", "gym_keep_awake", "gym_sound",
        "gym_timer_flash", "gym_effort_mode", "athleteBodyModel", "gym_accent_color", "gym_theme", "gym_reminder_on",
        "gym_reminder_hour", "gym_reminder_minute", "proactive.settings.daily", "proactive.settings.weekly",
        "proactive.settings.inbody", "proactive.settings.checkin", "proactive.settings.pattern", "gym_custom_routines_json",
        "gym_week_schedule_json", "gym_day_plan_json", "gym_day_plan_auto_json", "gym_day_workout_overrides_json",
        "targetWeightKg", "gym_split_template_name", "gym_equip_filter_on", "gym_active_profile_id",
        "gym_equipment_profiles_json", "gym_media_source", "gym_working_weights_json"
    ]

    static func exportData(context: ModelContext, defaults: UserDefaults = .standard) throws -> Data {
        let df = ISO8601DateFormatter()
        let date: (Date) -> String = { df.string(from: $0) }
        let optional: (Any?) -> Any = { $0 ?? NSNull() }
        func rows<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let profiles = rows(UserProfile.self).map { p in
            ["goalRaw": p.goalRaw, "experienceRaw": p.experienceRaw, "heightCm": p.heightCm, "weightKg": p.weightKg,
             "birthYear": p.birthYear, "sexRaw": p.sexRaw, "sessionsPerWeek": p.sessionsPerWeek,
             "splitTemplateName": optional(p.splitTemplateName), "sessionLengthMinutes": p.sessionLengthMinutes,
             "availableEquipmentRaws": p.availableEquipmentRaws, "excludedMuscleRaws": p.excludedMuscleRaws,
             "excludedExerciseIDs": p.excludedExerciseIDs, "bodyFatPercent": optional(p.bodyFatPercent),
             "skeletalMuscleMassKg": optional(p.skeletalMuscleMassKg), "bodyFatMassKg": optional(p.bodyFatMassKg),
             "fatFreeMassKg": optional(p.fatFreeMassKg), "totalBodyWaterL": optional(p.totalBodyWaterL),
             "proteinKg": optional(p.proteinKg), "mineralKg": optional(p.mineralKg),
             "basalMetabolicRateKcal": optional(p.basalMetabolicRateKcal), "visceralFatLevel": optional(p.visceralFatLevel),
             "inBodyScore": optional(p.inBodyScore), "waistHipRatio": optional(p.waistHipRatio),
             "phaseAngleDegrees": optional(p.phaseAngleDegrees), "createdAt": date(p.createdAt), "updatedAt": date(p.updatedAt)] as [String: Any]
        }
        let weights = rows(BodyweightEntryModel.self).map { ["date": date($0.date), "kg": $0.kg, "morningKg": optional($0.morningKg), "nightKg": optional($0.nightKg)] as [String: Any] }
        let checkins = rows(DailyCheckinModel.self).map { ["date": date($0.date), "sleepQuality": optional($0.sleepQuality), "soreness": optional($0.soreness), "note": optional($0.note)] as [String: Any] }
        let observations = rows(ObservationModel.self).map { ["kind": $0.kind, "value": $0.value, "unit": $0.unit, "timestamp": date($0.timestamp), "contextJSON": $0.contextJSON, "sessionID": optional($0.sessionID?.uuidString), "entryExerciseID": optional($0.entryExerciseID), "confirmed": $0.confirmed] as [String: Any] }
        let records = rows(PersonalRecordModel.self).map { ["typeRaw": $0.typeRaw, "exerciseID": $0.exerciseID, "value": $0.value, "atLoadKg": $0.atLoadKg, "reps": $0.reps, "date": date($0.date), "sessionID": $0.sessionID.uuidString] as [String: Any] }
        let providers = rows(ProviderProfile.self).map { ["id": $0.id.uuidString, "displayName": $0.displayName, "adapterKindRaw": $0.adapterKindRaw, "baseURL": optional($0.baseURL), "modelID": $0.modelID, "supportsVision": $0.supportsVision, "pricePerMTokIn": $0.pricePerMTokIn, "pricePerMTokOut": $0.pricePerMTokOut, "pricePerMTokCached": $0.pricePerMTokCached, "isActive": $0.isActive, "createdAt": date($0.createdAt), "fallbackProfileID": optional($0.fallbackProfileID?.uuidString), "capToolCallingRaw": optional($0.capToolCallingRaw)] as [String: Any] }
        let plans = rows(StoredPlan.self).map { ["generatedAt": date($0.generatedAt), "weekStartDate": date($0.weekStartDate), "planJSON": $0.planJSON.base64EncodedString(), "hadValidationIssues": $0.hadValidationIssues] as [String: Any] }
        let sessions = rows(CompletedSessionModel.self).map { s -> [String: Any] in
            let entries = s.entries.map { e -> [String: Any] in
                let sets = e.sets.map { x -> [String: Any] in ["targetReps": x.targetReps, "targetLoadKg": optional(x.targetLoadKg), "actualReps": x.actualReps, "actualLoadKg": x.actualLoadKg, "startedAt": date(x.startedAt), "completedAt": date(x.completedAt), "restBeforeSec": x.restBeforeSec, "rpe": optional(x.rpe), "rir": optional(x.rir), "heldSec": optional(x.heldSec), "isWarmup": x.isWarmup, "isDropSet": x.isDropSet, "toFailure": x.toFailure, "assisted": x.assisted, "dropsJSON": x.dropsJSON, "clustersJSON": x.clustersJSON] }
                return ["exerciseID": e.exerciseID, "performedOrder": e.performedOrder, "stateRaw": e.stateRaw, "skipped": e.skipped, "wasSwappedFrom": optional(e.wasSwappedFrom), "feelRaw": optional(e.feelRaw), "note": optional(e.note), "sets": sets]
            }
            return ["id": s.id.uuidString, "startedAt": date(s.startedAt), "finishedAt": optional(s.finishedAt.map(date)), "weekdayRaw": s.weekdayRaw, "timeOfDayMinutes": s.timeOfDayMinutes, "plannedDurationMin": s.plannedDurationMin, "actualDurationMin": s.actualDurationMin, "energyRaw": s.energyRaw, "timeAvailableMin": s.timeAvailableMin, "outcomeRaw": optional(s.outcomeRaw), "partialReasonRaw": optional(s.partialReasonRaw), "coachSourceRaw": s.coachSourceRaw, "plannedSessionID": optional(s.plannedSessionID?.uuidString), "overallNote": optional(s.overallNote), "importSource": optional(s.importSource), "importSourceID": optional(s.importSourceID), "entries": entries]
        }
        let calls = rows(AICallRecord.self).map { ["timestamp": date($0.timestamp), "callType": $0.callType, "providerDisplayName": $0.providerDisplayName, "modelID": $0.modelID, "inputTokens": $0.inputTokens, "outputTokens": $0.outputTokens, "cachedTokens": $0.cachedTokens, "costUSD": $0.costUSD, "success": $0.success, "usedFallback": $0.usedFallback] as [String: Any] }
        let memories = rows(CoachMemoryModel.self).map { ["id": $0.id.uuidString, "kindRaw": $0.kindRaw, "statement": $0.statement, "action": optional($0.action), "confidence": $0.confidence, "sourceKind": $0.sourceKind, "sourceAgent": optional($0.sourceAgent), "createdAt": date($0.createdAt), "lastConfirmedAt": date($0.lastConfirmedAt), "supersededBy": optional($0.supersededBy?.uuidString), "retiredByCap": $0.retiredByCap, "outcomeScore": optional($0.outcomeScore), "tagExerciseID": optional($0.tagExerciseID), "tagMuscleRaw": optional($0.tagMuscleRaw), "tagEquipmentRaw": optional($0.tagEquipmentRaw), "tagFreeJSON": $0.tagFreeJSON] as [String: Any] }
        let messages = rows(ChatMessageModel.self).map { ["id": $0.id.uuidString, "role": $0.role, "text": $0.text, "timestamp": date($0.timestamp)] as [String: Any] }
        let summaries = rows(ChatSummaryModel.self).map { ["text": $0.text, "updatedAt": date($0.updatedAt), "messagesCoveredThrough": optional($0.messagesCoveredThrough.map(date))] as [String: Any] }
        let suggestions = rows(PendingCoachSuggestion.self).map { ["id": $0.id.uuidString, "plannedSessionID": $0.plannedSessionID.uuidString, "kind": $0.kind, "exerciseID": $0.exerciseID, "replacementExerciseID": optional($0.replacementExerciseID), "targetSets": optional($0.targetSets), "targetRepsMin": optional($0.targetRepsMin), "targetRepsMax": optional($0.targetRepsMax), "targetLoadKg": optional($0.targetLoadKg), "rationale": $0.rationale, "source": $0.source, "createdAt": date($0.createdAt), "resolvedAt": optional($0.resolvedAt.map(date)), "accepted": optional($0.accepted), "sourceMemoryID": optional($0.sourceMemoryID?.uuidString)] as [String: Any] }
        let notes = rows(CoachNoteModel.self).map { ["id": $0.id.uuidString, "kindRaw": $0.kindRaw, "topicRaw": optional($0.topicRaw), "text": $0.text, "reason": optional($0.reason), "createdAt": date($0.createdAt), "readAt": optional($0.readAt.map(date))] as [String: Any] }
        let weekly = rows(WeeklySummaryModel.self).map { ["weekStartDate": date($0.weekStartDate), "headline": $0.headline, "summaryBody": $0.summaryBody, "nextWeekFocus": $0.nextWeekFocus, "generatedAt": date($0.generatedAt)] as [String: Any] }
        let preferences = preferenceKeys.reduce(into: [String: Any]()) { if let value = defaults.object(forKey: $1) { $0[$1] = value } }
        let customExercises = rows(CustomExerciseModel.self).map { ["id": $0.id.uuidString, "name": $0.name, "primaryMuscleRaw": $0.primaryMuscleRaw, "secondaryMuscleRaws": $0.secondaryMuscleRaws, "equipmentRaw": $0.equipmentRaw, "mechanicRaw": $0.mechanicRaw, "forceRaw": optional($0.forceRaw), "difficultyRaw": $0.difficultyRaw, "isUnilateral": $0.isUnilateral, "instructions": $0.instructions, "photoFilename": optional($0.photoFilename), "createdAt": date($0.createdAt), "updatedAt": date($0.updatedAt)] as [String: Any] }
        let root: [String: Any] = ["appName": "TrainSage", "version": 4, "exportedAt": date(.now), "preferences": preferences, "profiles": profiles, "plans": plans, "providers": providers, "customExercises": customExercises, "workouts": sessions, "bodyweight": weights, "dailyCheckins": checkins, "observations": observations, "personalRecords": records, "aiCalls": calls, "memories": memories, "chatMessages": messages, "chatSummaries": summaries, "suggestions": suggestions, "coachNotes": notes, "weeklySummaries": weekly]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    static func restore(data: Data, into context: ModelContext, defaults: UserDefaults = .standard) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let version = root["version"] as? Int else { throw BackupError.invalidFormat }
        guard version <= 4 else { throw BackupError.unsupportedVersion(version) }
        let df = ISO8601DateFormatter()
        func rows(_ key: String) -> [[String: Any]] { root[key] as? [[String: Any]] ?? [] }
        func date(_ x: Any?) -> Date? { (x as? String).flatMap(df.date) }
        func str(_ x: Any?) -> String? { x as? String }
        func dbl(_ x: Any?) -> Double? { x as? Double ?? (x as? NSNumber)?.doubleValue }
        func int(_ x: Any?) -> Int? { x as? Int ?? (x as? NSNumber)?.intValue }
        func id(_ x: Any?) -> UUID? { (x as? String).flatMap(UUID.init(uuidString:)) }
        func clear<T: PersistentModel>(_ type: T.Type) { (try? context.fetch(FetchDescriptor<T>()))?.forEach(context.delete) }
        clear(UserProfile.self); clear(StoredPlan.self); clear(ProviderProfile.self); clear(CustomExerciseModel.self); clear(AICallRecord.self); clear(LoggedSetModel.self); clear(CompletedEntryModel.self); clear(CompletedSessionModel.self); clear(BodyweightEntryModel.self); clear(DailyCheckinModel.self); clear(ObservationModel.self); clear(PersonalRecordModel.self); clear(CoachMemoryModel.self); clear(ChatMessageModel.self); clear(ChatSummaryModel.self); clear(PendingCoachSuggestion.self); clear(CoachNoteModel.self); clear(WeeklySummaryModel.self)
        for p in rows("providers") {
            guard let name = str(p["displayName"]), let kind = str(p["adapterKindRaw"]), let model = str(p["modelID"]) else { continue }
            let x = ProviderProfile(displayName: name, adapterKind: AdapterKind(rawValue: kind) ?? .openAICompatible,
                baseURL: str(p["baseURL"]), modelID: model, apiKeyRef: nil,
                supportsVision: p["supportsVision"] as? Bool ?? false, pricePerMTokIn: dbl(p["pricePerMTokIn"]) ?? 0,
                pricePerMTokOut: dbl(p["pricePerMTokOut"]) ?? 0, pricePerMTokCached: dbl(p["pricePerMTokCached"]) ?? 0)
            x.isActive = p["isActive"] as? Bool ?? false; x.fallbackProfileID = id(p["fallbackProfileID"]); x.capToolCallingRaw = str(p["capToolCallingRaw"]); if let d = date(p["createdAt"]) { x.createdAt = d }; if let restoredID = id(p["id"]) { x.id = restoredID }; context.insert(x)
        }
        for p in rows("plans") { guard let generated = date(p["generatedAt"]), let week = date(p["weekStartDate"]), let encoded = str(p["planJSON"]), let json = Data(base64Encoded: encoded) else { continue }; context.insert(StoredPlan(generatedAt: generated, weekStartDate: week, planJSON: json, hadValidationIssues: p["hadValidationIssues"] as? Bool ?? false)) }
        for c in rows("customExercises") { guard let name = str(c["name"]), let muscle = MuscleGroup(rawValue: str(c["primaryMuscleRaw"]) ?? ""), let equipment = Equipment(rawValue: str(c["equipmentRaw"]) ?? "") else { continue }; let x = CustomExerciseModel(id: id(c["id"]) ?? UUID(), name: name, primaryMuscle: muscle, equipment: equipment, secondaryMuscles: (c["secondaryMuscleRaws"] as? [String] ?? []).compactMap(MuscleGroup.init(rawValue:)), mechanic: Mechanic(rawValue: str(c["mechanicRaw"]) ?? "") ?? .compound, force: str(c["forceRaw"]).flatMap(ForceType.init(rawValue:)), difficulty: Difficulty(rawValue: str(c["difficultyRaw"]) ?? "") ?? .intermediate, isUnilateral: c["isUnilateral"] as? Bool ?? false, instructions: str(c["instructions"]) ?? "", photoFilename: str(c["photoFilename"])); if let created = date(c["createdAt"]) { x.createdAt = created }; if let updated = date(c["updatedAt"]) { x.updatedAt = updated }; context.insert(x) }
        for p in rows("profiles") { guard let goal = str(p["goalRaw"]), let experience = str(p["experienceRaw"]), let height = dbl(p["heightCm"]), let weight = dbl(p["weightKg"]), let year = int(p["birthYear"]), let sex = str(p["sexRaw"]), let count = int(p["sessionsPerWeek"]), let length = int(p["sessionLengthMinutes"]) else { continue }; let x = UserProfile(goalRaw: goal, experienceRaw: experience, heightCm: height, weightKg: weight, birthYear: year, sexRaw: sex, sessionsPerWeek: count, sessionLengthMinutes: length, availableEquipmentRaws: p["availableEquipmentRaws"] as? [String] ?? [], excludedMuscleRaws: p["excludedMuscleRaws"] as? [String] ?? [], excludedExerciseIDs: p["excludedExerciseIDs"] as? [String] ?? []); x.splitTemplateName = str(p["splitTemplateName"]); x.bodyFatPercent = dbl(p["bodyFatPercent"]); x.skeletalMuscleMassKg = dbl(p["skeletalMuscleMassKg"]); x.bodyFatMassKg = dbl(p["bodyFatMassKg"]); x.fatFreeMassKg = dbl(p["fatFreeMassKg"]); x.totalBodyWaterL = dbl(p["totalBodyWaterL"]); x.proteinKg = dbl(p["proteinKg"]); x.mineralKg = dbl(p["mineralKg"]); x.basalMetabolicRateKcal = dbl(p["basalMetabolicRateKcal"]); x.visceralFatLevel = dbl(p["visceralFatLevel"]); x.inBodyScore = dbl(p["inBodyScore"]); x.waistHipRatio = dbl(p["waistHipRatio"]); x.phaseAngleDegrees = dbl(p["phaseAngleDegrees"]); if let d = date(p["createdAt"]) { x.createdAt = d }; if let d = date(p["updatedAt"]) { x.updatedAt = d }; context.insert(x) }
        for b in rows("bodyweight") { guard let d = date(b["date"]), let kg = dbl(b["kg"]) else { continue }; context.insert(BodyweightEntryModel(date: d, kg: kg, morningKg: dbl(b["morningKg"]), nightKg: dbl(b["nightKg"]))) }
        for c in rows("dailyCheckins") { guard let d = date(c["date"]) else { continue }; let x = DailyCheckinModel(date: d); x.sleepQuality = int(c["sleepQuality"]); x.soreness = int(c["soreness"]); x.note = str(c["note"]); context.insert(x) }
        for o in rows("observations") { guard let kind = str(o["kind"]), let value = dbl(o["value"]), let unit = str(o["unit"]), let d = date(o["timestamp"]) else { continue }; let x = ObservationModel(kind: kind, value: value, unit: unit, timestamp: d); x.contextJSON = str(o["contextJSON"]) ?? "{}"; x.sessionID = id(o["sessionID"]); x.entryExerciseID = str(o["entryExerciseID"]); x.confirmed = o["confirmed"] as? Bool ?? true; context.insert(x) }
        for s in rows("workouts") { guard let sid = id(s["id"]), let started = date(s["startedAt"]) else { continue }; let x = CompletedSessionModel(id: sid, startedAt: started, weekdayRaw: int(s["weekdayRaw"]) ?? 1, timeOfDayMinutes: int(s["timeOfDayMinutes"]) ?? 0, plannedDurationMin: int(s["plannedDurationMin"]) ?? 0, energyRaw: str(s["energyRaw"]) ?? "normal", timeAvailableMin: int(s["timeAvailableMin"]) ?? 0, plannedSessionID: id(s["plannedSessionID"])); x.finishedAt = date(s["finishedAt"]); x.actualDurationMin = int(s["actualDurationMin"]) ?? 0; x.outcomeRaw = str(s["outcomeRaw"]); x.partialReasonRaw = str(s["partialReasonRaw"]); x.coachSourceRaw = str(s["coachSourceRaw"]) ?? "rule"; x.overallNote = str(s["overallNote"]); x.importSource = str(s["importSource"]); x.importSourceID = str(s["importSourceID"]); context.insert(x); for e in s["entries"] as? [[String: Any]] ?? [] { let entry = CompletedEntryModel(exerciseID: str(e["exerciseID"]) ?? "", performedOrder: int(e["performedOrder"]) ?? 0); entry.stateRaw = str(e["stateRaw"]) ?? entry.stateRaw; entry.skipped = e["skipped"] as? Bool ?? false; entry.wasSwappedFrom = str(e["wasSwappedFrom"]); entry.feelRaw = str(e["feelRaw"]); entry.note = str(e["note"]); entry.session = x; context.insert(entry); x.entries.append(entry); for z in e["sets"] as? [[String: Any]] ?? [] { guard let a = date(z["startedAt"]), let c = date(z["completedAt"]) else { continue }; let set = LoggedSetModel(targetReps: int(z["targetReps"]) ?? 0, targetLoadKg: dbl(z["targetLoadKg"]), actualReps: int(z["actualReps"]) ?? 0, actualLoadKg: dbl(z["actualLoadKg"]) ?? 0, startedAt: a, completedAt: c, restBeforeSec: int(z["restBeforeSec"]) ?? 0, rpe: dbl(z["rpe"]), rir: dbl(z["rir"]), heldSec: int(z["heldSec"]), isWarmup: z["isWarmup"] as? Bool ?? false, isDropSet: z["isDropSet"] as? Bool ?? false, toFailure: z["toFailure"] as? Bool ?? false, assisted: z["assisted"] as? Bool ?? false); set.dropsJSON = str(z["dropsJSON"]) ?? "[]"; set.clustersJSON = str(z["clustersJSON"]) ?? "[]"; set.entry = entry; context.insert(set); entry.sets.append(set) } } }
        for c in rows("aiCalls") { guard let time = date(c["timestamp"]), let callType = str(c["callType"]), let provider = str(c["providerDisplayName"]), let model = str(c["modelID"]) else { continue }; let x = AICallRecord(callType: callType, providerDisplayName: provider, modelID: model, inputTokens: int(c["inputTokens"]) ?? 0, outputTokens: int(c["outputTokens"]) ?? 0, cachedTokens: int(c["cachedTokens"]) ?? 0, costUSD: dbl(c["costUSD"]) ?? 0, success: c["success"] as? Bool ?? false, usedFallback: c["usedFallback"] as? Bool ?? false); x.timestamp = time; context.insert(x) }
        for m in rows("memories") { guard let statement = str(m["statement"]), let kind = str(m["kindRaw"]), let source = str(m["sourceKind"]), let created = date(m["createdAt"]), let confirmed = date(m["lastConfirmedAt"]) else { continue }; let x = CoachMemoryModel(id: id(m["id"]) ?? UUID(), kindRaw: kind, statement: statement, confidence: dbl(m["confidence"]) ?? 0, sourceKind: source, createdAt: created, lastConfirmedAt: confirmed); x.action = str(m["action"]); x.sourceAgent = str(m["sourceAgent"]); x.supersededBy = id(m["supersededBy"]); x.retiredByCap = m["retiredByCap"] as? Bool ?? false; x.outcomeScore = dbl(m["outcomeScore"]); x.tagExerciseID = str(m["tagExerciseID"]); x.tagMuscleRaw = str(m["tagMuscleRaw"]); x.tagEquipmentRaw = str(m["tagEquipmentRaw"]); x.tagFreeJSON = str(m["tagFreeJSON"]) ?? "[]"; context.insert(x) }
        for m in rows("chatMessages") { guard let role = str(m["role"]), let text = str(m["text"]), let time = date(m["timestamp"]) else { continue }; let x = ChatMessageModel(role: role, text: text, timestamp: time); if let restoredID = id(m["id"]) { x.id = restoredID }; context.insert(x) }
        for s in rows("chatSummaries") { guard let text = str(s["text"]), let updated = date(s["updatedAt"]) else { continue }; let x = ChatSummaryModel(); x.text = text; x.updatedAt = updated; x.messagesCoveredThrough = date(s["messagesCoveredThrough"]); context.insert(x) }
        for s in rows("suggestions") { guard let planned = id(s["plannedSessionID"]), let kind = str(s["kind"]), let exercise = str(s["exerciseID"]), let rationale = str(s["rationale"]), let source = str(s["source"]) else { continue }; let x = PendingCoachSuggestion(plannedSessionID: planned, kind: kind, exerciseID: exercise, rationale: rationale, source: source); if let restoredID = id(s["id"]) { x.id = restoredID }; x.replacementExerciseID = str(s["replacementExerciseID"]); x.targetSets = int(s["targetSets"]); x.targetRepsMin = int(s["targetRepsMin"]); x.targetRepsMax = int(s["targetRepsMax"]); x.targetLoadKg = dbl(s["targetLoadKg"]); if let created = date(s["createdAt"]) { x.createdAt = created }; x.resolvedAt = date(s["resolvedAt"]); x.accepted = s["accepted"] as? Bool; x.sourceMemoryID = id(s["sourceMemoryID"]); context.insert(x) }
        for n in rows("coachNotes") { guard let kind = str(n["kindRaw"]), let text = str(n["text"]), let created = date(n["createdAt"]) else { continue }; let x = CoachNoteModel(kindRaw: kind, text: text, reason: str(n["reason"]), topicRaw: str(n["topicRaw"]), createdAt: created); x.readAt = date(n["readAt"]); if let restoredID = id(n["id"]) { x.id = restoredID }; context.insert(x) }
        for w in rows("weeklySummaries") { guard let start = date(w["weekStartDate"]), let headline = str(w["headline"]), let body = str(w["summaryBody"]), let focus = str(w["nextWeekFocus"]) else { continue }; let x = WeeklySummaryModel(weekStartDate: start, headline: headline, summaryBody: body, nextWeekFocus: focus); if let generated = date(w["generatedAt"]) { x.generatedAt = generated }; context.insert(x) }
        for key in preferenceKeys { defaults.removeObject(forKey: key) }; if let preferences = root["preferences"] as? [String: Any] { for (key, value) in preferences where preferenceKeys.contains(key) { defaults.set(value, forKey: key) } }
        do { try context.save() } catch { throw BackupError.saveFailed(error) }
    }

    static func reset(context: ModelContext, defaults: UserDefaults = .standard) throws {
        if let providers = try? context.fetch(FetchDescriptor<ProviderProfile>()) {
            for provider in providers {
                if let account = provider.apiKeyRef { try? KeychainStore.delete(account: account) }
            }
        }
        if let custom = try? context.fetch(FetchDescriptor<CustomExerciseModel>()) { custom.forEach { CustomExercisePhotoStore.delete(filename: $0.photoFilename) } }
        let types: [any PersistentModel.Type] = [UserProfile.self, StoredPlan.self, ProviderProfile.self, CustomExerciseModel.self, AICallRecord.self, CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self, BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self, PersonalRecordModel.self, CoachMemoryModel.self, ChatMessageModel.self, ChatSummaryModel.self, PendingCoachSuggestion.self, CoachNoteModel.self, WeeklySummaryModel.self]
        for type in types { try context.delete(model: type) }
        for key in preferenceKeys { defaults.removeObject(forKey: key) }
        defaults.removeObject(forKey: "hevy_api_key") // legacy pre-Keychain storage
        try? KeychainStore.delete(account: "hevy-api-key")
        try? KeychainStore.delete(account: "openai-api-key")
        try? KeychainStore.delete(account: "openrouter-api-key")
        try context.save()
    }
}
