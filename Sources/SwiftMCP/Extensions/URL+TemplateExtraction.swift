import Foundation

extension URL {
    /// Extracts named variables from a URL based on an RFC 6570 URI template
    /// - Parameter template: RFC 6570 compliant URI template
    /// - Returns: Dictionary of variable names and their values, or nil if URL doesn't match template pattern
    public func extractTemplateVariables(from template: String) -> [String: String]? {
        let extractor = RFC6570TemplateExtractor(template: template, url: self)
        return extractor.extract()
    }

    /// Returns true if the URL matches the given RFC 6570 template
    public func matches(template: String) -> Bool {
        return self.extractTemplateVariables(from: template) != nil
    }
}

extension String {
    /// Constructs a URI from an RFC 6570 template and parameters
    /// - Parameter parameters: Dictionary of parameter names and their values
    /// - Returns: Constructed URL
    /// - Throws: An error if the template cannot be processed or required parameters are missing
    public func constructURI(with parameters: JSONDictionary) throws -> URL {
        let constructor = RFC6570TemplateConstructor(template: self, parameters: parameters)
        return try constructor.construct()
    }
}

// MARK: - RFC 6570 Template Extractor

/// RFC 6570 compliant URI template extractor.
///
/// The implementation is split across multiple files in
/// `RFC6570TemplateExtractor+*.swift` for each expression form (simple,
/// reserved, label, path segment, path style, query) and parsing concerns.
internal struct RFC6570TemplateExtractor {
    let template: String
    let url: URL

    func extract() -> [String: String]? {
        // Split URL and template into components for easier matching
        let urlString = url.absoluteString

        // Handle different parts of the URL separately
        return extractFromComponents(urlString: urlString, template: template)
    }

    private func extractFromComponents(urlString: String, template: String) -> [String: String]? {
        var variables: [String: String] = [:]

        // First, handle query and fragment expressions that are part of the template structure
        var processedTemplate = template
        var processedURL = urlString

        // Handle fragment expressions like {#var}
        if let fragmentMatch = extractFragmentExpression(
            template: template,
            url: urlString,
            variables: &variables
        ) {
            processedTemplate = fragmentMatch.remainingTemplate
            processedURL = fragmentMatch.remainingURL
        }

        // Handle query expressions like {?var} and {&var}
        if let queryMatch = extractQueryExpressions(
            template: processedTemplate,
            url: processedURL,
            variables: &variables
        ) {
            processedTemplate = queryMatch.remainingTemplate
            processedURL = queryMatch.remainingURL
        }

        // Now handle the base URL (everything before query/fragment)
        let templateParts = processedTemplate.split(separator: "?", maxSplits: 1)
        let urlParts = processedURL.split(separator: "?", maxSplits: 1)

        let templateBase = String(templateParts[0])
        let urlBase = String(urlParts[0])

        // Extract from base URL (path part)
        guard extractFromBase(
            urlBase: urlBase,
            templateBase: templateBase,
            variables: &variables
        ) else {
            return nil
        }

        // Handle any remaining literal query parameters
        if templateParts.count > 1 && urlParts.count > 1 {
            let templateQuery = String(templateParts[1])
            let urlQuery = String(urlParts[1])
            guard extractFromQuery(
                urlQuery: urlQuery,
                templateQuery: templateQuery,
                variables: &variables
            ) else {
                return nil
            }
        }

        return variables
    }
}
