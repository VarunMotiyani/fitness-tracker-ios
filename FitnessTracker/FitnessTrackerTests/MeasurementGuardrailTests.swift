import Testing
@testable import FitnessTracker

@Suite struct MeasurementGuardrailTests {
    @Test func acceptsPlausibleBodyweight() {
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 82.5, unit: "kg"))
    }

    @Test func rejectsImplausibleBodyweight() {
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 900, unit: "kg"))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: -5, unit: "kg"))
    }

    @Test func acceptsPlausibleBodyFatPercent() {
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyFatPercent", value: 18.2, unit: "%"))
    }

    @Test func rejectsImplausibleBodyFatPercent() {
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyFatPercent", value: 95, unit: "%"))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyFatPercent", value: 0, unit: "%"))
    }

    @Test func acceptsPlausibleMuscleMass() {
        #expect(MeasurementGuardrail.isPlausible(kind: "muscleMassKg", value: 35, unit: "kg"))
    }

    @Test func rejectsUnknownKind() {
        #expect(!MeasurementGuardrail.isPlausible(kind: "shoeSize", value: 10, unit: "kg"))
    }

    @Test func acceptsInclusiveBoundsAndRejectsJustOutside() {
        // Bounds are inclusive (ClosedRange) of the extremes but must still
        // reject values just outside them.
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 30, unit: "kg"))
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 300, unit: "kg"))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 29.9, unit: "kg"))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 300.1, unit: "kg"))
    }

    @Test func rejectsMismatchedUnit() {
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 180, unit: "lb"))
    }
}
