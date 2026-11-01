# Offline queue & recovery

Durable replay is an explicit application decision. Do not queue payments,
non-idempotent actions or transient payloads without a server/storage contract.

## Opt in for one owned mutation

```dart
import 'package:like/like.dart';

final result = await LikeClient().post('/orders',
  body: {'productId': 42, 'quantity': 1},
  withAuth: true,
  offlineSync: true,
  requestConfig: LikeRequestConfig(invalidates: const ['orders']),
);
```

Set the session scope after login first. A queued result reports pending work
through the `offlineQueued` failure/state; do not display it as a confirmed order.

## Replay lifecycle

1. Attempt the mutation with its account/environment identity and operation ID.
2. Persist a replayable action on an eligible transport failure.
3. Startup, reconnect or the next scheduled retry wakes eligible work.
4. Validate owner, payload availability and retry eligibility.
5. Replay with current credentials for the same owner.
6. Remove acknowledged work and invalidate affected resources, or retain blocked/failed metadata.

## Inspect, retry and cancel

```dart
final client = LikeClient();
final tasks = client.offlineTasks;
final queue = client.offlineQueue;
// Subscribe to queue?.taskChanges when a sync screen is open.
// await queue?.retryTask(selectedKey);
// await queue?.cancelTask(selectedKey);
```

Use actual task keys returned by the queue; do not invent them. Cancel owned
subscriptions on screen disposal. Queue controls enforce owner checks, and failure
updates must not resurrect an entry that was cancelled while a request was running.

## Guarantees and limits

- Stable operation IDs survive retries; exactly-once writes require backend support for `Idempotency-Key`.
- Scheduled retries are bounded with backoff and applicable Retry-After handling.
- Multipart byte snapshots default to a 10 MiB limit; larger uploads need an application codec/storage policy.
- Legacy ownerless entries remain blocked for review.
- Timers run while the process is active. This is not a guaranteed OS worker after app termination.
- Public API shops simulate checkout and intentionally disable offline replay for those demo writes.
