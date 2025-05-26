import Testing
import Foundation
@testable import SwiftMCP

@Suite("RFC 6570 URL Template Extraction")
struct RFC6570ExtractionTests {
    
    // MARK: - Level 1 Simple String Expansion Tests
    
    @Test("Simple variable extraction")
    func testSimpleVariableExtraction() {
        let template = "http://example.com/users/{user_id}"
        let url = URL(string: "http://example.com/users/123")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["user_id"] == "123")
    }
    
    @Test("Multiple simple variables")
    func testMultipleSimpleVariables() {
        let template = "http://example.com/users/{user_id}/posts/{post_id}"
        let url = URL(string: "http://example.com/users/123/posts/456")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["user_id"] == "123")
        #expect(variables?["post_id"] == "456")
    }
    
    @Test("Comma-separated variables")
    func testCommaSeparatedVariables() {
        let template = "http://example.com/map/{x,y}"
        let url = URL(string: "http://example.com/map/50,100")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["x"] == "50")
        #expect(variables?["y"] == "100")
    }
    
    // MARK: - Level 2 Reserved String Expansion Tests
    
    @Test("Reserved expansion with plus operator")
    func testReservedExpansion() {
        let template = "http://example.com/{+path}"
        let url = URL(string: "http://example.com/foo/bar")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["path"] == "foo/bar")
    }
    
    @Test("Fragment expansion")
    func testFragmentExpansion() {
        let template = "http://example.com/page{#section}"
        let url = URL(string: "http://example.com/page#introduction")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["section"] == "introduction")
    }
    
    // MARK: - Level 3 Multiple Variable Expansion Tests
    
    @Test("Label expansion with dot prefix")
    func testLabelExpansion() {
        let template = "http://example.com/file{.format}"
        let url = URL(string: "http://example.com/file.json")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["format"] == "json")
    }
    
    @Test("Multiple label expansion")
    func testMultipleLabelExpansion() {
        let template = "http://example.com/file{.type,format}"
        let url = URL(string: "http://example.com/file.text.json")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["type"] == "text")
        #expect(variables?["format"] == "json")
    }
    
    @Test("Path segment expansion")
    func testPathSegmentExpansion() {
        let template = "http://example.com{/path}"
        let url = URL(string: "http://example.com/foo")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["path"] == "foo")
    }
    
    @Test("Multiple path segment expansion")
    func testMultiplePathSegmentExpansion() {
        let template = "http://example.com{/path,subpath}"
        let url = URL(string: "http://example.com/foo/bar")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["path"] == "foo")
        #expect(variables?["subpath"] == "bar")
    }
    
    @Test("Path-style parameter expansion")
    func testPathStyleExpansion() {
        let template = "http://example.com/users{;id}"
        let url = URL(string: "http://example.com/users;id=123")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["id"] == "123")
    }
    
    @Test("Multiple path-style parameters")
    func testMultiplePathStyleExpansion() {
        let template = "http://example.com/users{;id,name}"
        let url = URL(string: "http://example.com/users;id=123;name=john")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["id"] == "123")
        #expect(variables?["name"] == "john")
    }
    
    @Test("Query expansion")
    func testQueryExpansion() {
        let template = "http://example.com/search{?q}"
        let url = URL(string: "http://example.com/search?q=test")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["q"] == "test")
    }
    
    @Test("Multiple query parameters")
    func testMultipleQueryExpansion() {
        let template = "http://example.com/search{?q,limit}"
        let url = URL(string: "http://example.com/search?q=test&limit=10")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["q"] == "test")
        #expect(variables?["limit"] == "10")
    }
    
    @Test("Query continuation")
    func testQueryContinuation() {
        let template = "http://example.com/search?fixed=value{&q,limit}"
        let url = URL(string: "http://example.com/search?fixed=value&q=test&limit=10")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["q"] == "test")
        #expect(variables?["limit"] == "10")
    }
    
    // MARK: - Level 4 Modifier Tests
    
    @Test("Prefix modifier")
    func testPrefixModifier() {
        let template = "http://example.com/search/{term:3}"
        let url = URL(string: "http://example.com/search/foo")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["term"] == "foo")
    }
    
    @Test("Explode modifier with simple expansion")
    func testExplodeModifierSimple() {
        let template = "http://example.com/search/{list*}"
        let url = URL(string: "http://example.com/search/red,green,blue")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["list"] == "red,green,blue")
    }
    
    @Test("Explode modifier with path segments")
    func testExplodeModifierPath() {
        let template = "http://example.com{/list*}"
        let url = URL(string: "http://example.com/red/green/blue")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["list"] == "red,green,blue")
    }
    
    @Test("Explode modifier with labels")
    func testExplodeModifierLabel() {
        let template = "http://example.com/file{.list*}"
        let url = URL(string: "http://example.com/file.red.green.blue")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["list"] == "red,green,blue")
    }
    
    // MARK: - Complex Real-World Examples
    
    @Test("GitHub API style template")
    func testGitHubAPIStyle() {
        let template = "https://api.github.com/repos/{owner}/{repo}/issues{?state,labels,sort,direction}"
        let url = URL(string: "https://api.github.com/repos/octocat/Hello-World/issues?state=open&labels=bug&sort=created&direction=desc")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["owner"] == "octocat")
        #expect(variables?["repo"] == "Hello-World")
        #expect(variables?["state"] == "open")
        #expect(variables?["labels"] == "bug")
        #expect(variables?["sort"] == "created")
        #expect(variables?["direction"] == "desc")
    }
    
    @Test("Complex mixed operators")
    func testComplexMixedOperators() {
        let url = URL(string: "http://example.com/foo/bar/file.json?query=test&limit=10#section1")!
        let template = "http://example.com{+path}/file{.format}{?query,limit}{#fragment}"
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["path"] == "foo/bar")
        #expect(variables?["format"] == "json")
        #expect(variables?["query"] == "test")
        #expect(variables?["limit"] == "10")
        #expect(variables?["fragment"] == "section1")
    }
    
    @Test("Custom scheme with path parameters")
    func testCustomSchemeWithPathParams() {
        let template = "users://{user_id}/profile{?locale,format}"
        let url = URL(string: "users://123/profile?locale=en&format=json")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["user_id"] == "123")
        #expect(variables?["locale"] == "en")
        #expect(variables?["format"] == "json")
    }
    
    // MARK: - Edge Cases and Error Conditions
    
    @Test("Non-matching template returns nil")
    func testNonMatchingTemplate() {
        let template = "http://example.com/users/{user_id}"
        let url = URL(string: "http://example.com/posts/123")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables == nil)
    }
    
    @Test("Different scheme returns nil")
    func testDifferentScheme() {
        let template = "http://example.com/users/{user_id}"
        let url = URL(string: "https://example.com/users/123")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables == nil)
    }
    
    @Test("Missing required query parameter")
    func testMissingRequiredQueryParameter() {
        let template = "http://example.com/search{?q,limit}"
        let url = URL(string: "http://example.com/search?q=test")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["q"] == "test")
        // limit should be missing, which is okay for optional parameters
    }
    
    @Test("URL with percent encoding")
    func testPercentEncoding() {
        let template = "http://example.com/search{?q}"
        let url = URL(string: "http://example.com/search?q=hello%20world")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["q"] == "hello world")
    }
    
    @Test("Empty variable value")
    func testEmptyVariableValue() {
        let template = "http://example.com/users/{user_id}"
        let url = URL(string: "http://example.com/users/")!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?["user_id"] == "")
    }
    
    // MARK: - Matching Tests
    
    @Test("URL matches template")
    func testURLMatches() {
        let template = "http://example.com/users/{user_id}"
        let url = URL(string: "http://example.com/users/123")!
        
        #expect(url.matches(template: template))
    }
    
    @Test("URL does not match template")
    func testURLDoesNotMatch() {
        let template = "http://example.com/users/{user_id}"
        let url = URL(string: "http://example.com/posts/123")!
        
        #expect(!url.matches(template: template))
    }
    
    // MARK: - Performance and Stress Tests
    
    @Test("Large number of variables")
    func testLargeNumberOfVariables() {
        let template = "http://example.com/" + (1...20).map { "path{var\($0)}" }.joined(separator: "/")
        let url = URL(string: "http://example.com/" + (1...20).map { "path\($0)" }.joined(separator: "/"))!
        
        let variables = url.extractTemplateVariables(from: template)
        #expect(variables != nil)
        #expect(variables?.count == 20)
        
        for i in 1...20 {
            #expect(variables?["var\(i)"] == "\(i)")
        }
    }
} 