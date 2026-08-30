# ChatTea Production Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` for each behavior and `superpowers:verification-before-completion` before reporting completion.

**Goal:** Close all seven approved production blockers across backend, mobile, and operations without weakening trust boundaries or changing unrelated user work.

**Architecture:** Three workers edit disjoint ownership zones in the shared approved working tree. Backend owns database schema, migrations, backend dependencies, and business state machines. Mobile owns frontend dependencies, native integrations, and graph cleanup. Operations owns the migration runner, maintenance entrypoint, containers, workflows, and deploy scripts. The controller resolves cross-track contracts and performs independent review and full verification.

**Tech stack:** NestJS, Drizzle, PostgreSQL, GraphQL, Expo/React Native, RevenueCat, Expo Notifications, R2/S3, Sharp, Docker Compose, GitHub Actions, GHCR.

**Spec:** `docs/superpowers/specs/2026-08-29-production-readiness-design.md`

## Global Constraints

- Preserve all existing dirty changes and never modify root `error.log` or root `test/`.
- Do not commit, push, deploy, publish packages, or store credentials.
- Use arrow function expressions and no source-code comments.
- Add only the approved official dependencies. Reuse existing helpers and infrastructure first.
- Every state transition, trust boundary, parser, concurrency path, and rollback path starts with a failing runnable test.
- External RevenueCat, Expo, R2, GHCR, and signing paths must remain disabled or fail-closed when configuration is absent.

## Locked Cross-Track Contracts

### Push

- `registerPushToken(input: { token, platform }): Boolean!` uses authenticated user plus the existing validated `x-device-id` header.
- `unregisterPushToken: Boolean!` deletes the authenticated installation by user plus `x-device-id`; repeated calls succeed.
- `NotificationService.processPushOutboxBatch({ now, limit })` and `processPushReceiptBatch({ now, limit })` expose bounded maintenance work.

### Upload

- `createUpload(input) -> { id, putUrl, expiresAt }`; it never returns a usable public URL.
- `finalizeUpload(uploadId) -> { id, publicUrl, contentType, sizeBytes }` returns only a verified final object.
- Profile mutation input uses `photoUploadIds: [ID!]!`; raw client-provided URLs are not a trust boundary.
- `UploadService.cleanupExpiredStagingBatch({ now, limit })` exposes bounded maintenance work.

### Maintenance

- Batch results are structurally `{ claimed, succeeded, retryScheduled, permanentlyFailed, hasMore }`.
- `UserService.processDueAccountDeletionBatch({ now, limit })` owns row claims and anonymization.
- The API process contains no cleanup timer.

## Track A: Backend State Machines

**Exclusive ownership:** `chattea-be/src/modules/database/schema.ts`, `chattea-be/migrations/*.sql`, `chattea-be/package.json`, `chattea-be/pnpm-lock.yaml`, billing/notification/upload/user modules and their tests. Do not edit `scripts/migrate.ts`, maintenance entrypoints, Docker/Compose, or root workflows.

### Task A1: RevenueCat transaction ledger

**Files:** billing module, `schema.ts`, a new ledger migration, billing unit tests, and PostgreSQL billing tests.

1. Add RED tests for transaction ID validation, purchase duplication, spent-credit refund debt, duplicate refund, refund reversal, stale events, timestamp conflicts, owner/product/unit conflicts, and concurrent ordering.
2. Add a transaction projection keyed by provider transaction identity and an append-only transition ledger keyed by provider event.
3. Remove nonnegative balance constraints while preserving `balance > 0` consumption guards.
4. Parse `transaction_id`, `original_transaction_id`, and `cancel_reason`; map consumable purchase to `granted`, customer-support cancellation to `refunded`, and refund reversal to `granted`.
5. In one database transaction: record event hash, take a per-provider-transaction advisory lock, validate immutable identity, resolve timestamp order, apply one signed delta, update projection, and append the transition.
6. Run focused unit and PostgreSQL tests until GREEN, then billing regressions.

### Task A2: Durable Expo push outbox

**Files:** notification module, `schema.ts`, push migration, gateway/processor tests, PostgreSQL notification tests.

