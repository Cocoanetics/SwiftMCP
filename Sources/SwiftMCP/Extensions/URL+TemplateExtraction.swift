import Foundation

extension URL {
    /// Extracts named variables from a URL based on a template pattern
    /// - Parameter template: Template string in format "scheme://{var1}/{var2}?param={var3}"
    /// - Returns: Dictionary of variable names and their values, or nil if URL doesn't match template pattern
    public func extractTemplateVariables(from template: String) -> [String: String]? {
        // For custom schemes, we need to handle the path differently
        // Split template into components
        let templateParts = template.split(separator: "?", maxSplits: 1)
        let templateBase = String(templateParts[0])
        let templateQuery = templateParts.count > 1 ? String(templateParts[1]) : nil
        
        // Split actual URL into components
        let actualParts = self.absoluteString.split(separator: "?", maxSplits: 1)
        let actualBase = String(actualParts[0])
        let actualQuery = actualParts.count > 1 ? String(actualParts[1]) : nil
        
        // Extract scheme and path from template
        guard let schemeSeparatorRange = templateBase.range(of: "://") else { return nil }
        let templateScheme = String(templateBase[..<schemeSeparatorRange.lowerBound])
        let templatePath = String(templateBase[schemeSeparatorRange.upperBound...])
        
        // Extract scheme and path from actual URL
        guard let actualSchemeSeparatorRange = actualBase.range(of: "://") else { return nil }
        let actualScheme = String(actualBase[..<actualSchemeSeparatorRange.lowerBound])
        let actualPath = String(actualBase[actualSchemeSeparatorRange.upperBound...])
        
        // Check scheme matches
        guard templateScheme == actualScheme else { return nil }
        
        var variables: [String: String] = [:]
        
        // Split paths into components
        let templateComponents = templatePath.split(separator: "/").map(String.init)
        let actualComponents = actualPath.split(separator: "/").map(String.init)
        
        // Paths must have same number of components
        guard templateComponents.count == actualComponents.count else { return nil }
        
        // Compare each path component
        for (templateComponent, actualComponent) in zip(templateComponents, actualComponents) {
            if templateComponent.hasPrefix("{") && templateComponent.hasSuffix("}") {
                // Extract variable name without braces
                let varName = String(templateComponent.dropFirst().dropLast())
                variables[varName] = actualComponent
            } else if templateComponent != actualComponent {
                // If non-variable components don't match, template doesn't match
                return nil
            }
        }
        
        // Extract query variables
        if let templateQuery = templateQuery {
            // Parse template query parameters
            let templateParams = parseQueryString(templateQuery)
            
            // Parse actual query parameters
            let actualParams: [String: String]
            if let actualQuery = actualQuery {
                actualParams = parseQueryString(actualQuery)
            } else {
                actualParams = [:]
            }
            
            // Match template query parameters
            for (key, templateValue) in templateParams {
                if templateValue.hasPrefix("{") && templateValue.hasSuffix("}") {
                    // This is a placeholder
                    let varName = String(templateValue.dropFirst().dropLast())
                    if let actualValue = actualParams[key] {
                        variables[varName] = actualValue
                    }
                    // If the parameter is missing from actual URL, that's okay for optional params
                } else {
                    // This is a literal value, must match exactly
                    guard actualParams[key] == templateValue else {
                        return nil
                    }
                }
            }
        }
        
        return variables
    }
    
    /// Parses a query string into a dictionary
    private func parseQueryString(_ query: String) -> [String: String] {
        var params: [String: String] = [:]
        let pairs = query.split(separator: "&")
        for pair in pairs {
            let components = pair.split(separator: "=", maxSplits: 1)
            if components.count == 2 {
                let key = String(components[0])
                let value = String(components[1]).removingPercentEncoding ?? String(components[1])
                params[key] = value
            } else if components.count == 1 {
                // Handle parameters without values
                params[String(components[0])] = ""
            }
        }
        return params
    }
    
    /// Returns true if the URL matches the given template
    public func matches(template: String) -> Bool {
        return self.extractTemplateVariables(from: template) != nil
    }
} 