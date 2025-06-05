//
//  DemoServer+MCPCompletionProviding.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 05.06.25.
//

import SwiftMCP

extension DemoServer: MCPCompletionProviding {
    
    func completion(for parameter: MCPParameterInfo, in context: MCPCompletionContext, prefix: String) async -> CompleteResult.Completion
    {
        // provide completion for any query
        if parameter.name == "query"
        {
            let values = ["Oliver", "Sylvia", "Max"].sortedByBestCompletion(prefix: prefix)
            
            return .init(values: values, total: values.count, hasMore: false)
        }
        
        // return default otherwise
        let completions = parameter.defaultCompletions.sortedByBestCompletion(prefix: prefix)
        return CompleteResult.Completion(values: completions, total: completions.count, hasMore: false)
    }
}
