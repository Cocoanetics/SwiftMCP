import Foundation

/// Postal address structure for OpenID Connect userinfo
public struct Address: Codable, Sendable {
    /// Full mailing address, formatted for display or use with a mailing label
    public let formatted: String?
    
    /// Full street address component, which may include house number, street name, Post Office Box, and multi-line extended street address information
    public let streetAddress: String?
    
    /// City or locality component
    public let locality: String?
    
    /// State, province, prefecture, or region component
    public let region: String?
    
    /// Zip code or postal code component
    public let postalCode: String?
    
    /// Country name component
    public let country: String?
    
    public init(
        formatted: String? = nil,
        streetAddress: String? = nil,
        locality: String? = nil,
        region: String? = nil,
        postalCode: String? = nil,
        country: String? = nil
    ) {
        self.formatted = formatted
        self.streetAddress = streetAddress
        self.locality = locality
        self.region = region
        self.postalCode = postalCode
        self.country = country
    }
    
    internal enum CodingKeys: String, CodingKey {
        case formatted
        case streetAddress = "street_address"
        case locality
        case region
        case postalCode = "postal_code"
        case country
    }
}
