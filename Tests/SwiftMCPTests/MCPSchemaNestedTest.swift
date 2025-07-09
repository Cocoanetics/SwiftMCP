import Foundation
import Testing
@testable import SwiftMCP

@Test("Nested @Schema annotations work correctly")
func testNestedSchemaAnnotations() {
    // Test that ModelPreferences has schema metadata
    let preferencesMetadata = ModelPreferences.schemaMetadata
    #expect(preferencesMetadata.name == "ModelPreferences")
    #expect(preferencesMetadata.description == "Represents model preferences for sampling requests.")
    
    // Should have properties for hints, costPriority, speedPriority, intelligencePriority
    #expect(preferencesMetadata.parameters.count == 4)
    
    let hintProperty = preferencesMetadata.parameters.first { $0.name == "hints" }
    #expect(hintProperty != nil)
    #expect(hintProperty?.isRequired == false) // Optional array
    
    // Test that ModelHint has its own schema metadata
    let hintMetadata = ModelPreferences.ModelHint.schemaMetadata
    #expect(hintMetadata.name == "ModelHint")
    #expect(hintMetadata.description == "Model hints for preference matching.")
    
    // Should have one property: name
    #expect(hintMetadata.parameters.count == 1)
    
    let nameProperty = hintMetadata.parameters.first { $0.name == "name" }
    #expect(nameProperty != nil)
    #expect(nameProperty?.isRequired == true) // Non-optional String
} 