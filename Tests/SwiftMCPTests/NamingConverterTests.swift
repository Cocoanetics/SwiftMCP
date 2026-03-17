import Testing
@testable import SwiftMCP

@Suite("NamingConverter")
struct NamingConverterTests {

    // MARK: - Detection

    @Test("Detects lowerCamelCase")
    func detectLowerCamelCase() {
        #expect(NamingConverter.detect("buildProject") == .lowerCamelCase)
        #expect(NamingConverter.detect("getItems") == .lowerCamelCase)
        #expect(NamingConverter.detect("x") == .lowerCamelCase)
    }

    @Test("Detects UpperCamelCase")
    func detectUpperCamelCase() {
        #expect(NamingConverter.detect("BuildProject") == .upperCamelCase)
        #expect(NamingConverter.detect("HTMLParser") == .upperCamelCase)
        #expect(NamingConverter.detect("X") == .upperCamelCase)
    }

    @Test("Detects snake_case")
    func detectSnakeCase() {
        #expect(NamingConverter.detect("build_project") == .snakeCase)
        #expect(NamingConverter.detect("html_parser") == .snakeCase)
        #expect(NamingConverter.detect("get_url_for_request") == .snakeCase)
    }

    // MARK: - PascalCase → lowerCamelCase

    @Test("PascalCase to lowerCamelCase — simple words")
    func pascalToLowerSimple() {
        #expect(NamingConverter.toLowerCamelCase("BuildProject") == "buildProject")
        #expect(NamingConverter.toLowerCamelCase("RunAllTests") == "runAllTests")
        #expect(NamingConverter.toLowerCamelCase("GetBuildLog") == "getBuildLog")
    }

    @Test("PascalCase to lowerCamelCase — acronym prefix")
    func pascalToLowerAcronym() {
        #expect(NamingConverter.toLowerCamelCase("XcodeRead") == "xcodeRead")
        #expect(NamingConverter.toLowerCamelCase("XcodeWrite") == "xcodeWrite")
        #expect(NamingConverter.toLowerCamelCase("XcodeGlob") == "xcodeGlob")
        #expect(NamingConverter.toLowerCamelCase("XcodeListWindows") == "xcodeListWindows")
    }

    @Test("PascalCase to lowerCamelCase — acronym suffix")
    func pascalToLowerAcronymSuffix() {
        #expect(NamingConverter.toLowerCamelCase("XcodeMV") == "xcodeMv")
        #expect(NamingConverter.toLowerCamelCase("XcodeLS") == "xcodeLs")
    }

    @Test("PascalCase to lowerCamelCase — multi-letter acronym")
    func pascalToLowerMultiAcronym() {
        #expect(NamingConverter.toLowerCamelCase("HTMLParser") == "htmlParser")
        #expect(NamingConverter.toLowerCamelCase("URLValidator") == "urlValidator")
        #expect(NamingConverter.toLowerCamelCase("GetURLForRequest") == "getUrlForRequest")
    }

    @Test("PascalCase to lowerCamelCase — all caps")
    func pascalToLowerAllCaps() {
        #expect(NamingConverter.toLowerCamelCase("LS") == "ls")
        #expect(NamingConverter.toLowerCamelCase("MV") == "mv")
        #expect(NamingConverter.toLowerCamelCase("URL") == "url")
    }

    @Test("PascalCase to lowerCamelCase — single character")
    func pascalToLowerSingle() {
        #expect(NamingConverter.toLowerCamelCase("X") == "x")
    }

    @Test("Already lowerCamelCase — no change")
    func alreadyLowerCamelCase() {
        #expect(NamingConverter.toLowerCamelCase("buildProject") == "buildProject")
        #expect(NamingConverter.toLowerCamelCase("getItems") == "getItems")
    }

    // MARK: - lowerCamelCase → PascalCase

    @Test("lowerCamelCase to PascalCase — simple words")
    func lowerToPascalSimple() {
        #expect(NamingConverter.toUpperCamelCase("buildProject") == "BuildProject")
        #expect(NamingConverter.toUpperCamelCase("runAllTests") == "RunAllTests")
        #expect(NamingConverter.toUpperCamelCase("getBuildLog") == "GetBuildLog")
    }

    @Test("lowerCamelCase to PascalCase — already PascalCase preserved")
    func alreadyPascalCase() {
        #expect(NamingConverter.toUpperCamelCase("BuildProject") == "BuildProject")
        #expect(NamingConverter.toUpperCamelCase("HTMLParser") == "HTMLParser")
        #expect(NamingConverter.toUpperCamelCase("MCPServer") == "MCPServer")
    }

    // MARK: - snake_case → lowerCamelCase

