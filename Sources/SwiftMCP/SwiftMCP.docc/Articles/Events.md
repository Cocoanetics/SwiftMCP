# Events

MCP Events let a server advertise application events and deliver them to
subscribers over signed HTTPS webhooks. They are available on the modern
protocol revision (`2026-07-28`) only. For how Events relate to
`subscriptions/listen` and existing JSON-RPC notifications, see
<doc:Events-vs-Listen>.

## Declare an event

Annotate a function with ``MCPEvent``. Its parameters become the subscriber
filter (`inputSchema`); its return type becomes the delivered payload
(`payloadSchema`). Pass `name:` when the wire name should differ from the
function name (for example a dotted name such as `ci.failed`):

```swift
@Schema
struct CIFailedPayload: Sendable, Codable {
    let pipeline: String
    let branch: String
    let commit: String
    let url: String
    let message: String
}

@MCPServer
actor BuildServer {
    /// A continuous-integration run failed.
    /// - Parameter pipeline: Only failures from this pipeline.
    @MCPEvent(name: "ci.failed", delivery: ["webhook"])
    func ciFailed(pipeline: String? = nil) -> CIFailedPayload {
        CIFailedPayload(pipeline: "", branch: "", commit: "", url: "", message: "")
    }
}
```

Publish matching occurrences with ``MCPEventProviding/emit(_:_:eventId:attributes:cursor:)``.
The call validates the payload, finds active subscriptions whose filter matches,
and POSTs a Standard Webhooks–signed body to each callback URL.

## Client API

``MCPServerProxy`` exposes era-gated helpers that map to `events/list`,
`events/subscribe` and `events/unsubscribe`:

```swift
let proxy = MCPServerProxy(config: .stdioHandles(server: server))
proxy.meta["accessToken"] = .string("alice")  // required for subscribe/unsubscribe
try await proxy.connect()

let events = try await proxy.listEvents()
let delivery = EventsWebhookDelivery(
    url: "https://receiver.example.com/hook",
    secret: WebhookSigner.generateSecret()
)
let subscription = try await proxy.subscribeEvent(
    name: "ci.failed",
    arguments: .object(["pipeline": .string("main")]),
    delivery: delivery
)
try await proxy.unsubscribeEvent(
    name: "ci.failed",
    arguments: .object(["pipeline": .string("main")]),
    delivery: EventsWebhookDelivery(url: delivery.url)
)
```

On a legacy connection these methods throw before sending a request. Subscribe
requires an authenticated principal; set ``MCPServerProxy/meta`` with an
`accessToken` (or connect over an authenticated transport) so the subscription
is bound to a stable owner.

## ChatGPT Work

ChatGPT Work can subscribe to the same webhook Events. A manual interop checklist
lives in the repository at `docs/chatgpt-work-events-runbook.md`.
