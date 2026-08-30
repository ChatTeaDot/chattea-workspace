# ChatTea Production Readiness Design

## Goal

Close the seven remaining production blockers without weakening existing authentication, concurrency, migration, or mobile performance guarantees. Code must remain fail-closed when external services are not configured, and every non-trivial behavior must be introduced test-first.

## Decisions

- Implement the complete internal flows now; do not fake success when RevenueCat, Expo, R2, GHCR, or native project credentials are absent.
- A refunded consumable that has already been spent creates a negative balance. Future grants first repay that debt.
- Keep the current `features/native` implementation as the canonical mobile implementation and delete unreachable legacy feature slices and their obsolete tests.
- Build the backend container once in GitHub Actions and deploy the immutable digest. The VPS must not rebuild production source.
- Add only dependencies that replace security-sensitive custom protocol code or are required by a native integration.

## 1. Billing

### Backend

Add an append-only RevenueCat transaction ledger keyed by provider transaction identity. Each row records the user, canonical and provider product IDs, granted units, event timestamp, and current purchase state. Webhook processing remains idempotent by event ID and additionally serializes per provider transaction.

- Purchase grants credits exactly once.
- Refund cancellation reverses the original grant exactly once. Balances may become negative when the user already spent the grant.
- Refund reversal restores the exact original grant once.
- Out-of-order events are resolved by provider event timestamp, without deleting ledger history.
- Unsupported transfer and virtual-currency semantics continue to fail explicitly.

### Mobile

Add RevenueCat's native SDK. Configure it only when a platform public SDK key is present, identify the customer with the authenticated ChatTea UUID, load offerings, purchase packages, restore purchases, and refresh backend balance/subscription state. When configuration is absent, purchase controls are disabled with a configuration message rather than pretending a purchase can start.

## 2. Push Notifications

### Backend

Create a durable push outbox. Creating an in-app notification and its push job must be one database transaction. A worker claims bounded batches with `FOR UPDATE SKIP LOCKED`, sends at most 100 Expo messages per request, validates every ticket, stores ticket IDs, checks receipts after the required delay, removes permanently invalid tokens, and retries transient failures with bounded exponential backoff. Domain requests never await Expo.

### Mobile

Add `expo-notifications`. Request permission only after an authenticated session exists, obtain the Expo token using the configured EAS project ID, register token rotation, handle foreground notification responses, and unregister the installation's token on logout. Missing project identity disables remote push registration without breaking in-app notifications.

## 3. Verified Profile Uploads

Replace direct trust in a public URL with a pending-upload state machine.

1. The authenticated user requests a staging upload.
2. The server records key, expected MIME, expected length, owner, and expiry.
3. The client uploads to the short-lived staging URL and calls finalize.
4. The server reads the R2 object, verifies size and decodability, strips metadata, re-encodes it to a supported safe format, writes the final object, deletes the staging object, and marks the row verified.
5. Profile updates accept only verified, unexpired final objects owned by that user.

Use the official S3 client for R2 access and `sharp` for decode/re-encode instead of expanding hand-written SigV4 and image parsers. Failed and abandoned staging objects are removed by the maintenance worker.

## 4. Account Deletion Maintenance

Remove cleanup scheduling from the API service. Add a dedicated maintenance process using the same production image. It runs immediately, then at a fixed interval, and performs bounded batches under a PostgreSQL advisory lock. Rows are claimed with database locking so multiple workers cannot anonymize the same account concurrently. Failures use structured logs and retry on the next cycle; the process never swallows errors silently. The same worker expires upload staging rows and advances push receipt jobs.

## 5. Frontend Graph Cleanup

Keep `src/features/native` and the active authentication/shared infrastructure. Delete the unreachable `chat`, `community`, `likes`, `match`, and `profile` legacy trees after moving any uniquely used pure helper into the canonical implementation. Remove tests that only exercise deleted code and add a route-reachability test that fails when a production source subtree is not reachable from Expo Router roots unless explicitly allowlisted as a build-time entry.

## 6. Immutable Release Artifact

GitHub Actions builds one multi-platform-compatible backend image tagged with the workspace commit, emits provenance and an SBOM, scans it, signs it with GitHub OIDC, and pushes it to GHCR. Deployment passes the resulting digest to Compose, authenticates the VPS to GHCR with a read-only token when needed, pulls the digest, migrates, starts with `--no-build`, and health-checks. Rollback pulls the previous recorded digest; it never rebuilds source. Node and PostgreSQL base images remain digest pinned.

Native release stays fail-closed until the real EAS project identity and platform signing are configured. CI continues Metro exports and adds config/prebuild validation; a production claim requires actual Gradle/Xcode or EAS build gates.

## 7. Online Index Migrations

Extend the migration runner with an explicit file header for non-transactional migrations. Such migrations run under the existing session advisory lock but outside `BEGIN`; they must be idempotent and record history only after success. Add PostgreSQL tests proving transactional rollback, concurrent runner serialization, non-transactional execution, failure retry, and history integrity.

All future live-table indexes use `CREATE INDEX CONCURRENTLY`. The current unreleased query-index migration will be exercised against a fresh PostgreSQL database before release. An already-applied local review database is not mutated destructively; compatibility is verified separately.

## Parallel Ownership

- Backend state machines: billing ledger, push outbox, verified uploads, shared schema and migrations.
- Mobile graph: RevenueCat, Expo notifications, route cleanup, frontend package lock.
- Operations: maintenance worker, migration runner, GHCR workflow and Compose deployment.
- Controller: integration, conflict resolution, independent review, full static/unit/PostgreSQL/native/Docker verification.

Only the backend state-machine owner edits database schema files. Only the mobile owner edits the frontend package manifest and lockfile. Only the operations owner edits root workflows and migration-runner scripts.

## Verification

- Test-first unit tests for every state transition and parser.
- PostgreSQL tests for duplicate, concurrent, reversed, stale, failed, and retry paths.
- Frontend tests for disabled configuration, purchase/restore calls, push registration lifecycle, and production route reachability.
- Frozen installs, audits, lint, formatting, strict typechecks, and builds for both projects.
- iOS and Android production exports plus Expo config/prebuild validation.
- Docker build, production preflight, migrations, maintenance process, API health, non-root PID 1.
- Workflow lint, shell syntax, immutable action/image references, and deployment/rollback dry-run assertions.

## External Completion Inputs

The implementation can be complete without storing secrets in Git. Live end-to-end certification still requires real RevenueCat platform keys/products, an Expo EAS project ID and device, Apple/Google signing, GHCR VPS read credentials if the image is private, and production R2 credentials. Until each input exists, its path remains visibly disabled or fail-closed.

## Non-goals

- No custom payment processor, push provider, image codec, container registry, or job framework.
- No unrelated UI redesign.
- No commit, push, deployment, package publication, or modification of existing untracked user files as part of implementation.
