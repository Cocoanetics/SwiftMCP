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
| `notifications/message` (log) | `Session.sendLogNotification` | `MCPServerProxyLogNotificationHandling`, installed with `setLogNotificationHandler(_:)`; filtered by session log level (legacy) or per-request `logLevel` (modern) |
| `notifications/tools/list_changed`, `notifications/resources/list_changed`, `notifications/prompts/list_changed` | `Session` helpers and `SessionManager` broadcasting | Legacy: sessions on the standalone GET stream. Modern: `subscriptions/listen` streams |
| `notifications/resources/updated` | `Session.sendResourceUpdated`, `SessionManager` broadcasting | Clients subscribed to the URI (`resources/subscribe` legacy, `subscriptions/listen` modern) |
| `notifications/subscriptions/acknowledged` | `MCPServer` listen handling | The client that opened `subscriptions/listen` |
| `notifications/cancelled` (received) | — | The server, to cancel in-flight requests |
| Application-defined methods, such as `notifications/runStatusChanged` | An application server | Typed client handlers registered with `MCPServerProxy.setNotificationHandler(_:as:handler:)` |

The README's `RunStatusUpdate` example uses `setNotificationHandler(_:as:handler:)` to receive `notifications/runStatusChanged`. `Tests/SwiftMCPTests/ProxyLogNotificationTests.swift` exercises both that custom notification path and the log-notification handler. These are existing consumers of structured JSON-RPC notifications, not webhook subscriptions.

`LogMessage.data` can also carry structured JSON. The demo server uses it for roots-change logs in `DemoServer.swift` and elicitation diagnostics in `DemoServer+ElicitationSchemas.swift`. Those messages remain logging, even when their data is structured.

## Migration decision

- **Built-in notifications stay JSON-RPC notifications.** Progress is tied to a request token, logs remain observability messages, and list-changed and resource-updated notifications feed `subscriptions/listen` on modern connections. Cancellation and listen acknowledgements remain protocol control messages. Tool responses also remain tied to their requests.
- **Prefer Events for durable subscribed application events.** A domain event such as a failed CI run can move from a custom notification to a named, schema-defined event when subscribers need asynchronous webhook delivery beyond the lifetime of a connection. Subscription filters, callback verification, renewal and signed delivery are part of that migration; Events are not a drop-in replacement for an arbitrary JSON-RPC notification.
- **Existing custom handlers stay supported.** `setNotificationHandler(_:as:handler:)` remains appropriate for application notifications consumed over an open connection, including the README's `notifications/runStatusChanged` example. Applications can adopt Events for suitable use cases without changing existing notification consumers.
- **No deprecation or automatic compatibility adapter.** This change does not mirror Events onto legacy notification methods or turn existing notifications into webhook deliveries. Applications that adopt Events retain their existing notification path for older clients as needed; Events require the modern protocol profile described below.

## Protocol and version gating

Events are a modern-era feature only: ``MCPFeature/events`` is in the `2026-07-28` profile and absent from every legacy profile (`2024-11-05` through `2025-11-25`). Runtime code must branch on `profile.has(.events)` rather than on version strings. Legacy sessions keep their existing notification behaviour unchanged.
