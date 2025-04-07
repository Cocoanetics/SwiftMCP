import Foundation

protocol ArrayWithSchemaRepresentableElements {
	static func schema(description: String?) -> JSONSchema
}

extension Array: ArrayWithSchemaRepresentableElements where Element: SchemaRepresentable {
	
	public static func schema(description: String? = nil) -> JSONSchema {
		
		return .array(items: Element.schema, description: description)
	}
}
