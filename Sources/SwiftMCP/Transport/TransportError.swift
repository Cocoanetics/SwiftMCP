//
//  TransportError.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 21.03.25.
//

import Foundation

/**
 Errors that can occur during transport operations in SwiftMCP.
 
 This enum provides specific error types and localized descriptions for various
 transport-related failures, such as binding failures when starting a server.
 */
public enum TransportError: LocalizedError {
/**
	 Indicates that the transport failed to bind to a specific address and port.
	 
	 - Parameter message: A human-readable description of the binding failure,
	   including details about the specific cause (e.g., port in use, permission denied).
	 */
    case bindingFailed(String)

/**
	 Provides a localized description of the error.
	 
	 - Returns: A human-readable string describing the error.
	 */
    public var errorDescription: String? {
        switch self {
            case .bindingFailed(let message):
                return message
        }
    }
}
