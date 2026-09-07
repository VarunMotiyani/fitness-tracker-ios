import Foundation

/// Robust RFC 4180 compliant CSV parser.
/// Handles quoted fields, embedded newlines and commas, doubled-quote escapes, BOM, and CRLF line endings.
public enum CSVParser: Sendable {
    public static func parse(_ text: String) -> [[String]] {
        var clean = text
        if clean.hasPrefix("\u{FEFF}") {
            clean.removeFirst()
        }

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        var index = clean.startIndex
        while index < clean.endIndex {
            let char = clean[index]

            if inQuotes {
                if char == "\"" {
                    let nextIndex = clean.index(after: index)
                    if nextIndex < clean.endIndex && clean[nextIndex] == "\"" {
                        currentField.append("\"")
                        index = nextIndex
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == "," {
                    currentRow.append(currentField)
                    currentField = ""
                } else if char == "\r" || char == "\n" {
                    if char == "\r" {
                        let nextIndex = clean.index(after: index)
                        if nextIndex < clean.endIndex && clean[nextIndex] == "\n" {
                            index = nextIndex
                        }
                    }
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                } else {
                    currentField.append(char)
                }
            }

            index = clean.index(after: index)
        }

        currentRow.append(currentField)
        if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            rows.append(currentRow)
        }

        return rows
    }
}
