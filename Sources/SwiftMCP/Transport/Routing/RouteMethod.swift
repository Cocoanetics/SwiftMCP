import Foundation

/// HTTP method enum, transport-agnostic (no NIO dependency).
public enum RouteMethod: String, Sendable, CaseIterable {
	case GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD
}