    @Test("snake_case to lowerCamelCase")
    func snakeToLowerCamelCase() {
        #expect(NamingConverter.toLowerCamelCase("build_project") == "buildProject")
        #expect(NamingConverter.toLowerCamelCase("html_parser") == "htmlParser")
        #expect(NamingConverter.toLowerCamelCase("get_url_for_request") == "getUrlForRequest")
        #expect(NamingConverter.toLowerCamelCase("list_windows") == "listWindows")
    }

    // MARK: - snake_case → PascalCase

    @Test("snake_case to PascalCase")
    func snakeToPascalCase() {
        #expect(NamingConverter.toUpperCamelCase("build_project") == "BuildProject")
        #expect(NamingConverter.toUpperCamelCase("html_parser") == "HtmlParser")
        #expect(NamingConverter.toUpperCamelCase("get_url_for_request") == "GetUrlForRequest")
    }

    // MARK: - camelCase → snake_case

    @Test("lowerCamelCase to snake_case")
    func lowerCamelToSnake() {
        #expect(NamingConverter.toSnakeCase("buildProject") == "build_project")
        #expect(NamingConverter.toSnakeCase("listWindows") == "list_windows")
        #expect(NamingConverter.toSnakeCase("getItems") == "get_items")
    }

    @Test("PascalCase to snake_case")
    func pascalToSnake() {
        #expect(NamingConverter.toSnakeCase("BuildProject") == "build_project")
        #expect(NamingConverter.toSnakeCase("HTMLParser") == "html_parser")
        #expect(NamingConverter.toSnakeCase("XcodeRead") == "xcode_read")
        #expect(NamingConverter.toSnakeCase("XcodeMV") == "xcode_mv")
        #expect(NamingConverter.toSnakeCase("GetURLForRequest") == "get_url_for_request")
    }

    @Test("Already snake_case — no change")
    func alreadySnakeCase() {
        #expect(NamingConverter.toSnakeCase("build_project") == "build_project")
    }

    // MARK: - Round-trips

    @Test("PascalCase → lowerCamelCase → PascalCase round-trip")
    func roundTripPascalLower() {
        let names = ["BuildProject", "RunAllTests", "GetBuildLog", "XcodeRead", "XcodeListWindows"]
        for name in names {
            let lower = NamingConverter.toLowerCamelCase(name)
            let upper = NamingConverter.toUpperCamelCase(lower)
            #expect(upper == name, "Round-trip failed: \(name) → \(lower) → \(upper)")
        }
    }

    @Test("snake_case → lowerCamelCase → snake_case round-trip")
    func roundTripSnakeLower() {
        let names = ["build_project", "list_windows", "get_items", "html_parser"]
        for name in names {
            let lower = NamingConverter.toLowerCamelCase(name)
            let snake = NamingConverter.toSnakeCase(lower)
            #expect(snake == name, "Round-trip failed: \(name) → \(lower) → \(snake)")
        }
    }

    // MARK: - Edge cases

    @Test("Empty string")
    func emptyString() {
        #expect(NamingConverter.toLowerCamelCase("") == "")
        #expect(NamingConverter.toUpperCamelCase("") == "")
        #expect(NamingConverter.toSnakeCase("") == "")
    }

    @Test("Single lowercase letter")
    func singleLowercase() {
        #expect(NamingConverter.toLowerCamelCase("x") == "x")
        #expect(NamingConverter.toUpperCamelCase("x") == "X")
        #expect(NamingConverter.toSnakeCase("x") == "x")
    }

    @Test("All Xcode mcpbridge tool names")
    func xcodeToolNames() {
        let expectations: [(tool: String, swift: String)] = [
            ("XcodeListWindows", "xcodeListWindows"),
            ("XcodeGlob", "xcodeGlob"),
            ("XcodeUpdate", "xcodeUpdate"),
            ("XcodeGrep", "xcodeGrep"),
            ("XcodeRM", "xcodeRm"),
            ("ExecuteSnippet", "executeSnippet"),
            ("RenderPreview", "renderPreview"),
            ("GetTestList", "getTestList"),
            ("RunAllTests", "runAllTests"),
            ("XcodeRead", "xcodeRead"),
            ("RunSomeTests", "runSomeTests"),
            ("XcodeLS", "xcodeLs"),
            ("XcodeListNavigatorIssues", "xcodeListNavigatorIssues"),
            ("XcodeMakeDir", "xcodeMakeDir"),
            ("GetBuildLog", "getBuildLog"),
            ("XcodeWrite", "xcodeWrite"),
            ("BuildProject", "buildProject"),
            ("XcodeRefreshCodeIssuesInFile", "xcodeRefreshCodeIssuesInFile"),
            ("XcodeMV", "xcodeMv"),
        ]

        for (tool, expected) in expectations {
            let result = NamingConverter.toLowerCamelCase(tool)
            #expect(result == expected, "\(tool) → \(result), expected \(expected)")
        }
    }
}