1. Add RED tests proving domain requests do not call Expo, notification plus jobs are atomic, claims do not overlap, leases recover, send batches cap at 100, tickets map exactly, receipts never resend, invalid tokens are removed, and retries exhaust.
2. Add installation identity to push tokens and a notification/token outbox with queued, leased, receipt-pending, delivered, permanent, exhausted, and cancelled states.
3. Persist notification and current-token jobs in one transaction when `EXPO_PUSH_ENABLED=true`; otherwise preserve in-app notification only.
4. Use the official Expo server SDK behind a minimal gateway. Keep HTTP outside claim transactions and use `FOR UPDATE SKIP LOCKED` leases.
5. Implement bounded exponential retries, ticket storage, delayed receipts, permanent error classification, and installation unregister.
6. Export the two maintenance batch methods and run focused plus regression tests.

### Task A3: Verified R2 profile uploads

**Files:** upload/user modules, `schema.ts`, upload migration, object-store/image tests, PostgreSQL upload tests.

1. Add RED tests proving create never exposes a public URL, finalize requires ownership, size/MIME/decode checks, metadata stripping/re-encode, lease safety, idempotency, and profile atomicity.
2. Add pending/processing/verified/failed upload state with owner, staging/final keys, expected/final metadata, expiry, and processing lease.
3. Replace hand-written SigV4 with the official S3 client and presigner; read no more than the declared maximum.
4. Decode only JPEG/PNG/WebP/GIF with Sharp, cap input pixels and dimensions, auto-orient, strip metadata, and emit JPEG to a deterministic final key.
5. Make finalize lease-safe and idempotent. A failed staging deletion must not revoke a verified final object but remains cleanup work.
6. Replace profile URL input with verified owned upload IDs inside the profile replacement transaction.
7. Export bounded staging cleanup and run focused plus regression tests.

### Task A4: Backend handoff

Run `pnpm format:check`, `pnpm lint:check`, `pnpm typecheck`, `pnpm build`, focused unit tests, and focused PostgreSQL tests. Report exact commands, results, changed files, remaining external inputs, and any contract deviation.

## Track B: Mobile Integrations and Graph Cleanup

**Exclusive ownership:** all `chattea-fe` files including its manifest/lock. Do not edit backend, root workflows, Compose, or root docs.

### Task B1: Dependencies and native config

1. Add RED app-config tests for the notifications plugin and optional EAS project identity.
2. Add only `react-native-purchases@10.8.1` and the Expo-compatible `expo-notifications` version; update the frontend lockfile.
3. Expose optional platform RevenueCat public keys and optional EAS project ID without fake defaults. Missing values disable only the corresponding feature.

### Task B2: Authenticated RevenueCat lifecycle

1. Add RED tests for absent keys, platform key selection, ChatTea UUID configuration, user switches, stale async results, Android base-plan canonicalization, exact package matching, purchase cancellation, restore, and backend refresh.
2. Share authenticated `me.id` from the native session gate and configure RevenueCat only after it exists.
3. Load current offerings, map only the five backend products, display store price strings, purchase exact packages, and expose restore only through an explicit action.
4. Never grant local entitlement. Refetch backend balance and subscription after purchase/restore.
5. Replace placeholder premium alerts with explicit ready/loading/disabled/error states and accessible disabled controls.

### Task B3: Authenticated push lifecycle

1. Add RED tests for unauthenticated, no-project, denied, register, token rotation ordering, stale callbacks, logout ordering, retries, and safe route parsing.
2. Request permission only after authentication, obtain Expo tokens with project ID, register the installation, serialize rotations, and persist current/pending cleanup state in SecureStore.
3. On ordinary logout, unregister the current installation before clearing session/cache; retain the session on failure so cleanup is retryable.
4. Handle foreground, response-listener, and cold-start notifications once. Allow only the known internal route grammar and reject schemes, query/hash, traversal, malformed UUIDs, and external URLs.

### Task B4: Verified upload client

1. Add RED tests for local validation, create/PUT/finalize ordering, PUT/finalize failure, and ignoring any transitional URL.
2. Upload to the staging URL with exact type/length, finalize by upload ID, and store both final `uploadId` and display URL.
3. Submit only `photoUploadIds` in the profile mutation. Never submit arbitrary URLs as authority.

