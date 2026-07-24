# Realtime Features Guide
## Movello Frontend - React Implementation

**Version:** 2.0
**Last verified against code: 2026-07-23**
**Technology:** SignalR (`.NET`/`@microsoft/signalr`), cookie-based auth (no bearer token in the hub URL)
**Primary sources:**
- `src/core/services/notification-hub.ts` (SignalR client)
- `src/stores/notification-store.ts` (Zustand store — connection lifecycle + cache invalidation)
- `src/core/services/notification-service.ts` (REST inbox: list/summary/read/delete)
- `backlog/mvp/epic-11-notification-system.md` (full backend architecture, rewritten 2026-07-23)
- `project-docs/18_Implementation_Coverage_Audit.md` §6, §7.2 (scope-undersell findings)

This replaces the v1.0 guide, which described a hand-rolled `signalRClient` class with `accessTokenFactory`, a generic `notification-store.ts` with client-side toast dispatch by `type`, and three invented events (`BidCountUpdated`, `ContractStatusUpdated`, `WalletBalanceUpdated`) that do not exist anywhere in the codebase. The real system is simpler in shape but broader in scope: **two** event types over **one** hub connection, plus a much larger backend (admin-configurable multi-channel providers, mobile push) than the v1.0 doc implied.

---

## Table of Contents

