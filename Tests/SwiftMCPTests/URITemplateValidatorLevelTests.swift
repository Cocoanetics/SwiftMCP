//
//  URITemplateValidatorLevelTests.swift
//  SwiftMCPTests
//

import Testing

#if canImport(SwiftCompilerPlugin)
@testable import SwiftMCPMacros

@Suite("URI Template Validator Levels and Modifiers")
struct URITemplateValidatorLevelTests {

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
}

#endif
