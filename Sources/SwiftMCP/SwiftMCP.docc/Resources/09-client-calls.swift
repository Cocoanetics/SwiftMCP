import SwiftMCP

do {
    let sum = try await client.add(a: 2, b: 3)
    let formatted = try await client.format(date: Date())
    print("Sum: \\(sum)")
    print("Date: \\(formatted)")
} catch {
    print("Client call failed: \\(error)")
}