1. [What's Actually Real vs. What v1.0 Invented](#whats-actually-real-vs-what-v10-invented)
2. [SignalR Hub Connection](#signalr-hub-connection)
3. [The Two Real-Time Events](#the-two-real-time-events)
4. [Notification Store & Cache Invalidation](#notification-store--cache-invalidation)
5. [REST Inbox Endpoints](#rest-inbox-endpoints)
6. [Backend Architecture (Reference)](#backend-architecture-reference)
7. [Mobile Push (Both Flutter Apps)](#mobile-push-both-flutter-apps)
8. [Known Gaps](#known-gaps)

---

## What's Actually Real vs. What v1.0 Invented

| v1.0 claimed | Reality |
|---|---|
| `signalRClient` class with `.on()`/`.off()`, `accessTokenFactory: () => token` | `startNotificationHub()`/`stopNotificationHub()` function pair in `notification-hub.ts`; auth is the `mov_access_token` **HttpOnly cookie** via `withCredentials: true` — there is no token passed into the connection builder at all |
| Generic hub URL `${VITE_WS_URL}/hub` | Fixed relative path `/hubs/notifications` |
| Events: `NotificationReceived`, `BidCountUpdated`, `ContractStatusUpdated`, `WalletBalanceUpdated` | Real events: `ReceiveNotification` and `EntityStatusChanged`. None of the three per-entity-type events exist; `EntityStatusChanged` is a single generic event carrying `{ entityType, entityId }` that the client switches on |
| `useNotificationStore` holds an array of `Notification[]` client-side, computes `unreadCount` locally | Real store holds only `unreadCount` + a fetched `summary` object; the notification list itself lives server-side (`GET /api/notifications/my-notifications`, paginated) — the store is not a local cache of all notifications |
| `NotificationBell` renders from the Zustand array | `NotificationDropdown.tsx` fetches its own list from `notificationService`; the store only tracks the unread badge count and holds the hub connection |
| Manual `setInterval` polling `connection.state` for a "Reconnecting..." banner | `withAutomaticReconnect([0, 2000, 5000, 10000, 30000])` + an `onreconnected` callback that re-fetches the summary and invalidates queries — no polling anywhere |

---

## SignalR Hub Connection

**File:** `src/core/services/notification-hub.ts`

```typescript
import * as signalR from '@microsoft/signalr';

const HUB_URL = '/hubs/notifications';
let activeConnection: signalR.HubConnection | null = null;
let startPromise: Promise<signalR.HubConnection> | null = null;

function buildNotificationConnection(): signalR.HubConnection {
  return new signalR.HubConnectionBuilder()
    .withUrl(HUB_URL, {
      withCredentials: true, // auth via the mov_access_token HttpOnly cookie — no manual token wiring
    })
    .withAutomaticReconnect([0, 2000, 5000, 10000, 30000])
    .configureLogging(signalR.LogLevel.Warning)
    .build();
}

export async function startNotificationHub(
  onReceive: (notification: RealtimeNotificationDto) => void,
  onReconnected: () => void,
  onEntityStatusChanged?: (event: EntityStatusChangedEvent) => void
): Promise<signalR.HubConnection> {
  // guards against duplicate connections + concurrent start() calls (module-level singleton)
  ...
  connection.on('ReceiveNotification', onReceive);
  if (onEntityStatusChanged) {
    connection.on('EntityStatusChanged', onEntityStatusChanged);
  }
  // Backend sends 'Connected' on initial connect as a reconnect hint for mobile clients
  // that suppress background sockets — registered both casings to silence SignalR's
  // "no client method" warning, the payload itself is unused on web.
  connection.on('Connected', () => {});
  connection.on('connected', () => {});
  connection.onreconnected(onReconnected);
  ...
}

export async function stopNotificationHub(connection: signalR.HubConnection): Promise<void> {
  await connection.stop();
}
```

Key points that differ from a naive SignalR setup:
- **No manual token plumbing.** Because auth is an HttpOnly cookie, the client never reads or forwards an access token to the hub — `withCredentials: true` is the entire auth story on web.
- **Module-level singleton with a start-in-flight guard.** `activeConnection`/`startPromise` prevent two callers (e.g. two mounting components) from racing to open a second connection.
- **Backoff schedule is explicit, not the SignalR default.** `[0, 2000, 5000, 10000, 30000]` — reconnect immediately once, then 2s/5s/10s/30s.
- **`Connected`/`connected` no-op handlers exist purely to suppress a console warning**; the actual reconnect-hint logic they support is a mobile-only concern (see backend architecture below).

---

## The Two Real-Time Events

### `ReceiveNotification`

Fired once per new in-app notification for the connected user (server pushes to a per-user SignalR group). Payload: `RealtimeNotificationDto` (`id`, `title`, `body`, category, link, etc.).

### `EntityStatusChanged`

A **second, broader** channel beyond notifications — fired whenever an RFQ, Bid, Contract, LineItem, or Verification changes state, regardless of whether a notification was also sent. Payload shape:

```typescript
interface EntityStatusChangedEvent {
  entityType: 'RFQ' | 'Bid' | 'Contract' | 'LineItem' | 'Verification';
  entityId: string;
}
```

This is the mechanism that keeps RFQ/Bid/Contract list and detail screens live without polling — the web app does **not** re-fetch on a timer anywhere; it invalidates the affected React Query cache keys the moment this event arrives.

---

## Notification Store & Cache Invalidation

**File:** `src/stores/notification-store.ts` (Zustand)

```typescript
export const useNotificationStore = create<NotificationState>((set, get) => ({
  unreadCount: 0,
  summary: null,
  connection: null,

  fetchSummary: async () => {
    const summary = await notificationService.getNotificationSummary();
    set({ summary, unreadCount: summary.unreadCount });
  },

  startHub: async (queryClient?: QueryClient) => {
    if (get().connection) return; // prevent duplicate connections

    const handleReceive = (notification: RealtimeNotificationDto) => {
      get().incrementUnread();
      toast(notification.title, { description: notification.body, duration: 5000 });
    };

    const handleReconnected = () => {
      get().fetchSummary();
      queryClient?.invalidateQueries({ queryKey: ['rfqs'] });
      queryClient?.invalidateQueries({ queryKey: ['bids'] });
      queryClient?.invalidateQueries({ queryKey: ['contracts'] });
      queryClient?.invalidateQueries({ queryKey: ['marketplace-rfqs'] });
      queryClient?.invalidateQueries({ queryKey: ['provider-bids-rfqs'] });
    };

    const handleEntityStatusChanged = queryClient
      ? (event: EntityStatusChangedEvent) => {
          switch (event.entityType) {
            case 'RFQ':
              queryClient.invalidateQueries({ queryKey: ['rfqs'] });
              queryClient.invalidateQueries({ queryKey: ['rfq', event.entityId] });
              queryClient.invalidateQueries({ queryKey: ['marketplace-rfqs'] });
              queryClient.invalidateQueries({ queryKey: ['business-dashboard'] });
              queryClient.invalidateQueries({ queryKey: ['provider-dashboard'] });
              break;
            case 'Bid':
              queryClient.invalidateQueries({ queryKey: ['bids'] });
              queryClient.invalidateQueries({ queryKey: ['bid', event.entityId] });
              queryClient.invalidateQueries({ queryKey: ['provider-bids-rfqs'] });
              queryClient.invalidateQueries({ queryKey: ['provider-dashboard'] });
              queryClient.invalidateQueries({ queryKey: ['rfq'] }); // parent RFQ's bid count
              break;
            case 'Contract':
              queryClient.invalidateQueries({ queryKey: ['contracts'] });
              queryClient.invalidateQueries({ queryKey: ['contract', event.entityId] });
              queryClient.invalidateQueries({ queryKey: ['business-dashboard'] });
              queryClient.invalidateQueries({ queryKey: ['provider-dashboard'] });
              break;
            case 'LineItem':
              // line items are nested in RFQ detail — invalidate all RFQ query variants
              queryClient.invalidateQueries({ queryKey: ['rfq'] });
              queryClient.invalidateQueries({ queryKey: ['rfqs'] });
              queryClient.invalidateQueries({ queryKey: ['marketplace-rfqs'] });
              break;
            case 'Verification':
              queryClient.invalidateQueries({ queryKey: ['admin-verifications'] });
              queryClient.invalidateQueries({ queryKey: ['profile'] });
              queryClient.invalidateQueries({ queryKey: ['business-profile'] });
              queryClient.invalidateQueries({ queryKey: ['provider-profile'] });
              queryClient.invalidateQueries({ queryKey: ['provider-fleet'] });
              break;
          }
        }
      : undefined;

    try {
      const connection = await startNotificationHub(handleReceive, handleReconnected, handleEntityStatusChanged);
      set({ connection });
    } catch {
      // non-fatal — e.g. user not fully registered yet
    }
  },

  stopHub: async () => { /* ... */ },
  incrementUnread: () => set((s) => ({ unreadCount: s.unreadCount + 1 })),
  resetUnread: () => set({ unreadCount: 0 }),
}));
```

Notes:
- The toast on receive is a single `toast(title, { description: body })` call, not a `type`-keyed `toast[type]()` dispatch — there is no `INFO/SUCCESS/WARNING/ERROR` enum on the client model.
- `startHub` takes an **optional** `QueryClient` — if the caller doesn't pass one, the hub still connects and the badge still updates, it just skips cache invalidation. In practice the app root always passes the real query client.
- Reconnect handling does double duty: `onreconnected` (SignalR's built-in "connection recovered" callback) triggers a **blanket** re-fetch of five core query keys to recover from anything missed while offline, on top of whatever per-entity invalidation `EntityStatusChanged` events would have done individually.

### Where the hub is started

The hub is started once per authenticated session (root layout / auth-gated shell), not per-page — individual pages never call `startNotificationHub` themselves. They only need to be registered under keys the invalidation switch above already covers (`['rfqs']`, `['rfq', id]`, `['bids']`, `['contract', id]`, etc.) to get live updates for free.

---

## REST Inbox Endpoints

Backing `notification-service.ts` / `NotificationDropdown.tsx` / the full-page `NotificationsPage.tsx` (business and provider each have their own):

| Endpoint | Purpose |
|---|---|
| `GET /api/notifications/my-notifications` | Paginated inbox list (infinite-scroll on the full page) |
| `GET /api/notifications/my-notifications/summary` | Unread count + recent preview, used for the bell badge and on hub reconnect |
| `PUT /api/notifications/{id}/read` | Mark one notification read |
| `PUT /api/notifications/mark-all-read` | Mark all read |
| `DELETE /api/notifications/{id}` | Delete a notification |

Mobile apps hit a parallel, mobile-specific route set (`mobile/notifications/*`, capped at 50/page, rate-limited) against the **same** underlying `InAppNotification` store — not a separate notification system.

---

## Backend Architecture (Reference)

Full detail lives in `backlog/mvp/epic-11-notification-system.md` (rewritten 2026-07-23); summary for frontend purposes:

- **Four channels, not one:** in-app (SignalR, above), email (SMTP), SMS (Afromessage), push (Firebase Cloud Messaging) — each independently admin-configurable from `Email Providers` / `SMS Providers` / `FCM Providers` admin console pages, with credential rotation and live test-send, none of which the v1.0 doc's "WebSocket optional" framing anticipated.
- **Per-category × per-channel preferences**, not a single on/off switch: 8 categories (RFQ, Bid, Contract, Delivery, Return, Settlement, Wallet, Direct Rental) × 4 channels, stored as JSONB on the business/provider profile. The web Settings → Notifications tab currently exposes **one toggle per category** that sets all 4 channels together — true independent per-channel toggling is supported end-to-end by the data model and every backend event handler, it's just not yet exposed as 4 separate switches in the web UI. Treat this as a UI gap, not a backend limitation, if asked to extend it.
- **~35 event handlers** (`Modules/Notifications/EventHandlers/`) cover account/OTP, RFQ, bidding, contracts, delivery, returns, settlement, wallet, vehicle assignment, verification, and Direct Rental lifecycle events — each independently preference-gated and individually try/caught so one failing handler never blocks the triggering transaction.
- **Mobile push token lifecycle** is a real, separate concern from the web hub: `POST mobile/notifications/push/rebind` (on login / FCM token refresh) and `POST mobile/notifications/push/unregister` (on logout, best-effort). `MOBILE_APP_SPEC.md`'s `POST mobile/me/devices` is stale — that endpoint does not exist.

---

## Mobile Push (Both Flutter Apps)

Both apps request notification permission, initialize `firebase_messaging` + `flutter_local_notifications`, and handle foreground / background-tapped / terminated-launch delivery. Tapping a push notification deep-links via an `actionUrl` in the payload. On login and on FCM token refresh the app calls `push/rebind`; on logout it calls `push/unregister` (failure there never blocks local logout). Mobile inbox screens (`business_notifications_screen.dart`, `provider_notifications_screen.dart`) consume the same `mobile/notifications/*` REST surface described above.

The server also sends mobile clients a `Connected` reconnect hint ~55s after connect (ahead of the server's 60s idle timeout) plus an explicit `Ping`/`Pong` keep-alive, specifically to survive OS-level background socket suppression — this is why the web client's no-op `Connected` handler exists even though web doesn't need the hint itself.

---

## Known Gaps

Carried forward from the 2026-07-23 audit — do not assume these exist without checking first:

- **No delivery-status webhook ingestion** for email/SMS providers (outbox tracks Pending/Delivered/Failed, but nothing updates it from provider callbacks) and **no automated outbox retry worker** — a transient SMTP/SMS failure currently goes unretried. In-app/SignalR delivery is unaffected (it's a direct write + push, not outboxed).
- **No template version history/rollback** for admin-managed notification templates — templates are edited in place.
- **No hard-coded "critical" category** that a user can't fully silence — a business could theoretically disable every channel for "Settlement" today; there's no backend guard against it.
- **Retention is free-form**, not a fixed TTL — notifications persist until the user deletes them; there's no cleanup job. Don't cite a specific retention window without checking again first.
