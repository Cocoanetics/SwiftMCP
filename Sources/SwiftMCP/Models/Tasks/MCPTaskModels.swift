//
//  MCPTaskModels.swift
//  SwiftMCP
//
//  Wire-shaped helpers for the official Tasks extension. Detailed task
//  responses are assembled as dictionaries so status-specific fields
//  (`inputRequests`, `result`, `error`) stay flat on the result object.
//

import Foundation

/// Snapshot of a task's observable state for `tasks/get` and create handles.
public struct MCPTaskSnapshot: Sendable {
    public var taskId: String
    public var status: MCPTaskStatus
    public var statusMessage: String?
    public var createdAt: Date
    public var lastUpdatedAt: Date
    public var ttlMs: Int?
    public var pollIntervalMs: Int?
    public var inputRequests: [String: InputRequest]?
    public var result: JSONDictionary?
    public var error: JSONRPCError?

    /// Builds the `CreateTaskResult` payload (`resultType: "task"`).
    public func createTaskResultDictionary() -> JSONDictionary {
        var dict = baseDictionary()
        dict["resultType"] = .string("task")
        return dict
    }

    /// Builds a `tasks/get` payload (`resultType: "complete"`) with status-
    /// specific fields inlined.
    public func getTaskResultDictionary() -> JSONDictionary {
        var dict = baseDictionary()
        dict["resultType"] = .string("complete")
        switch status {
        case .inputRequired:
            if let inputRequests {
                dict["inputRequests"] = .object(inputRequests.mapValues { request in
                    var entry: JSONDictionary = ["method": .string(request.method)]
                    if let params = request.params {
                        entry["params"] = params
                    }
                    return .object(entry)
                })
            }
        case .completed:
            if let result {
                dict["result"] = .object(result)
            }
        case .failed:
            if let error {
                var errorDict: JSONDictionary = [
                    "code": .integer(error.code),
                    "message": .string(error.message)
                ]
                if let data = error.data {
                    errorDict["data"] = data
                }
                dict["error"] = .object(errorDict)
            }
        case .working, .cancelled:
            break
        }
        return dict
    }

    private func baseDictionary() -> JSONDictionary {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var dict: JSONDictionary = [
            "taskId": .string(taskId),
            "status": .string(status.rawValue),
            "createdAt": .string(formatter.string(from: createdAt)),
            "lastUpdatedAt": .string(formatter.string(from: lastUpdatedAt)),
            "ttlMs": ttlMs.map { JSONValue.integer($0) } ?? .null
        ]
        if let statusMessage {
            dict["statusMessage"] = .string(statusMessage)
        }
        if let pollIntervalMs {
            dict["pollIntervalMs"] = .integer(pollIntervalMs)
        }
        return dict
    }
}

/// Empty acknowledgement used by `tasks/update` and `tasks/cancel`.
public struct MCPTaskEmptyResult: Codable, Sendable {
    public var resultType: String

    public init(resultType: String = "complete") {
        self.resultType = resultType
    }
}
