import Testing
@testable import FitnessTracker

@Suite struct MeasurementGuardrailTests {
    @Test func acceptsPlausibleBodyweight() {
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 82.5))
    }

    @Test func rejectsImplausibleBodyweight() {
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 900))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: -5))
    }

    @Test func acceptsPlausibleBodyFatPercent() {
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyFatPercent", value: 18.2))
    }

    @Test func rejectsImplausibleBodyFatPercent() {
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyFatPercent", value: 95))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyFatPercent", value: 0))
    }

    @Test func acceptsPlausibleMuscleMass() {
        #expect(MeasurementGuardrail.isPlausible(kind: "muscleMassKg", value: 35))
    }

    @Test func rejectsUnknownKind() {
        #expect(!MeasurementGuardrail.isPlausible(kind: "shoeSize", value: 10))
    }

    @Test func rejectsBoundaryValuesExactlyAtTheEdge() {
        // Bounds are exclusive of the implausible extremes but must still
        // accept realistic edge cases without off-by-one rejection.
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 30))
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 300))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 29.9))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 300.1))
    }
}
