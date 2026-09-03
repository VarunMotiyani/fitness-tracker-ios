import Foundation

public enum RepRangeNormalize {
    /// Upper defaults to 10; lower defaults to max(1, upper - 2). Both ceil-aligned to
    /// `stride` (stride 2 for per-side). If lower >= upper, returns (repsMin: lower, reps: lower + stride).
    public static func normalize(reps: Int?, repsMin: Int?, stride: Int = 1) -> (repsMin: Int, reps: Int) {
        let step = stride > 0 ? stride : 1
        let repVal = (reps ?? 0) > 0 ? reps! : 10
        let upper = align(repVal, stride: step)
        let minVal = (repsMin ?? 0) > 0 ? repsMin! : max(1, upper - 2)
        let lower = align(minVal, stride: step)

        if lower >= upper {
            return (repsMin: lower, reps: lower + step)
        }
        return (repsMin: lower, reps: upper)
    }

    private static func align(_ value: Int, stride: Int) -> Int {
        let ceilSteps = Int(ceil(Double(value) / Double(stride)))
        return max(stride, ceilSteps * stride)
    }
}
