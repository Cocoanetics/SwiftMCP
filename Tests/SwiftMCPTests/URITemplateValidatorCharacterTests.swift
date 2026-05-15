//
//  URITemplateValidatorCharacterTests.swift
//  SwiftMCPTests
//

import Testing

#if canImport(SwiftCompilerPlugin)
@testable import SwiftMCPMacros

@Suite("URI Template Validator Variables and Characters")
struct URITemplateValidatorCharacterTests {

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

#endif
