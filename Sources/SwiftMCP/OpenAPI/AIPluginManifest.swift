import Foundation

/// Represents the AI plugin manifest structure
struct AIPluginManifest: Codable {
    /// The schema version of the manifest
    let schemaVersion: String = "v1"
    
    /// The human-readable name of the plugin
    let nameForHuman: String
    
    /// The model-readable name of the plugin
    let nameForModel: String
    
    /// The human-readable description of the plugin
    let descriptionForHuman: String
    
    /// The model-readable description of the plugin
    let descriptionForModel: String
    
    /// The authentication configuration
    let auth: Auth
    
    /// The API configuration
    let api: API
    
    /// Coding keys for JSON serialization
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case nameForHuman = "name_for_human"
        case nameForModel = "name_for_model"
        case descriptionForHuman = "description_for_human"
        case descriptionForModel = "description_for_model"
        case auth
        case api
    }
    
    /// Authentication configuration
    struct Auth: Codable {
        /// The type of authentication
        let type: AuthType
        
        /// The type of authorization (only for user_http)
        let authorizationType: String?
        
        /// Instructions for authentication (only for user_http)
        let instructions: String?
        
        enum CodingKeys: String, CodingKey {
            case type
            case authorizationType = "authorization_type"
            case instructions
        }
        
        /// Create an auth configuration for no authentication
        static var none: Auth {
            Auth(type: .none, authorizationType: nil, instructions: nil)
        }
        
        /// Create an auth configuration for bearer token authentication
        static var bearer: Auth {
            Auth(
                type: .userHttp,
                authorizationType: "bearer",
                instructions: "Enter your Bearer Token to authenticate with the API."
            )
        }
    }
    
    /// Authentication types supported by the manifest
    enum AuthType: String, Codable {
        case none
        case userHttp = "user_http"
    }
    
    /// API configuration
    struct API: Codable {
        /// The type of API
        let type: String
        
        /// The URL of the API specification
        let url: String
    }
} 
