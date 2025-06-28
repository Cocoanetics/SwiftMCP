import Foundation

/// User information from OpenID Connect userinfo endpoint
/// Based on OpenID Connect Core 1.0 specification, section 5.1 "Standard Claims"
public struct UserInfo: Codable, Sendable {
    // MARK: - Required Claims
    
    /// Unique identifier for the user (always present)
    public let sub: String
    
    // MARK: - Personal Information
    
    /// Full name
    public let name: String?
    
    /// Given name(s) or first name(s)
    public let givenName: String?
    
    /// Surname(s) or last name(s)
    public let familyName: String?
    
    /// Middle name(s)
    public let middleName: String?
    
    /// Casual name
    public let nickname: String?
    
    /// Shorthand name by which the End-User wishes to be referred to
    public let preferredUsername: String?
    
    // MARK: - Profile & Contact
    
    /// URL of the End-User's profile page
    public let profile: String?
    
    /// URL of the End-User's profile picture
    public let picture: String?
    
    /// URL of the End-User's Web page or blog
    public let website: String?
    
    /// End-User's preferred e-mail address
    public let email: String?
    
    /// True if the End-User's e-mail address has been verified
    public let emailVerified: Bool?
    
    /// End-User's preferred telephone number
    public let phoneNumber: String?
    
    /// True if the End-User's phone number has been verified
    public let phoneNumberVerified: Bool?
    
    // MARK: - Demographics
    
    /// End-User's gender
    public let gender: String?
    
    /// End-User's birthday, represented as an ISO 8601:2004 [ISO8601‑2004] YYYY-MM-DD format
    public let birthdate: String?
    
    /// String from zoneinfo [zoneinfo] time zone database
    public let zoneinfo: String?
    
    /// End-User's locale, represented as a BCP47 [RFC5646] language tag
    public let locale: String?
    
    // MARK: - Address
    
    /// End-User's preferred postal address
    public let address: Address?
    
    // MARK: - Metadata
    
    /// Time the End-User's information was last updated
    public let updatedAt: Date?
    
    // MARK: - Initialization
    
    public init(
        sub: String,
        name: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil,
        middleName: String? = nil,
        nickname: String? = nil,
        preferredUsername: String? = nil,
        profile: String? = nil,
        picture: String? = nil,
        website: String? = nil,
        email: String? = nil,
        emailVerified: Bool? = nil,
        phoneNumber: String? = nil,
        phoneNumberVerified: Bool? = nil,
        gender: String? = nil,
        birthdate: String? = nil,
        zoneinfo: String? = nil,
        locale: String? = nil,
        address: Address? = nil,
        updatedAt: Date? = nil
    ) {
        self.sub = sub
        self.name = name
        self.givenName = givenName
        self.familyName = familyName
        self.middleName = middleName
        self.nickname = nickname
        self.preferredUsername = preferredUsername
        self.profile = profile
        self.picture = picture
        self.website = website
        self.email = email
        self.emailVerified = emailVerified
        self.phoneNumber = phoneNumber
        self.phoneNumberVerified = phoneNumberVerified
        self.gender = gender
        self.birthdate = birthdate
        self.zoneinfo = zoneinfo
        self.locale = locale
        self.address = address
        self.updatedAt = updatedAt
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case sub
        case name
        case givenName = "given_name"
        case familyName = "family_name"
        case middleName = "middle_name"
        case nickname
        case preferredUsername = "preferred_username"
        case profile
        case picture
        case website
        case email
        case emailVerified = "email_verified"
        case phoneNumber = "phone_number"
        case phoneNumberVerified = "phone_number_verified"
        case gender
        case birthdate
        case zoneinfo
        case locale
        case address
        case updatedAt = "updated_at"
    }
}

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
    
    private enum CodingKeys: String, CodingKey {
        case formatted
        case streetAddress = "street_address"
        case locality
        case region
        case postalCode = "postal_code"
        case country
    }
} 