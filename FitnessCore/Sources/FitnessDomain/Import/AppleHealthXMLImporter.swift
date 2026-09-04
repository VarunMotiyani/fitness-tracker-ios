import Foundation

public struct ImportedBodyweight: Sendable, Codable, Equatable {
    public var date: Date
    public var weightKg: Double
    public var source: String?

    public init(date: Date, weightKg: Double, source: String? = nil) {
        self.date = date
        self.weightKg = weightKg
        self.source = source
    }
}

public final class AppleHealthXMLImporter: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var records: [ImportedBodyweight] = []
    private let dateFormatter: DateFormatter
    private let lbToKg: Double = 0.45359237

    public override init() {
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        self.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        super.init()
    }

    public static func parse(data: Data) -> [ImportedBodyweight] {
        let importer = AppleHealthXMLImporter()
        let parser = XMLParser(data: data)
        parser.delegate = importer
        parser.parse()
        return importer.records.sorted { $0.date < $1.date }
    }

    public static func parse(xmlString: String) -> [ImportedBodyweight] {
        guard let data = xmlString.data(using: .utf8) else { return [] }
        return parse(data: data)
    }

    // MARK: - XMLParserDelegate

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        guard elementName == "Record" else { return }
        guard attributeDict["type"] == "HKQuantityTypeIdentifierBodyMass" else { return }

        guard let valStr = attributeDict["value"], let rawVal = Double(valStr) else { return }
        let unitStr = attributeDict["unit"]?.lowercased() ?? "kg"
        let weightKg: Double
        if unitStr.contains("lb") {
            weightKg = rawVal * lbToKg
        } else {
            weightKg = rawVal
        }

        let dateStr = attributeDict["startDate"] ?? attributeDict["creationDate"] ?? ""
        let date = dateFormatter.date(from: dateStr) ?? Date()
        let source = attributeDict["sourceName"]

        records.append(ImportedBodyweight(date: date, weightKg: weightKg, source: source))
    }
}
