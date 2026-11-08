# Events vs. subscriptions/listen

How MCP Events relate to `subscriptions/listen`, and which of SwiftMCP's server-sent notifications stay where they are.

## Overview

Protocol revision `2026-07-28` offers two distinct ways for a server to tell a client that something happened:

| | `subscriptions/listen` | Events (`events/*`) |
|---|---|---|
| Purpose | Stream of *protocol* notifications (list changes, resource updates) | Subscriber-driven delivery of *application* events |
| Transport | A long-lived response stream on the open connection | Webhook: the server POSTs to a subscriber-supplied callback URL |
| Lifetime | Lives as long as the stream | Subscription with expiry; subscriber renews |
| Authentication | The connection | Standard Webhooks signing (`webhook-id`, `webhook-timestamp`, `webhook-signature`) |
| Methods | `subscriptions/listen` | `events/list`, `events/subscribe`, `events/unsubscribe` |

The wire models live in `Models/Events` (``MCPEventsExtension``, ``EventDescriptor``, ``EventsSubscribeParams`` and friends). Servers declare types with ``MCPEvent``, advertise them when the negotiated profile has ``MCPFeature/events``, and deliver matching occurrences with ``MCPEventProviding/emit(_:_:eventId:attributes:cursor:)``. Clients use ``MCPServerProxy/listEvents(cursor:)``, ``MCPServerProxy/subscribeEvent(name:arguments:delivery:cursor:maxAgeMs:ttlMs:)`` and ``MCPServerProxy/unsubscribeEvent(name:arguments:delivery:)``. See <doc:Events>.

## Inventory of what SwiftMCP sends today

| Notification | Sent by | Consumer |
|---|---|---|
| `notifications/progress` | `Session.sendProgressNotification` | The client that issued the request carrying the progress token |
| `notifications/message` (log) | `Session.sendLogNotification` | The client; filtered by session log level (legacy) or per-request `logLevel` (modern) |
| `notifications/tools/list_changed`, `notifications/resources/list_changed`, `notifications/prompts/list_changed` | `Session` helpers and `SessionManager` broadcasting | Legacy: sessions on the standalone GET stream. Modern: `subscriptions/listen` streams |
| `notifications/resources/updated` | `Session.sendResourceUpdated`, `SessionManager` broadcasting | Clients subscribed to the URI (`resources/subscribe` legacy, `subscriptions/listen` modern) |
| `notifications/subscriptions/acknowledged` | `MCPServer` listen handling | The client that opened `subscriptions/listen` |
| `notifications/cancelled` (received) | — | The server, to cancel in-flight requests |

## Migration decision

- **All of the above stay JSON-RPC notifications.** They are protocol-level signals tied to a live connection or request (progress and logs belong to one request; list-changed and resource-updated feed `subscriptions/listen`). Webhook delivery adds nothing for them and cannot carry per-request context.
- **Nothing moves to Events.** Events are for application-defined, durable-subscription events that a subscriber wants delivered while not connected. SwiftMCP has no such built-in notification today, so there is nothing to migrate. If a server author adds one later, it is exposed as an event type, not by repurposing the notifications above.
- SwiftMCP has no custom-notification API beyond the helpers listed, so there is no existing user-defined notification surface to migrate.

## Protocol and version gating

Events are a modern-era feature only: ``MCPFeature/events`` is in the `2026-07-28` profile and absent from every legacy profile (`2024-11-05` through `2025-11-25`). Runtime code must branch on `profile.has(.events)` rather than on version strings. Legacy sessions keep their existing notification behaviour unchanged.
