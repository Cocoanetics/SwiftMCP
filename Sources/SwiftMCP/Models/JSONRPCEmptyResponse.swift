//
//  JSONRPCEmptyResponse.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

@preconcurrency import AnyCodable

/// An empty response as it would be returned from Ping
public struct JSONRPCEmptyResponse: JSONRPCMessage {
        public var jsonrpc: String = "2.0"
        public var id: Int?
        public var result: [String: AnyCodable] = [:]
}
