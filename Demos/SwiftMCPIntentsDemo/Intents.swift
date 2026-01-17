import AppIntents
import Foundation
import SwiftMCP

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
enum Soup: String, CaseIterable, AppEnum, Codable, Sendable {
    case tomato
    case chicken
    case miso

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Soup"

    static let caseDisplayRepresentations: [Soup: DisplayRepresentation] = [
        .tomato: "Tomato",
        .chicken: "Chicken",
        .miso: "Miso"
    ]
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
@Schema
struct SoupOrder: AppEntity, Identifiable, Codable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Soup Order"
    static var defaultQuery: SoupOrderQuery { SoupOrderQuery() }

    let id: UUID
    let soup: Soup
    let quantity: Int
    let note: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(quantity)x \(soup.rawValue.capitalized)")
    }

    static let sampleOrders: [SoupOrder] = [
        SoupOrder(id: UUID(), soup: .tomato, quantity: 2, note: "Extra hot"),
        SoupOrder(id: UUID(), soup: .miso, quantity: 1, note: nil)
    ]
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
struct SoupOrderQuery: EntityQuery {
    func entities(for identifiers: [SoupOrder.ID]) async throws -> [SoupOrder] {
        SoupOrder.sampleOrders.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SoupOrder] {
        SoupOrder.sampleOrders
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
@MCPAppIntentTool(description: "Orders a soup for delivery.")
struct OrderSoupIntent: AppIntent {
    static let title: LocalizedStringResource = "Order Soup"

    @Parameter(title: "Soup")
    var soup: Soup

    @Parameter(title: "Quantity")
    var quantity: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Order \(\.$soup)") {
            \.$quantity
        }
    }

    func perform() async throws -> some IntentResult {
        _ = quantity
        return .result()
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
@MCPAppIntentTool(description: "Turns the kitchen light on or off.")
struct ToggleKitchenLightIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Kitchen Light"

    @Parameter(title: "On")
    var isOn: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Turn kitchen light \(\.$isOn)")
    }

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
@MCPAppIntentTool(description: "Adds a delivery note for the order.")
struct SetDeliveryNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Delivery Note"

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Set delivery note") {
            \.$note
        }
    }

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
@MCPAppIntentTool
struct ListRecentSoupOrdersIntent: AppIntent {
    static let title: LocalizedStringResource = "List Recent Soup Orders"
    static let description: IntentDescription? = IntentDescription("Lists recent soup orders.")

    func perform() async throws -> some IntentResult & ReturnsValue<[SoupOrder]> {
        .result(value: SoupOrder.sampleOrders)
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
@MCPServer(name: "Intents Demo", version: "0.1")
actor IntentsDemoServer: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OrderSoupIntent(),
            phrases: [AppShortcutPhrase("Order soup")],
            shortTitle: "Order Soup",
            systemImageName: "cup.and.saucer"
        )
        AppShortcut(
            intent: ToggleKitchenLightIntent(),
            phrases: [AppShortcutPhrase("Toggle kitchen light")],
            shortTitle: "Kitchen Light",
            systemImageName: "lightbulb"
        )
        AppShortcut(
            intent: SetDeliveryNoteIntent(),
            phrases: [AppShortcutPhrase("Set delivery note")],
            shortTitle: "Delivery Note",
            systemImageName: "note.text"
        )
        AppShortcut(
            intent: ListRecentSoupOrdersIntent(),
            phrases: [AppShortcutPhrase("List recent soup orders")],
            shortTitle: "Recent Orders",
            systemImageName: "list.bullet"
        )
    }

    @MCPTool(description: "Simple ping for the demo server.")
    func ping() -> String {
        "pong"
    }
}
