//
//  TestError.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 10.03.25.
//


struct TestError: Error {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
} 