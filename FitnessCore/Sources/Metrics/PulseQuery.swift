import Foundation

public enum PulseQueryValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([PulseQueryValue])
    case object([String: PulseQueryValue])

    init(any: Any) {
        switch any {
        case let n as NSNumber:
            // NSNumber carries JSON booleans as 0/1 — check objCType to distinguish
            // an actual bool from a numeric 0/1.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let b as Bool: self = .bool(b)
        case let arr as [Any]: self = .array(arr.map(PulseQueryValue.init(any:)))
        case let dict as [String: Any]:
            self = .object(dict.mapValues(PulseQueryValue.init(any:)))
        case is NSNull: self = .null
        default: self = .null
        }
    }

    public var asAny: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let a): return a.map(\.asAny)
        case .object(let o): return o.mapValues(\.asAny)
        }
    }
}

public enum PulseQueryError: Error, Sendable, Equatable {
    case parseError(String)
    case evaluationError(String)
}

/// A small, dependency-free JMESPath-*inspired* subset — dot paths, `[]`
/// wildcard flatten, `[?field==value]` equality filters, and a handful of
/// pipe-applied functions (`length`, `max_by`, `sort_by`). Not a full
/// JMESPath clone: only what querying a personal-scale training-history JSON
/// export actually needs. See spec §4.4 (2026-09-05-ai-coach-layer-v2-design.md).
///
/// The wildcard flatten deliberately deviates from strict JMESPath in one
/// place for simplicity: chained wildcards (`a[].b[].c`) always flatten into
/// one flat array rather than JMESPath's more nuanced per-projection
/// flattening rules — the right call for a small, personal-use subset where
/// "give me every leaf value across this nested structure" is the only case
/// that comes up in practice.
public enum PulseQuery {
    public static func evaluate(_ query: String, against json: Data) throws -> PulseQueryValue {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed])
        } catch {
            throw PulseQueryError.parseError(error.localizedDescription)
        }
        let stages = query.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        var current = PulseQueryValue(any: root)
        for stage in stages {
            current = try apply(stage: stage, to: current)
        }
        return current
    }

    private static func apply(stage: String, to value: PulseQueryValue) throws -> PulseQueryValue {
        if stage.hasPrefix("length(") { return .number(Double(try length(of: value))) }
        if stage.hasPrefix("max_by(") { return try maxBy(value, field: try fieldArg(of: stage)) }
        if stage.hasPrefix("sort_by(") { return try sortBy(value, field: try fieldArg(of: stage)) }
        if stage.hasPrefix("[?") { return try filter(value, expression: stage) }
        let segments = stage.split(separator: ".").map(String.init)
        return try navigate(pathSegments: segments, from: value)
    }

    private static func fieldArg(of stage: String) throws -> String {
        // e.g. "max_by(@, &actualLoadKg)" -> "actualLoadKg"
        guard let ampIdx = stage.firstIndex(of: "&") else {
            throw PulseQueryError.evaluationError("expected &field in \(stage)")
        }
        let rest = stage[stage.index(after: ampIdx)...]
        return String(rest.prefix(while: { $0 != ")" }))
    }

    private static func length(of value: PulseQueryValue) throws -> Int {
        switch value {
        case .array(let a): return a.count
        case .string(let s): return s.count
        case .object(let o): return o.count
        default: throw PulseQueryError.evaluationError("length() needs array/string/object")
        }
    }

    private static func maxBy(_ value: PulseQueryValue, field: String) throws -> PulseQueryValue {
        guard case .array(let items) = value else {
            throw PulseQueryError.evaluationError("max_by needs an array")
        }
        let scored = items.compactMap { item -> (PulseQueryValue, Double)? in
            guard case .object(let obj) = item, case .number(let n)? = obj[field] else { return nil }
            return (item, n)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else {
            throw PulseQueryError.evaluationError("no numeric field '\(field)' found")
        }
        return best.0
    }

    private static func sortBy(_ value: PulseQueryValue, field: String) throws -> PulseQueryValue {
        guard case .array(let items) = value else {
            throw PulseQueryError.evaluationError("sort_by needs an array")
        }
        let sorted = items.sorted { lhs, rhs in
            guard case .object(let l) = lhs, case .object(let r) = rhs else { return false }
            switch (l[field], r[field]) {
            case (.number(let a)?, .number(let b)?): return a < b
            case (.string(let a)?, .string(let b)?): return a < b
            default: return false
            }
        }
        return .array(sorted)
    }

    private static func filter(_ value: PulseQueryValue, expression: String) throws -> PulseQueryValue {
        // "[?exerciseID=='0025']" or "[?targetSets==3]"
        guard let eqRange = expression.range(of: "==") else {
            throw PulseQueryError.evaluationError("only '==' filters are supported: \(expression)")
        }
        let fieldPart = expression[expression.index(expression.startIndex, offsetBy: 2)..<eqRange.lowerBound]
        let field = fieldPart.trimmingCharacters(in: .whitespaces)
        var rhs = expression[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
        rhs = String(rhs.dropLast()) // trailing ']'
        rhs = rhs.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))

        guard case .array(let items) = value else {
            throw PulseQueryError.evaluationError("filter needs an array")
        }
        let matches = items.filter { item in
            guard case .object(let obj) = item, let fieldValue = obj[field] else { return false }
            switch fieldValue {
            case .string(let s): return s == rhs
            case .number(let n): return n == Double(rhs)
            case .bool(let b): return b == (rhs == "true")
            default: return false
            }
        }
        return .array(matches)
    }

    /// Recursively walks dot-separated path segments. A segment like
    /// `entries[]` means "wildcard project": for each element of `entries`,
    /// continue evaluating the *remaining* segments against that element and
    /// collect the results. When those per-element results are themselves
    /// arrays (because a later segment was also a wildcard), they're
    /// flattened into one flat array rather than nested per outer element —
    /// see the type doc comment for why.
    private static func navigate(pathSegments: [String], from value: PulseQueryValue) throws -> PulseQueryValue {
        guard let first = pathSegments.first else { return value }
        let rest = Array(pathSegments.dropFirst())

        var seg = first
        var index: Int?
        var isWildcard = false

        if seg.hasSuffix("[]") {
            isWildcard = true
            seg = String(seg.dropLast(2))
        } else if seg.hasSuffix("]"), let bracketIdx = seg.firstIndex(of: "[") {
            let inside = seg[seg.index(after: bracketIdx)..<seg.index(before: seg.endIndex)]
            guard let parsedIndex = Int(inside) else {
                throw PulseQueryError.evaluationError("bad index in '\(seg)'")
            }
            index = parsedIndex
            seg = String(seg[..<bracketIdx])
        }

        var current = value
        if !seg.isEmpty {
            guard case .object(let obj) = current, let next = obj[seg] else {
                throw PulseQueryError.evaluationError("no field '\(seg)'")
            }
            current = next
        }

        if let index {
            guard case .array(let arr) = current, arr.indices.contains(index) else {
                throw PulseQueryError.evaluationError("index \(index) out of range")
            }
            return try navigate(pathSegments: rest, from: arr[index])
        }

        if isWildcard {
            guard case .array(let arr) = current else {
                throw PulseQueryError.evaluationError("[] on a non-array")
            }
            let mapped = try arr.map { try navigate(pathSegments: rest, from: $0) }
            if !mapped.isEmpty, mapped.allSatisfy({ if case .array = $0 { return true } else { return false } }) {
                let flattened = mapped.flatMap { (v: PulseQueryValue) -> [PulseQueryValue] in
                    if case .array(let inner) = v { return inner }
                    return [v]
                }
                return .array(flattened)
            }
            return .array(mapped)
        }

        return try navigate(pathSegments: rest, from: current)
    }
}
