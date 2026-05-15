import Testing
import Foundation
@testable import SwiftMCP

func responseSchema(_ spec: OpenAPISpec, path: String) -> JSONSchema? {
    spec.paths[path]?.post?.responses["200"]?.content?["application/json"]?.schema
}

func assertSingleForecastSchema(_ spec: OpenAPISpec) {
    guard let schema = responseSchema(spec, path: "/testserver/getSingleForecast") else {
        #expect(Bool(false), "Failed to get schema for getSingleForecast")
        return
    }
    #expect(schema.type == "object", "Expected object schema for single forecast")
}

func assertMultipleForecastsSchema(_ spec: OpenAPISpec) {
    guard let schema = responseSchema(spec, path: "/testserver/getMultipleForecasts") else {
        #expect(Bool(false), "Failed to get schema for getMultipleForecasts")
        return
    }
    #expect(schema.type == "array", "Expected array schema for multiple forecasts")
    if case .array(let items, title: _, description: _, defaultValue: _) = schema {
        #expect(items.type == "object", "Expected object schema for array items")
    } else {
        #expect(Bool(false), "Expected array schema")
    }
}

func assertSingleConditionSchema(_ spec: OpenAPISpec) {
    guard let schema = responseSchema(spec, path: "/testserver/getSingleCondition") else {
        #expect(Bool(false), "Failed to get schema for getSingleCondition")
        return
    }
    #expect(schema.type == "string", "Expected string schema for single condition")
    if case .enum(let enumValues, title: _, description: _, enumNames: _, defaultValue: _) = schema {
        #expect(enumValues == ["sunny", "cloudy", "rainy", "snowy"], "Enum values don't match expected values")
    } else {
        #expect(Bool(false), "Expected string schema with enum values")
    }
}

func assertMultipleConditionsSchema(_ spec: OpenAPISpec) {
    guard let schema = responseSchema(spec, path: "/testserver/getMultipleConditions") else {
        #expect(Bool(false), "Failed to get schema for getMultipleConditions")
        return
    }
    #expect(schema.type == "array", "Expected array schema for multiple conditions")
    if case .array(let items, title: _, description: _, defaultValue: _) = schema {
        #expect(items.type == "string", "Expected string schema for array items")
        if case .enum(let enumValues, title: _, description: _, enumNames: _, defaultValue: _) = items {
            #expect(Set(enumValues) == Set(["sunny", "cloudy", "rainy", "snowy"]),
                   "Array items enum values don't match expected values")
        } else {
            #expect(Bool(false), "Expected string schema with enum values for array items")
        }
    } else {
        #expect(Bool(false), "Expected array schema")
    }
}

func assertBasicArraySchema(_ spec: OpenAPISpec) {
    guard let schema = responseSchema(spec, path: "/testserver/getBasicArray") else {
        #expect(Bool(false), "Failed to get schema for getBasicArray")
        return
    }
    #expect(schema.type == "array", "Expected array schema for basic array")
    if case .array(let items, title: _, description: _, defaultValue: _) = schema {
        #expect(items.type == "string", "Expected string schema for array items")
    } else {
        #expect(Bool(false), "Expected array schema")
    }
}

extension JSONSchema {
    var type: String {
        switch self {
        case .string: return "string"
        case .number: return "number"
        case .boolean: return "boolean"
        case .array: return "array"
        case .object: return "object"
        case .enum: return "string"
        case .oneOf: return "oneOf"
        }
    }
}
