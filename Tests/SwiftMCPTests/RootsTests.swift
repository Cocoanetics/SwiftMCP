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
            let rootsList = RootsList(roots: roots)
            
            #expect(rootsList.roots.count == 2)
            #expect(rootsList.roots[0].name == "Project 1")
            #expect(rootsList.roots[1].name == "Project 2")
            
            // Test encoding/decoding
            let encoder = JSONEncoder()
            let data = try encoder.encode(rootsList)
            
            let decoder = JSONDecoder()
            let decodedList = try decoder.decode(RootsList.self, from: data)
            
            #expect(decodedList.roots.count == rootsList.roots.count)
            #expect(decodedList.roots[0].uri == rootsList.roots[0].uri)
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
            #expect(capabilities.experimental.isEmpty)
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
            #expect(capabilities.experimental["customFeature"]?.value as? String == "enabled")
        }
    }
    
    @Suite("Session Integration Tests")
    struct SessionTests {
        
        @Test("Session stores client capabilities")
        func sessionStoresCapabilitiesTest() {
            let session = Session(id: UUID())
            let capabilities = ClientCapabilities(
                roots: ClientCapabilities.RootsCapabilities(listChanged: true)
            )
            
            session.clientCapabilities = capabilities
            
            #expect(session.clientCapabilities?.roots?.listChanged == true)
        }
        
        @Test("Session roots error when no capabilities")
        func sessionRootsErrorTest() async {
            let session = Session(id: UUID())
            
            do {
                _ = try await session.listRoots()
                #expect(Bool(false), "Expected error to be thrown")
            } catch let error as RootsError {
                if case .clientDoesNotSupportRoots = error {
                    // Expected error
                } else {
                    #expect(Bool(false), "Unexpected error type")
                }
            } catch {
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
    }
    
    @Suite("Error Handling Tests")
    struct ErrorTests {
        
        @Test("RootsError descriptions")
        func rootsErrorDescriptionsTest() {
            let noSupportError = RootsError.clientDoesNotSupportRoots
            #expect(noSupportError.errorDescription == "Client does not support roots capability")
            
            let requestError = RootsError.requestFailed(TestError("test"))
            #expect(requestError.errorDescription?.contains("Roots request failed") == true)
        }
    }
}

// Simple calculator for testing - reuse existing test calculator
extension Calculator {
    // Calculator is already defined in the test suite
} 