### Task B5: Delete unreachable graph

1. Move only the uniquely required message-length policy from legacy chat into the canonical native chat implementation and test 30/90-character behavior.
2. Add a RED TypeScript-compiler-API reachability test rooted at Expo Router entries and root `index.ts`.
3. Delete unreachable legacy `chat`, `community`, `likes`, `match`, and `profile` trees, obsolete helpers, exports, mocks, and tests; retain real route redirects and active native code.
4. Keep LegendList in active list screens and preserve the existing performance paths.

### Task B6: Mobile handoff

Run frozen install, both audits, dependency check, all tests, typecheck, lint, format check, Expo public config, and iOS/Android production exports. Report exact results and clearly separate implementation completeness from live RevenueCat/push/device certification.

## Track C: Operations and Immutable Release

**Exclusive ownership:** `chattea-be/scripts/migrate.ts`, migration-runner tests, new maintenance entrypoint/process files, database pool wiring, Dockerfiles/Compose, `.github/**`, root `.gitignore`, and operational docs. Do not edit schema, SQL migrations, package manifests/locks, or mobile app config.

### Task C1: Nontransactional migration runner

1. Add PostgreSQL RED tests for transactional rollback, concurrent runner serialization, one-statement concurrent index success, history-insert failure/retry, unchanged checksum/history, malformed header, and multi-statement rejection without side effects.
2. Accept only the exact BOM-stripped first line `-- chattea:migration-mode=non-transactional`; reject any other reserved mode.
3. Keep the session advisory lock. Run the nontransactional SQL outside `BEGIN` with node-postgres extended query mode so each file can contain exactly one executable statement; record history only after success.
4. Coordinate with Track A to split the unreleased multi-index `0011` into one header plus one `CREATE INDEX CONCURRENTLY IF NOT EXISTS` statement per migration file.

### Task C2: Dedicated maintenance process

1. Add RED unit/PostgreSQL tests for immediate execution, bounded order, failure isolation, no overlap, advisory-lock exclusion, heartbeat, and clean shutdown.
2. Share one managed PostgreSQL pool with Drizzle. Hold one session advisory lock across a cycle and always unlock or destroy the session.
3. Run the four locked service batch methods immediately and then every 60 seconds with an awaited loop, limit 100, one timestamp per cycle, and structured per-job results/errors.
4. Write the maintenance heartbeat only after a completed or explicitly lock-skipped cycle; shutdown on SIGINT/SIGTERM.

### Task C3: Immutable container and deploy

1. Add shell RED tests for digest validation, operation order, migration failure, rollout rollback, rollback failure, traps, and prohibition of production builds.
2. Make the image start API as non-root Node PID 1 without automatic migration. Keep dev Compose migration convenience.
3. Add a production Compose file with no `build:`, one digest image for migrate/API/maintenance, fail-closed environment interpolation, API and heartbeat health checks, and `--no-build` operation.
4. Update CI to validate migration modes, maintenance, production Compose, workflow pins, and Expo config/prebuild.
5. Update release to build the backend once for amd64/arm64, push the commit tag, deploy the output digest, emit/verify provenance and SBOM, scan both platforms, keylessly sign/verify with GitHub OIDC, smoke the exact digest, and deploy through the tested script.
6. Record the successful root revision plus digest atomically. Roll back the app artifact/revision only; never reverse migrations.

### Task C4: Operations handoff

Run shell syntax/tests, workflow lint, production Compose config, migration PostgreSQL tests, maintenance tests, Docker build/smoke, and relevant CI-equivalent commands. Report exact results and missing live secrets separately.

## Controller Review and Verification

1. Review each track's diff against this plan and the approved design; reject untested or expanded scope.
2. Dispatch independent backend, mobile, and operations reviewers. Fix all verified findings in the owning track.
3. Run a cross-contract review for GraphQL names/types, maintenance interfaces, environment variables, migrations, and container commands.
4. Run full backend and frontend checks, fresh-PostgreSQL migrations/e2e, Expo config/prebuild/export, Docker production smoke, workflow/shell validation, audits, and `git diff --check`.
5. Report blockers by severity. External credentials/device certification remain explicit external inputs, not false implementation failures.
