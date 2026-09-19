import Foundation
import SwiftMCP

// How generated types get their names, and whether they can be Hashable.
extension OpenAPITypeRegistry {
    /// Names a generated type, and says whether that name already denotes it.
    ///
    /// A titled schema names its own type: a server that calls a shape "Ride"
    /// in three tools gets one `Ride`, not `ListRidesResponseItem`,
    /// `GetRideResponseRide` and `AcceptRideResponseRide`. Structural identity is
    /// what makes the sharing safe — the same title over a *different* shape
    /// means the server said two things were the same when they were not, and
    /// that gets a numbered name rather than a silently merged type. Shape is
    /// compared with descriptions stripped: the same fields documented two ways
    /// are still one type.
    ///
    /// Untitled schemas keep their positional names, so existing output is
    /// unchanged for servers that never set a title.
    func typeName(
        for schema: JSONSchema,
        title: String?,
        suggestedName: String
    ) -> (name: String, exists: Bool) {
        guard let title, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return (uniqueName(suggestedName), false)
        }
        let preferred = ProxyGenerator.pascalCase(title)
        let shape = schema.withoutDescriptions

        if shapes[preferred] == shape {
            return (preferred, true)
        }
        if !usedNames.contains(preferred) {
            usedNames.insert(preferred)
            shapes[preferred] = shape
            return (preferred, false)
        }
        // Taken, by a positional name or by a different shape under this title.
        var index = 2
        while usedNames.contains("\(preferred)\(index)") {
            if shapes["\(preferred)\(index)"] == shape {
                return ("\(preferred)\(index)", true)
            }
            index += 1
        }
        let name = "\(preferred)\(index)"
        usedNames.insert(name)
        shapes[name] = shape
        return (name, false)
    }

    func isHashable(_ typeName: String) -> Bool {
        var base = typeName
        while base.hasSuffix("?") { base.removeLast() }
        while base.hasPrefix("["), base.hasSuffix("]") { base = String(base.dropFirst().dropLast()) }
        if let known = hashable[base] { return known }
        return Self.hashablePrimitives.contains(base)
    }

    func uniqueName(_ name: String) -> String {
        if !usedNames.contains(name) {
            usedNames.insert(name)
            return name
        }
        var index = 2
        while usedNames.contains("\(name)\(index)") {
            index += 1
        }
        let result = "\(name)\(index)"
        usedNames.insert(result)
        return result
    }
}
