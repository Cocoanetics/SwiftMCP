//
//  Data+base64URLEncoded.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 02.07.25.
//

import Foundation

// MARK: - Extension to handle base64URL decoding for JWT

extension Data {
    /// SwiftCrypto expects raw big-endian bytes.  
    /// JWT uses base64url with no padding.  
    init(base64URLEncoded source: String) throws {
        var padded = source.replacingOccurrences(of: "-", with: "+")
                           .replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        guard let d = Data(base64Encoded: padded) else {
            throw JWTError.invalidBase64
        }
        self = d
    }
} 
