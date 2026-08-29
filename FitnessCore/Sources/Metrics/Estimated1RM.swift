public enum Estimated1RM {
    public static func epley(loadKg: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        if reps == 1 { return loadKg }
        return loadKg * (1 + Double(reps) / 30.0)
    }
}
