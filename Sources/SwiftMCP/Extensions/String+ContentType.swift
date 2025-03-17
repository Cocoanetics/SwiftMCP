extension String {
    /// Checks if the content type matches the Accept header string
    /// - Parameter acceptHeader: The Accept header string (e.g. "text/html, application/xhtml+xml, */*")
    /// - Returns: true if the content type matches any of the accepted types
    func matchesAcceptHeader(_ acceptHeader: String) -> Bool {
        // Split accept header into individual types
        let acceptedTypes = acceptHeader.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Get the main type and subtype of the content type (self)
        let contentParts = self.split(separator: "/")
        guard contentParts.count == 2 else { return false }
        let contentMainType = String(contentParts[0])
        let contentSubType = String(contentParts[1])
        
        for acceptedType in acceptedTypes {
            // Handle quality values (;q=0.9) by removing them
            let type = acceptedType.split(separator: ";")[0].trimmingCharacters(in: .whitespaces)
            
            // Handle */* case
            if type == "*/*" {
                return true
            }
            
            let parts = type.split(separator: "/")
            guard parts.count == 2 else { continue }
            
            let mainType = String(parts[0])
            let subType = String(parts[1])
            
            // Check for exact match
            if mainType == contentMainType && (subType == "*" || subType == contentSubType) {
                return true
            }
            
            // Check for type/* match
            if mainType == "*" && subType == "*" {
                return true
            }
        }
        
        return false
    }
} 