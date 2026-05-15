import Foundation

enum ProxyDemoFormatter {

    static func formatValue(_ value: Any) -> String {
        formatValue(value, depth: 0)
    }

    static func formatValue(_ value: Any, depth: Int) -> String {
        if depth > 6 {
            return "\"<max-depth>\""
        }

        let mirrored = Mirror(reflecting: value)
        if mirrored.displayStyle == .optional {
            if let child = mirrored.children.first {
                return formatValue(child.value, depth: depth)
            }
            return "null"
        }

        if let primitive = formatPrimitive(value) {
            return primitive
        }

        switch mirrored.displayStyle {
        case .collection, .set:
            let items = mirrored.children.map { formatValue($0.value, depth: depth + 1) }
            return formatArray(items)
        case .dictionary:
            return formatDictionaryMirror(mirrored, depth: depth)
        case .struct, .class:
            return formatStructOrClass(mirrored, depth: depth)
        case .enum:
            return "\"\(escapeString(String(describing: value)))\""
        default:
            return "\"\(escapeString(String(describing: value)))\""
        }
    }

    private static func formatPrimitive(_ value: Any) -> String? {
        if let scalar = formatScalar(value) {
            return scalar
        }
        return formatFoundationLiteral(value)
    }

    private static func formatScalar(_ value: Any) -> String? {
        if let string = value as? String {
            return "\"\(escapeString(string))\""
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let int = value as? Int {
            return "\(int)"
        }
        if let number = value as? any BinaryInteger {
            return "\(number)"
        }
        if let double = value as? Double {
            return String(describing: double)
        }
        if let float = value as? Float {
            return String(describing: float)
        }
        if let decimal = value as? Decimal {
            return NSDecimalNumber(decimal: decimal).stringValue
        }
        return nil
    }

    private static func formatFoundationLiteral(_ value: Any) -> String? {
        if let date = value as? Date {
            return "Date(\"\(formatDate(date))\")"
        }
        if let url = value as? URL {
            return "URL(\"\(escapeString(url.absoluteString))\")"
        }
        if let uuid = value as? UUID {
            return "UUID(\"\(uuid.uuidString)\")"
        }
        if let data = value as? Data {
            return "Data(\"\(data.base64EncodedString())\")"
        }
        return nil
    }

    private static func formatDictionaryMirror(_ mirrored: Mirror, depth: Int) -> String {
        var pairs: [(String, String)] = []
        for child in mirrored.children {
            let pair = Mirror(reflecting: child.value).children.map { $0.value }
            guard pair.count == 2 else { continue }
            let key = formatDictionaryKey(pair[0])
            let value = formatValue(pair[1], depth: depth + 1)
            pairs.append((key, value))
        }
        return formatObject(pairs)
    }

    private static func formatStructOrClass(_ mirrored: Mirror, depth: Int) -> String {
        let fields = mirrored.children.compactMap { child -> (String, String)? in
            guard let label = child.label else { return nil }
            let value = formatValue(child.value, depth: depth + 1)
            return ("\"\(escapeString(label))\"", value)
        }
        return formatObject(fields)
    }

    static func formatDictionaryKey(_ value: Any) -> String {
        if let key = value as? String {
            return "\"\(escapeString(key))\""
        }
        return "\"\(escapeString(String(describing: value)))\""
    }

    static func formatArray(_ items: [String]) -> String {
        guard !items.isEmpty else {
            return "[]"
        }
        var lines: [String] = ["["]
        for (index, item) in items.enumerated() {
            let indented = indentMultiline(item, indent: "  ")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            if let last = indented.indices.last {
                var linesWithComma = indented
                if index < items.count - 1 {
                    linesWithComma[last] = "\(linesWithComma[last]),"
                }
                lines.append(contentsOf: linesWithComma)
            } else {
                lines.append("  \(item)")
            }
        }
        lines.append("]")
        return lines.joined(separator: "\n")
    }

    static func formatObject(_ fields: [(String, String)]) -> String {
        guard !fields.isEmpty else {
            return "{}"
        }
        var lines: [String] = ["{"]
        for (index, field) in fields.enumerated() {
            let (key, value) = field
            let valueLines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if valueLines.count == 1 {
                var line = "  \(key): \(valueLines[0])"
                if index < fields.count - 1 {
                    line += ","
                }
                lines.append(line)
            } else {
                let firstLine = "  \(key): \(valueLines[0])"
                lines.append(firstLine)
                for lineIndex in valueLines.indices.dropFirst() {
                    lines.append("  \(valueLines[lineIndex])")
                }
                if index < fields.count - 1, let lastIndex = lines.indices.last {
                    lines[lastIndex] += ","
                }
            }
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    static func indentMultiline(_ text: String, indent: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\(indent)\($0)" }
            .joined(separator: "\n")
    }

    static func escapeString(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        return escaped
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        return formatter.string(from: date)
    }
}
