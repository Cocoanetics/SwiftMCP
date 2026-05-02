//
//  PrototypeServer+CrossTarget.swift
//
//  Cross-target extension demonstrating a tool, a resource, and a prompt
//  contributed from a different module than the one defining the server.
//

import Foundation
import SwiftMCP
import PrototypeServerLib

@MCPExtension("Calendar")
extension PrototypeServer {
    /// Subtract b from a.
    @MCPTool
    public func subtract(a: Int, b: Int) -> Int {
        a - b
    }

    /// A static calendar greeting resource.
    @MCPResource("calendar://today")
    public func todayResource() -> String {
        "Today's calendar is empty."
    }

    /// A prompt that frames a question about scheduling.
    @MCPPrompt
    public func schedulingPrompt(person: String) -> String {
        "Suggest three meeting times that work for \(person)."
    }
}
