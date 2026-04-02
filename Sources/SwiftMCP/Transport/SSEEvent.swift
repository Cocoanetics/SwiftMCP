import Foundation

/// Represents the different types of SSE content as defined by the ABNF specification
enum SSEEvent {
    /// A comment line starting with colon
    case comment(String)
    
    /// A field with name and value
    case field(name: String, value: String, eventName: String? = nil)
}
