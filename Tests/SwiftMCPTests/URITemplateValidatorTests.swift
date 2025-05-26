//
//  URITemplateValidatorTests.swift
//  SwiftMCPTests
//
//  Created by SwiftMCP on $(date).
//

import Testing
@testable import SwiftMCPMacros

@Suite("URI Template Validator")
struct URITemplateValidatorTests {
    
    // MARK: - Basic Validation Tests
    
    @Test("Empty template should be invalid")
    func testEmptyTemplate() {
        let result = URITemplateValidator.validate("")
        #expect(!result.isValid)
        #expect(result.error != nil)
        #expect(result.error?.message.contains("cannot be empty") == true)
        #expect(result.level == 0)
        #expect(result.variables == [])
    }
    
    @Test("Valid absolute URIs with schemes should be accepted")
    func testValidAbsoluteURIWithScheme() {
        let templates = [
            "http://example.com/users/{id}",
            "https://api.example.com/v1/users/{user_id}",
            "ftp://files.example.com/{path}",
            "custom://app.example.com/{resource}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Template '\(template)' should be valid")
            #expect(result.error == nil)
        }
    }
    
    @Test("Valid relative URIs should be accepted")
    func testValidRelativeURIs() {
        let templates = [
            "/users/{id}",
            "users/{id}/profile",
            "?query={q}",
            "#section-{id}",
            "relative/path/{param}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Template '\(template)' should be valid")
            #expect(result.error == nil)
        }
    }
    
    @Test("Invalid URI structures should be rejected")
    func testInvalidURIStructure() {
        let templates = [
            "://invalid",
            "ht!tp://invalid.com",
            "123://invalid.com"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(!result.isValid, "Template '\(template)' should be invalid")
            #expect(result.error != nil)
            #expect(result.error?.message.contains("valid scheme") == true)
        }
    }
    
    // MARK: - Expression Validation Tests
    
    @Test("Valid simple expressions should be accepted")
    func testValidSimpleExpressions() {
        let templates = [
            "http://example.com/{id}",
            "/users/{user_id}",
            "/path/{param1}/{param2}",
            "/{var_name}",
            "/{_underscore}",
            "/{var123}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Template '\(template)' should be valid")
            #expect(result.error == nil)
            #expect(result.level == 1)
        }
    }
    
    @Test("Empty expressions should be rejected")
    func testEmptyExpression() {
        let result = URITemplateValidator.validate("http://example.com/{}")
        #expect(!result.isValid)
        #expect(result.error != nil)
        #expect(result.error?.message.contains("Empty expression") == true)
    }
    
    @Test("Unmatched braces should be rejected")
    func testUnmatchedBraces() {
        let templates = [
            "http://example.com/{unclosed",
            "http://example.com/unclosed}",
            "http://example.com/{nested{invalid}}",
            "http://example.com/{missing"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(!result.isValid, "Template '\(template)' should be invalid")
            #expect(result.error != nil)
        }
    }
    
    // MARK: - RFC 6570 Level Tests
    
    @Test("Level 1 templates should be correctly identified")
    func testLevel1Templates() {
        let templates = [
            "http://example.com/{id}",
            "/users/{user_id}",
            "/{var}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Template '\(template)' should be valid")
            #expect(result.level == 1)
        }
    }
    
    @Test("Level 2 templates should be correctly identified")
    func testLevel2Templates() {
        let templates = [
            "http://example.com/{+path}",
            "/users/{#fragment}",
            "/{+var}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Template '\(template)' should be valid")
            #expect(result.level == 2)
        }
    }
    
    @Test("Level 3 templates should be correctly identified")
    func testLevel3Templates() {
        let templates = [
            "http://example.com{/path}",
            "/users{.format}",
            "/search{?q,limit}",
            "/users{;id}",
            "/path{&param}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Template '\(template)' should be valid")
            #expect(result.level == 3)
        }
    }
    
    @Test("Level 4 reserved operators should be rejected")
    func testLevel4ReservedOperators() {
        let templates = [
            "http://example.com/{=var}",
            "/users/{,var}",
            "/path/{!var}",
            "/resource/{@var}",
            "/data/{|var}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(!result.isValid, "Template '\(template)' should be invalid (reserved operator)")
            #expect(result.error != nil)
            #expect(result.error?.message.contains("reserved for future") == true)
        }
    }
    
    @Test("Level 4 modifiers should be correctly identified")
    func testLevel4Modifiers() {
        let templates = [
            "http://example.com/{var*}",
            "/users/{var:3}",
            "/path/{list*}",
            "/data/{name:10}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Template '\(template)' should be valid")
            #expect(result.level == 4)
        }
    }
    
    // MARK: - Variable Name Validation Tests
    
    @Test("Valid variable names should be accepted")
    func testValidVariableNames() {
        let variables = [
            "id",
            "user_id",
            "var123",
            "_underscore",
            "camelCase",
            "snake_case",
            "var.with.dots",
            "a1b2c3"
        ]
        
        for variable in variables {
            let template = "http://example.com/{\(variable)}"
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Variable '\(variable)' should be valid")
            #expect(result.variables == [variable])
        }
    }
    
    @Test("Invalid variable names should be rejected")
    func testInvalidVariableNames() {
        let variables = [
            "var-with-dashes",
            "var with spaces",
            "var@symbol",
            "var#hash",
            "var$dollar",
            "123numeric",
            "var/slash"
        ]
        
        for variable in variables {
            let template = "http://example.com/{\(variable)}"
            let result = URITemplateValidator.validate(template)
            #expect(!result.isValid, "Variable '\(variable)' should be invalid")
            #expect(result.error != nil)
            #expect(result.error?.message.contains("Invalid variable name") == true)
        }
    }
    
    // MARK: - Modifier Validation Tests
    
    @Test("Valid prefix modifiers should be accepted")
    func testValidPrefixModifiers() {
        let templates = [
            "http://example.com/{var:1}",
            "/users/{name:10}",
            "/path/{id:999}",
            "/data/{value:9999}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Template '\(template)' should be valid")
            #expect(result.level == 4)
        }
    }
    
    @Test("Invalid prefix modifiers should be rejected")
    func testInvalidPrefixModifiers() {
        let templates = [
            "http://example.com/{var:}",
            "/users/{name:0}",
            "/path/{id:-1}",
            "/data/{value:10000}",
            "/invalid/{var:abc}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(!result.isValid, "Template '\(template)' should be invalid")
            #expect(result.error != nil)
        }
    }
    
    @Test("Explode modifiers should be accepted")
    func testExplodeModifier() {
        let templates = [
            "http://example.com/{var*}",
            "/users/{list*}",
            "/path/{params*}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Template '\(template)' should be valid")
            #expect(result.level == 4)
        }
    }
    
    // MARK: - Multiple Variables Tests
    
    @Test("Multiple variables should be accepted")
    func testMultipleVariables() {
        let templates = [
            "http://example.com/{var1,var2}",
            "/users/{id,format}",
            "/search{?q,limit,offset}",
            "/path{/var1,var2,var3}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Template '\(template)' should be valid")
            #expect(result.level >= 3) // Multiple variables require Level 3+
        }
    }
    
    @Test("Variable extraction should work correctly")
    func testVariableExtraction() {
        let testCases: [(template: String, expectedVars: [String])] = [
            ("http://example.com/{id}", ["id"]),
            ("/users/{user_id}/posts/{post_id}", ["user_id", "post_id"]),
            ("/search{?q,limit,offset}", ["q", "limit", "offset"]),
            ("/path/{var1,var2}", ["var1", "var2"]),
            ("/users/{id:3}/profile", ["id"]),
            ("/data/{list*}", ["list"]),
            ("http://example.com/static", [])
        ]
        
        for (template, expectedVars) in testCases {
            let result = URITemplateValidator.validate(template)
            #expect(result.variables.sorted() == expectedVars.sorted(), 
                          "Variables for '\(template)' should be \(expectedVars)")
        }
    }
    
    // MARK: - Literal Character Validation Tests
    
    @Test("Valid literal characters should be accepted")
    func testValidLiteralCharacters() {
        let templates = [
            "http://example.com/users/{id}",
            "/path/to/resource/{param}",
            "/search?q={query}&limit=10",
            "/users/{id}#section",
            "/api/v1/users/{id}.json"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Template '\(template)' should be valid")
        }
    }
    
    @Test("Invalid literal characters should be rejected")
    func testInvalidLiteralCharacters() {
        let invalidChars = ["<", ">", "\\", "^", "`", "|", "\"", "'"]
        
        for char in invalidChars {
            let template = "http://example.com/path\(char)/{id}"
            let result = URITemplateValidator.validate(template)
            #expect(!result.isValid, "Template with '\(char)' should be invalid")
            #expect(result.error != nil)
            #expect(result.error?.message.contains("Invalid character") == true)
        }
    }
    
    @Test("Control characters should be rejected")
    func testControlCharacters() {
        // Test control characters (ASCII < 0x21 except space)
        let template = "http://example.com/path\u{01}/{id}"
        let result = URITemplateValidator.validate(template)
        #expect(!result.isValid)
        #expect(result.error != nil)
        #expect(result.error?.message.contains("Control character") == true)
    }
    
    // MARK: - Edge Cases and Complex Templates
    
    @Test("Complex valid templates should be accepted")
    func testComplexValidTemplates() {
        let templates = [
            "http://example.com/users/{user_id}/posts/{post_id}/comments{?limit,offset}",
            "https://api.example.com/v1{/path*}{?query*}",
            "/search{?q,category,sort,limit:10}",
            "http://example.com{+path}/resource{.format}{?params*}",
            "/users/{id}/profile{.format}{?fields,include*}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Complex template '\(template)' should be valid")
        }
    }
    
    @Test("Real-world examples should be accepted")
    func testRealWorldExamples() {
        let templates = [
            "https://api.github.com/repos/{owner}/{repo}/issues{?state,labels,sort,direction}",
            "http://example.com/dictionary/{term:1}/{term}",
            "http://example.com/search{?q,lang}",
            "https://api.example.com/users/{user_id}/posts/{post_id}",
            "/api/v1/resources/{id}{.format}",
            "features://list",
            "data://users/{user_id}",
            "custom://app/resource/{id}"
        ]
        
        for template in templates {
            let result = URITemplateValidator.validate(template)
            #expect(result.isValid, "Real-world template '\(template)' should be valid")
        }
    }
    
    // MARK: - Performance Tests
    
    @Test("Performance with large template should be acceptable")
    func testPerformanceWithLargeTemplate() {
        let largeTemplate = "http://example.com/" + (1...100).map { "path\($0)/{var\($0)}" }.joined(separator: "/")
        
        // Swift Testing doesn't have built-in performance testing like XCTest
        // So we'll just validate the functionality works correctly
        let result = URITemplateValidator.validate(largeTemplate)
        #expect(result.isValid)
        #expect(result.variables.count == 100)
    }
    
    // MARK: - Convenience Method Tests
    
    @Test("Extract variables convenience method should work correctly")
    func testExtractVariablesConvenienceMethod() {
        let template = "http://example.com/users/{user_id}/posts/{post_id}{?format,include}"
        let variables = URITemplateValidator.extractVariables(from: template)
        let expectedVariables = ["user_id", "post_id", "format", "include"]
        
        #expect(variables.sorted() == expectedVariables.sorted())
    }
    
    @Test("Extract variables from invalid template should return empty array")
    func testExtractVariablesFromInvalidTemplate() {
        let template = "http://example.com/{unclosed"
        let variables = URITemplateValidator.extractVariables(from: template)
        
        // Should return empty array for invalid templates
        #expect(variables == [])
    }
} 