//
//  URITemplateValidatorTests.swift
//  SwiftMCPTests
//
//  Created by SwiftMCP on $(date).
//

import Testing

#if canImport(SwiftCompilerPlugin)
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

}

#endif
