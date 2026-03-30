import Foundation
import Testing
@testable import SwiftMCP

@Suite("Client Info Tests")
struct ClientInfoTests {

    @Suite("Implementation Data Model")
    struct ImplementationTests {

        @Test("Implementation can be created and encoded/decoded")
        func implementationCodableTest() throws {
            let implementation = Implementation(
                name: "TestClient",
                version: "1.0.0"
            )

            #expect(implementation.name == "TestClient")
            #expect(implementation.version == "1.0.0")
            #expect(implementation.title == nil)
            #expect(implementation.description == nil)
            #expect(implementation.icons == nil)
            #expect(implementation.websiteUrl == nil)

            let encoder = JSONEncoder()
            let data = try encoder.encode(implementation)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Implementation.self, from: data)

            #expect(decoded.name == implementation.name)
            #expect(decoded.version == implementation.version)
        }

        @Test("Implementation with all fields")
        func implementationAllFieldsTest() throws {
            let icon = Icon(src: URL(string: "https://example.com/icon.png")!, mimeType: "image/png")
            let implementation = Implementation(
                icons: [icon],
                name: "TestClient",
                title: "Test Client App",
                version: "2.1.0",
                description: "A test MCP client",
                websiteUrl: URL(string: "https://example.com")!
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(implementation)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Implementation.self, from: data)

            #expect(decoded.name == "TestClient")
            #expect(decoded.title == "Test Client App")
            #expect(decoded.version == "2.1.0")
            #expect(decoded.description == "A test MCP client")
            #expect(decoded.websiteUrl == URL(string: "https://example.com")!)
            #expect(decoded.icons?.count == 1)
            #expect(decoded.icons?.first?.src == URL(string: "https://example.com/icon.png")!)
        }

        @Test("Implementation from JSON")
        func implementationFromJSONTest() throws {
            let json = """
            {
                "name": "claude-desktop",
                "version": "0.5.0",
                "title": "Claude Desktop",
                "description": "Anthropic Claude Desktop Client"
            }
            """

            let data = json.data(using: .utf8)!
            let decoder = JSONDecoder()
            let implementation = try decoder.decode(Implementation.self, from: data)

            #expect(implementation.name == "claude-desktop")
            #expect(implementation.version == "0.5.0")
            #expect(implementation.title == "Claude Desktop")
            #expect(implementation.description == "Anthropic Claude Desktop Client")
        }
    }

    @Suite("Icon Data Model")
    struct IconTests {

        @Test("Icon can be created and encoded/decoded")
        func iconCodableTest() throws {
            let icon = Icon(src: URL(string: "https://example.com/icon.png")!)

            #expect(icon.src == URL(string: "https://example.com/icon.png")!)
            #expect(icon.mimeType == nil)
            #expect(icon.sizes == nil)
            #expect(icon.theme == nil)

            let encoder = JSONEncoder()
            let data = try encoder.encode(icon)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Icon.self, from: data)

            #expect(decoded.src == icon.src)
        }

        @Test("Icon with all fields")
        func iconAllFieldsTest() throws {
            let icon = Icon(
                src: URL(string: "https://example.com/icon.png")!,
                mimeType: "image/png",
                sizes: ["64x64", "128x128"],
                theme: .dark
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(icon)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Icon.self, from: data)

            #expect(decoded.src == URL(string: "https://example.com/icon.png")!)
            #expect(decoded.mimeType == "image/png")
            #expect(decoded.sizes == ["64x64", "128x128"])
            #expect(decoded.theme == .dark)
        }

        @Test("Icon.Size pixels encoding/decoding")
        func iconSizePixelsTest() throws {
            let size = Icon.Size.pixels(width: 64, height: 64)

            let encoder = JSONEncoder()
            let data = try encoder.encode(size)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Icon.Size.self, from: data)

            if case .pixels(let width, let height) = decoded {
                #expect(width == 64)
                #expect(height == 64)
            } else {
                Issue.record("Expected .pixels, got .any")
            }
        }

        @Test("Icon.Size any encoding/decoding")
        func iconSizeAnyTest() throws {
            let size = Icon.Size.any

            let encoder = JSONEncoder()
            let data = try encoder.encode(size)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Icon.Size.self, from: data)

            if case .any = decoded {
                // pass
            } else {
                Issue.record("Expected .any, got .pixels")
            }
        }

        @Test("Icon.Size from invalid string throws")
        func iconSizeInvalidTest() throws {
            let json = "\"invalid\""
            let data = json.data(using: .utf8)!
            let decoder = JSONDecoder()

            #expect(throws: DecodingError.self) {
                _ = try decoder.decode(Icon.Size.self, from: data)
            }
        }
    }

    @Suite("Session Integration Tests")
    struct SessionTests {

        @Test("Session stores client info")
        func sessionStoresClientInfoTest() async {
            let session = Session(id: UUID())
            let implementation = Implementation(
                name: "TestClient",
                version: "1.0.0"
            )

            await session.setClientInfo(implementation)

            let storedInfo = await session.clientInfo
            #expect(storedInfo?.name == "TestClient")
            #expect(storedInfo?.version == "1.0.0")
        }

        @Test("Session client info is nil by default")
        func sessionClientInfoNilTest() async {
            let session = Session(id: UUID())

            let storedInfo = await session.clientInfo
            #expect(storedInfo == nil)
        }

        @Test("Session setClientInfo method works")
        func sessionSetClientInfoTest() async {
            let session = Session(id: UUID())
            let implementation = Implementation(
                name: "TestClient",
                title: "Test Client App",
                version: "2.0.0",
                description: "A test client"
            )

            await session.setClientInfo(implementation)

            let storedInfo = await session.clientInfo
            #expect(storedInfo?.name == "TestClient")
            #expect(storedInfo?.title == "Test Client App")
            #expect(storedInfo?.version == "2.0.0")
            #expect(storedInfo?.description == "A test client")
        }
    }
}
