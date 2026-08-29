# Release 0.4.0 — Phase 7 Client Runtime

This coordinated release adds product-agnostic signed Client Extensions, an atomic Runtime catalog with SSE revision notifications, content-addressed artifact delivery, server-validated Client Actions, accessible declarative rendering, networkless bounded WASM, persistent verified offline cache, and thin Web/Desktop TypeScript shells.

## Acceptance evidence

- Runtime publishes and retracts active artifacts atomically without restart.
- Web and Desktop verify artifact digest, publisher signature, target and schemas before activation.
- Corrupt or unsigned revisions leave the prior UI active.
- Unsupported targets receive an accessible standard fallback.
- Client Diagnostics renders the WASM proof value `7` and delegates its action to the authenticated server boundary.
- Tag workflows publish NuGet, npm, signed module bundles, web container/archive, and native Desktop artifacts with provenance attestations.

The immutable component pins are recorded in `releases/client-runtime.lock.json`. Client Runtime, Web and Desktop use `v0.4.1` repair tags without moving their original `v0.4.0` tags. Client Diagnostics uses `v0.4.2`: its bounded quality job runs before the cross-platform matrix, package authentication is shell-independent, and each self-contained publish receives a matching RID-specific restore.
