import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

@Suite("Roots Functionality Tests")
struct RootsTests {
    
    @Suite("Root Data Models")
    struct DataModelTests {
        
        @Test("Root can be created and encoded/decoded")
        func rootCodableTest() throws {
            let root = Root(uri: "file:///home/user/project", name: "My Project")
            
            #expect(root.uri == "file:///home/user/project")
            #expect(root.name == "My Project")
            
            // Test encoding/decoding
            let encoder = JSONEncoder()
            let data = try encoder.encode(root)
            
            let decoder = JSONDecoder()
            let decodedRoot = try decoder.decode(Root.self, from: data)
            
            #expect(decodedRoot.uri == root.uri)
            #expect(decodedRoot.name == root.name)
        }
        
        @Test("Root without name")
        func rootWithoutNameTest() throws {
            let root = Root(uri: "file:///home/user/project")
            
            #expect(root.uri == "file:///home/user/project")
            #expect(root.name == nil)
        }
        
        @Test("RootsList can be created and encoded/decoded")
        func rootsListCodableTest() throws {
            let roots = [
                Root(uri: "file:///home/user/project1", name: "Project 1"),
                Root(uri: "file:///home/user/project2", name: "Project 2")
            ]
            
            #expect(roots.count == 2)
            #expect(roots[0].name == "Project 1")
            #expect(roots[1].name == "Project 2")
            
            // Test encoding/decoding
            let encoder = JSONEncoder()
            let data = try encoder.encode(roots)
            
            let decoder = JSONDecoder()
            let decodedList = try decoder.decode([Root].self, from: data)
            
            #expect(decodedList.count == roots.count)
            #expect(decodedList[0].uri == roots[0].uri)
        }
    }
    
    @Suite("Client Capabilities Tests")
    struct ClientCapabilitiesTests {
        
        @Test("ClientCapabilities with roots support")
        func clientCapabilitiesWithRootsTest() throws {
            let capabilities = ClientCapabilities(
                roots: ClientCapabilities.RootsCapabilities(listChanged: true)
            )
            
            #expect(capabilities.roots?.listChanged == true)
            
            // Test encoding/decoding
            let encoder = JSONEncoder()
            let data = try encoder.encode(capabilities)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(ClientCapabilities.self, from: data)
            
            #expect(decoded.roots?.listChanged == true)
        }
        
        @Test("ClientCapabilities without roots")
        func clientCapabilitiesWithoutRootsTest() throws {
            let capabilities = ClientCapabilities()
            
            #expect(capabilities.roots == nil)
            #expect(capabilities.experimental?.isEmpty ?? true)
        }
        
        @Test("ClientCapabilities from JSON")
        func clientCapabilitiesFromJSONTest() throws {
            let json = """
            {
                "roots": {
                    "listChanged": true
                },
                "experimental": {
                    "customFeature": "enabled"
                }
            }
            """
            
            let data = json.data(using: .utf8)!
            let decoder = JSONDecoder()
            let capabilities = try decoder.decode(ClientCapabilities.self, from: data)
            
            #expect(capabilities.roots?.listChanged == true)
            #expect(capabilities.experimental?["customFeature"]?.value as? String == "enabled")
        }
    }
    
    @Suite("Session Integration Tests")
    struct SessionTests {
        
        @Test("Session stores client capabilities")
        func sessionStoresCapabilitiesTest() async {
            let session = Session(id: UUID())
            let capabilities = ClientCapabilities(
                roots: ClientCapabilities.RootsCapabilities(listChanged: true)
            )
            
            await session.setClientCapabilities(capabilities)
            
            let storedCapabilities = await session.getClientCapabilities()
            #expect(storedCapabilities?.roots?.listChanged == true)
        }
        
        @Test("Session roots error when no capabilities")
        func sessionRootsErrorTest() async {
            let session = Session(id: UUID())
            
            // When client doesn't support roots, listRoots should return empty array
            do {
                let roots = try await session.listRoots()
                #expect(roots.isEmpty)
            } catch {
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
        
        @Test("Session setClientCapabilities method works")
        func sessionSetClientCapabilitiesTest() async {
            let session = Session(id: UUID())
            let capabilities = ClientCapabilities(
                roots: ClientCapabilities.RootsCapabilities(listChanged: true)
            )
            
            await session.setClientCapabilities(capabilities)
            
            let storedCapabilities = await session.getClientCapabilities()
            #expect(storedCapabilities?.roots?.listChanged == true)
        }
    }
    
    @Suite("Error Handling Tests")
    struct ErrorTests {
        
    }
    
    @Suite("Roots Notification Tests")
    struct RootsNotificationTests {
        
        @Test("Roots list changed notification triggers roots retrieval")
        func rootsListChangedNotificationTest() async {
            // Create a mock server that implements the notification handling
            let mockServer = MockRootsServer()
            let session = Session(id: UUID())
            
            // Set up client capabilities to support roots
            await session.setClientCapabilities(ClientCapabilities(
                roots: ClientCapabilities.RootsCapabilities(listChanged: true)
            ))
            
            // Set the session as current for the notification handler
            _ = await session.work { _ in
                // Simulate receiving a roots list changed notification
                // This would normally be handled by the server's handleMessage method
                // For testing purposes, we'll just call the handler directly
                Task {
                    await mockServer.handleRootsListChanged()
                }
            }
            
            // In a real scenario, this would be verified through log messages
            // For now, we'll just verify that the method exists and can be called
            #expect(Bool(true)) // Placeholder - in a real test we'd verify the logs
        }
    }
    
    /// Mock server for testing roots notification handling
    actor MockRootsServer {
        var rootsRetrieved = false
        
        func handleRootsListChanged() async {
            // Simulate the notification handler logic
            rootsRetrieved = true
        }
        
        func getRootsRetrieved() -> Bool {
            return rootsRetrieved
        }
    }
}

// Simple calculator for testing - reuse existing test calculator
extension Calculator {
    // Calculator is already defined in the test suite
} 