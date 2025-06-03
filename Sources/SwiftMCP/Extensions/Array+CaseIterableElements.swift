//
//  Array+CaseIterableElements.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 07.04.25.
//

import Foundation

protocol ArrayWithCaseIterableElements {
    static func schema(description: String?) -> JSONSchema
}

extension Array: ArrayWithCaseIterableElements where Element: CaseIterable {

    public static func schema(description: String? = nil) -> JSONSchema {

        let elementSchema = JSONSchema.enum(values: Element.caseLabels)
        return .array(items: elementSchema, description: description)
    }
}
