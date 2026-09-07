import Testing
import Foundation
@testable import FitnessDomain

@Suite("CSV and App Import Tests")
struct CSVImportTests {
    @Test("CSVParser parses quoted fields and embedded commas")
    func testCSVParserQuotes() {
        let csv = #"""
"Exercise","Weight, kg","Reps"
"Bench Press, Close Grip","80.0","8"
"Squat ""Olympic""","120.5","5"
"""#
        let rows = CSVParser.parse(csv)
        #expect(rows.count == 3)
        #expect(rows[0] == ["Exercise", "Weight, kg", "Reps"])
        #expect(rows[1] == ["Bench Press, Close Grip", "80.0", "8"])
        #expect(rows[2] == ["Squat \"Olympic\"", "120.5", "5"])
    }

    @Test("ExternalAppImporter detects Hevy CSV and groups sessions")
    func testHevyImport() {
        let hevyCSV = #"""
title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
"Push Day","2026-08-15 10:00:00","2026-08-15 11:00:00","Solid","Barbell Bench Press",,"Felt good",0,"normal",80.0,8,,,8.0
"Push Day","2026-08-15 10:00:00","2026-08-15 11:00:00","Solid","Barbell Bench Press",,"Felt good",1,"normal",80.0,8,,,8.5
"Push Day","2026-08-15 10:00:00","2026-08-15 11:00:00","Solid","Incline Dumbbell Press",,,"0","warmup",20.0,12,,,
"""#
        let (source, sessions) = ExternalAppImporter.importCSV(hevyCSV)
        #expect(source == .hevy)
        #expect(sessions.count == 1)
        #expect(sessions[0].title == "Push Day")
        #expect(sessions[0].entries.count == 2)
        #expect(sessions[0].entries[0].exerciseName == "Barbell Bench Press")
        #expect(sessions[0].entries[0].sets.count == 2)
        #expect(sessions[0].entries[0].sets[0].weightKg == 80.0)
        #expect(sessions[0].entries[0].sets[0].reps == 8)
        #expect(sessions[0].entries[0].sets[0].rpe == 8.0)
        #expect(sessions[0].entries[1].exerciseName == "Incline Dumbbell Press")
        #expect(sessions[0].entries[1].sets[0].isWarmup == true)
    }

    @Test("ExternalAppImporter detects Strong CSV with pound conversion")
    func testStrongImport() {
        let strongCSV = #"""
Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
2026-08-18 18:30:00,Legs,45m,Barbell Squat,1,225,5,,,Felt heavy,,9
2026-08-18 18:30:00,Legs,45m,Barbell Squat,2,225,5,,,Felt heavy,,9.5
"""#
        let (source, sessions) = ExternalAppImporter.importCSV(strongCSV)
        #expect(source == .strong)
        #expect(sessions.count == 1)
        #expect(sessions[0].entries.count == 1)
        #expect(sessions[0].entries[0].sets.count == 2)
        #expect(sessions[0].entries[0].sets[0].reps == 5)
    }

    @Test("AppleHealthXMLImporter parses bodyweight records")
    func testAppleHealthImport() {
        let xml = #"""
<?xml version="1.0" encoding="UTF-8"?>
<HealthData>
    <Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Withings" unit="kg" startDate="2026-08-20 07:30:00 +0000" value="78.5"/>
    <Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Scale" unit="kg" startDate="2026-08-21 07:30:00 +0000" value="78.2"/>
</HealthData>
"""#
        let weights = AppleHealthXMLImporter.parse(xmlString: xml)
        #expect(weights.count == 2)
        #expect(weights[0].weightKg == 78.5)
        #expect(weights[1].weightKg == 78.2)
        #expect(weights[0].source == "Withings")
    }
}
