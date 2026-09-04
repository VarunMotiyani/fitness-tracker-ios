import Foundation

/// Which exercise-media dataset the Library is browsing. Two sources ship in the app so
/// they can be compared directly instead of just taking one on faith:
///
/// - `gymVisual`: `catalog.json`, 1,324 exercises, hotlinked from
///   `hasaneyldrm/exercises-dataset` on jsdelivr. Its own `LICENSE`/`README` say the
///   media is "© Gym visual" and that "cloning this repository does not grant you any
///   license to the media" — redistribution/reuse needs a license bought directly from
///   gymvisual.com. Animated GIFs, higher exercise count.
/// - `freeStatic`: `free_exercise_db.json`, 876 exercises, from `yuhonas/free-exercise-db`
///   — Unlicense (public domain), no attribution required. Static photos only, no GIFs.
public enum ExerciseMediaSource: String {
    case gymVisual = "gymvisual"
    case freeStatic = "free_static"
}
