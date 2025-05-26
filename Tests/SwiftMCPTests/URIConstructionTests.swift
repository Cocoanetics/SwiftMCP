import XCTest
import SwiftMCP

final class URIConstructionTests: XCTestCase {
    
    func testSimpleVariableConstruction() throws {
        let template = "users://{user_id}/profile"
        let parameters: [String: Sendable] = ["user_id": "123"]
        
        let constructedURI = try template.constructURI(with: parameters)
        
        XCTAssertEqual(constructedURI.absoluteString, "users://123/profile")
    }
    
    func testQueryParameterConstruction() throws {
        let template = "users://{user_id}/profile?locale={lang}"
        let parameters: [String: Sendable] = ["user_id": "456", "lang": "fr"]
        
        let constructedURI = try template.constructURI(with: parameters)
        
        XCTAssertEqual(constructedURI.absoluteString, "users://456/profile?locale=fr")
    }
    
    func testMultipleSimpleVariables() throws {
        let template = "api://{version}/{resource}/{id}"
        let parameters: [String: Sendable] = ["version": "v1", "resource": "users", "id": "789"]
        
        let constructedURI = try template.constructURI(with: parameters)
        
        XCTAssertEqual(constructedURI.absoluteString, "api://v1/users/789")
    }
    
    func testReservedExpansion() throws {
        let template = "files://{+path}"
        let parameters: [String: Sendable] = ["path": "documents/folder/file.txt"]
        
        let constructedURI = try template.constructURI(with: parameters)
        
        XCTAssertEqual(constructedURI.absoluteString, "files://documents/folder/file.txt")
    }
    
    func testPathSegmentExpansion() throws {
        let template = "api://{/segments}"
        let parameters: [String: Sendable] = ["segments": "v1,users,123"]
        
        let constructedURI = try template.constructURI(with: parameters)
        
        XCTAssertEqual(constructedURI.absoluteString, "api:///v1/users/123")
    }
    
    func testLabelExpansion() throws {
        let template = "api://example.com{.format}"
        let parameters: [String: Sendable] = ["format": "json"]
        
        let constructedURI = try template.constructURI(with: parameters)
        
        XCTAssertEqual(constructedURI.absoluteString, "api://example.com.json")
    }
    
    func testFragmentExpansion() throws {
        let template = "page://document{#section}"
        let parameters: [String: Sendable] = ["section": "introduction"]
        
        let constructedURI = try template.constructURI(with: parameters)
        
        XCTAssertEqual(constructedURI.absoluteString, "page://document#introduction")
    }
    
    func testMissingOptionalParameter() throws {
        let template = "users://{user_id}/profile?locale={lang}"
        let parameters: [String: Sendable] = ["user_id": "123"]
        
        let constructedURI = try template.constructURI(with: parameters)
        
        // Should construct without the optional query parameter
        XCTAssertEqual(constructedURI.absoluteString, "users://123/profile")
    }
    
    func testIntegerParameter() throws {
        let template = "users://{user_id}/posts/{post_id}"
        let parameters: [String: Sendable] = ["user_id": 123, "post_id": 456]
        
        let constructedURI = try template.constructURI(with: parameters)
        
        XCTAssertEqual(constructedURI.absoluteString, "users://123/posts/456")
    }
    
    func testBooleanParameter() throws {
        let template = "settings://notifications?enabled={enabled}"
        let parameters: [String: Sendable] = ["enabled": true]
        
        let constructedURI = try template.constructURI(with: parameters)
        
        XCTAssertEqual(constructedURI.absoluteString, "settings://notifications?enabled=true")
    }
} 