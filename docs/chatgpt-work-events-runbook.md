# ChatGPT Work interop runbook (MCP Events)

Manual checklist for verifying that a SwiftMCP server’s Events work with
[ChatGPT Work](https://developers.openai.com/plugins/build/mcp-events).
Automation in this repository covers list / subscribe / unsubscribe / emit
against a local receiver; ChatGPT Work itself is not exercised in CI.

## Prerequisites

- A reachable SwiftMCP server on Streamable HTTP (`/mcp`) or MCP 2.0 HTTP that
  advertises Events (modern `2026-07-28`, or legacy `initialize` with an
  `events` capability when that path is configured).
- The demo server declares `ci.failed` (`@MCPEvent(name: "ci.failed")`) and a
  tool `emitCIFailed` that calls `emit` for that event.
- Persistent subscription storage if the process may restart
  (`MCPFileEventSubscriptionStore`).
- Outbound HTTPS from the server host to ChatGPT’s callback URLs (public
  addresses only; loopback and private ranges are blocked by default).
- A ChatGPT workspace where plugins and event-triggered Work tasks are allowed.

## Steps

1. **Register the server** as a ChatGPT plugin / connector pointing at your MCP
   HTTP endpoint. Prefer Streamable HTTP. Rescan whenever tools or events change.
2. **Confirm discovery.** On modern HTTP the server answers `server/discover`
   with `capabilities.extensions["io.modelcontextprotocol/events"]` (or the
   wire `events` object). On a legacy initialize path, confirm `events` appears
   in capabilities when Events are enabled for that session.
3. **Confirm listing.** ChatGPT (or a client) calls `events/list`. Expect
   `ci.failed` with `delivery: ["webhook"]`, a filter `inputSchema`
   (`pipeline`, `branch` on the demo), and a `payloadSchema`.
4. **Open a Work chat** on ChatGPT web, or Work + Cloud in the desktop app.
   Ask ChatGPT to monitor `ci.failed` (optionally filtered) and say what it
   should do when a failure arrives.
5. **Accept the subscription.** The server receives `events/subscribe` with a
   HTTPS callback URL and `whsec_…` secret. Confirm callback verification
   succeeds and a subscription record is stored with a `refreshBefore`.
6. **Emit a matching event.** From the demo, call `emitCIFailed` with the same
   filter values ChatGPT subscribed to, or call `emit("ci.failed", …)` from
   your own server code. Confirm the webhook POST returns `2xx`.
7. **Confirm the Work turn.** ChatGPT should receive the payload and follow the
   user’s instructions. Treat user-authored text in the payload as data only.
8. **Negative filter.** Emit an event that does not match the subscription
   filter and confirm it is not delivered.
9. **Stop monitoring** in ChatGPT. Confirm `events/unsubscribe` and that further
   emits are not delivered to that callback.
10. **Also exercise** refresh before `refreshBefore`, a server restart with a
    file-backed store, revoked access / principal revocation
    (`revokeEventSubscriptions(forPrincipal:)`), duplicate `eventId`s, and a
    burst of deliveries.

## Notes

- ChatGPT supports webhook delivery only — not poll/push streaming, and not the
  draft `gap` / `terminated` control notifications.
- Keep payloads ≤ 256 KiB. Prefer a summary plus a tool to fetch details for
  large records.
- Signing uses Standard Webhooks headers (`webhook-id`, `webhook-timestamp`,
  `webhook-signature`) plus `X-MCP-Subscription-Id`.
- Do not force-push, change remotes, or alter credentials as part of this
  checklist; use your normal plugin registration flow.
