protocol SchemaOrCaseIterable: SchemaRepresentable, CaseIterable {}

protocol ArrayElementSchema {
    static var arrayElementSchema: JSONSchema { get }
}

extension SchemaRepresentable {
    static var arrayElementSchema: JSONSchema {
        return schema
    }
}

extension CaseIterable {
    static var arrayElementSchema: JSONSchema {
        return .string(enumValues: caseLabels)
    }
}

extension Array: SchemaRepresentable {
    public static var __schemaMetadata: SchemaMetadata {
        return .init(name: "Array", parameters: [])
    }
    
    public static var schema: JSONSchema {
        let elementSchema: JSONSchema
        
        if let schemaType = Element.self as? any SchemaRepresentable.Type {
            elementSchema = schemaType.schema
        } else if let caseIterableType = Element.self as? any CaseIterable.Type {
            elementSchema = .string(enumValues: caseIterableType.caseLabels)
        } else if Element.self == Int.self || Element.self == Double.self || Element.self == Float.self {
            elementSchema = .number()
        } else if Element.self == Bool.self {
            elementSchema = .boolean()
        } else {
            elementSchema = .string()
        }
        
        return .array(items: elementSchema)
    }
} 
