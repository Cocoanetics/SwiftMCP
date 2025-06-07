import Testing
@testable import SwiftMCP

// Define a helper function for tests
func constructURI(from template: String, with parameters: [String: String]) throws -> String {
    let sendableParams: [String: Sendable] = parameters.reduce(into: [:]) { result, pair in
        result[pair.key] = pair.value as Sendable
    }
    let url = try template.constructURI(with: sendableParams)
    return url.absoluteString
}

enum URIConstructionError: Error {
    case missingRequiredParameter(String)
    case invalidTemplate(String)
}

@Suite("URI Construction Tests", .tags(.uri, .unit))
struct URIConstructionTests {
    
    @Test("Basic URI construction with no parameters")
    func basicURIConstructionWithNoParameters() throws {
        let template = "https://api.example.com/users"
        let result = try constructURI(from: template, with: [:])
        #expect(result == "https://api.example.com/users")
    }
    
    @Test("URI construction with single parameter")
    func uriConstructionWithSingleParameter() throws {
        let template = "https://api.example.com/users/{id}"
        let parameters = ["id": "123"]
        let result = try constructURI(from: template, with: parameters)
        #expect(result == "https://api.example.com/users/123")
    }
    
    @Test("URI construction with multiple parameters")
    func uriConstructionWithMultipleParameters() throws {
        let template = "https://api.example.com/users/{userId}/posts/{postId}"
        let parameters = ["userId": "123", "postId": "456"]
        let result = try constructURI(from: template, with: parameters)
        #expect(result == "https://api.example.com/users/123/posts/456")
    }
    
    @Test("URI construction with query parameters")
    func uriConstructionWithQueryParameters() throws {
        let template = "https://api.example.com/users{?limit,offset}"
        let parameters = ["limit": "10", "offset": "20"]
        let result = try constructURI(from: template, with: parameters)
        #expect(result == "https://api.example.com/users?limit=10&offset=20")
    }
    
    @Test("URI construction with mixed path and query parameters")
    func uriConstructionWithMixedPathAndQueryParameters() throws {
        let template = "https://api.example.com/users/{id}{?include}"
        let parameters = ["id": "123", "include": "profile"]
        let result = try constructURI(from: template, with: parameters)
        #expect(result == "https://api.example.com/users/123?include=profile")
    }
    
    @Test("URI construction with URL encoding")
    func uriConstructionWithURLEncoding() throws {
        let template = "https://api.example.com/search{?q}"
        let parameters = ["q": "hello world"]
        let result = try constructURI(from: template, with: parameters)
        #expect(result == "https://api.example.com/search?q=hello%20world")
    }
    
    @Test("URI construction with missing required parameter removes placeholder")
    func uriConstructionWithMissingRequiredParameter() throws {
        let template = "https://api.example.com/users/{id}"
        let parameters: [String: String] = [:]
        
        // Current implementation removes the placeholder when parameter is missing
        let result = try constructURI(from: template, with: parameters)
        #expect(result == "https://api.example.com/users/")
    }
    
    @Test("URI construction with optional parameter omitted")
    func uriConstructionWithOptionalParameterOmitted() throws {
        let template = "https://api.example.com/users{?limit}"
        let parameters: [String: String] = [:]
        let result = try constructURI(from: template, with: parameters)
        #expect(result == "https://api.example.com/users")
    }
    
    @Test("URI construction with fragment")
    func uriConstructionWithFragment() throws {
        let template = "https://api.example.com/users/{id}#section"
        let parameters = ["id": "123"]
        let result = try constructURI(from: template, with: parameters)
        #expect(result == "https://api.example.com/users/123#section")
    }
    
    @Test("URI construction with complex template")
    func uriConstructionWithComplexTemplate() throws {
        let template = "https://api.example.com/v{version}/users/{userId}/posts{?limit,offset,sort}"
        let parameters = [
            "version": "2",
            "userId": "123",
            "limit": "10",
            "sort": "date"
        ]
        let result = try constructURI(from: template, with: parameters)
        #expect(result == "https://api.example.com/v2/users/123/posts?limit=10&sort=date")
    }
}

// MARK: - Test Tags Extension
extension Tag {
    @Tag static var uri: Self
} 