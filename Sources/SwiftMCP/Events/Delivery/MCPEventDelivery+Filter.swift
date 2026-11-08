#if Server
//
//  MCPEventDelivery+Filter.swift
//  SwiftMCP
//
//  Subscription filter matching for emit, with JSON-number equivalence.
//

import Foundation

extension MCPEventProviding {
    /// A subscription matches when each non-null filter entry equals the same-named
    /// attribute; numbers compare by JSON value across integer/unsigned/double cases.
    static func filter(_ filter: JSONValue, matches attributes: JSONValue) -> Bool {
        guard case .object(let wanted) = filter else { return true }
        let present = wanted.filter { $0.value != .null }
        if present.isEmpty { return true }
        guard case .object(let actual) = attributes else { return false }
        return present.allSatisfy { key, value in
            guard let observed = actual[key] else { return false }
            return jsonEqual(observed, value)
        }
    }

    /// JSON-value equality that treats integer / unsigned / double forms of the
    /// same number as equal, including nested objects and arrays.
    private static func jsonEqual(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
        if let left = numericValue(lhs), let right = numericValue(rhs) { return left == right }
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.bool(let left), .bool(let right)): return left == right
        case (.string(let left), .string(let right)): return left == right
        case (.array(let left), .array(let right)):
            return left.count == right.count && zip(left, right).allSatisfy(jsonEqual)
        case (.object(let left), .object(let right)):
            guard left.count == right.count else { return false }
            return left.allSatisfy { key, value in
                guard let other = right[key] else { return false }
                return jsonEqual(value, other)
            }
        default:
            return false
        }
    }

    private static func numericValue(_ value: JSONValue) -> Double? {
        switch value {
        case .integer(let int): return Double(int)
        case .unsignedInteger(let uint): return Double(uint)
        case .double(let double): return double
        default: return nil
        }
    }
}
#endif
