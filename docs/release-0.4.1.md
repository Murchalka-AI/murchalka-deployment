# Phase 7 coordinated release

Phase 7 is published as a coordinated component set. Run `python3 scripts/coordinated-release.py` from this repository once for each tag group below. The coordinator accepts one tag per run; when Deployment is selected it reads `releases/client-runtime.lock.json`, validates its `components`, and refuses publication until every differently tagged prerequisite already has a matching immutable GitHub Release.

| Repository | Tag |
| --- | --- |
| `murchalka-module-protocol` | `v0.4.1` |
| `murchalka-module-sdk` | `v0.4.1` |
| `murchalka-runtime` | `v0.4.1` |
| `murchalka-module-protocol-client-realtime` | `v0.4.0` |
| `murchalka-client-runtime` | `v0.4.2` |
| `murchalka-web` | `v0.4.2` |
| `murchalka-desktop` | `v0.4.2` |
| `murchalka-module-client-diagnostics` | `v0.4.3` |
| `murchalka-admin` | `v0.4.0` |
| `murchalka-deployment` | `v0.4.1` |

The Desktop artifacts are intentionally unsigned for this release. macOS code signing, Apple notarization, and Windows signing are deferred; no signing secrets are required by the current Desktop release workflow.

Bundle-producing repositories use `MURCHALKA_BUNDLE_SIGNING_KEY_PEM` and `MURCHALKA_BUNDLE_SIGNING_KEY_ID`. Deployment receives only the matching `BUNDLE_PUBLISHER_PUBLIC_KEY_PEM` and key identifier.

## Publication order

Use commit message `feat: complete Phase 7 client runtime and glass UI` for repositories with changes.

1. Publish `murchalka-module-protocol` as `v0.4.1`.
2. Publish `murchalka-module-sdk` and `murchalka-runtime` as `v0.4.1`.
3. Publish `murchalka-client-runtime`, `murchalka-web`, and `murchalka-desktop` as `v0.4.2`.
4. Publish `murchalka-module-client-diagnostics` as `v0.4.3`.
5. Publish `murchalka-deployment` as `v0.4.1`. The coordinator then verifies every component release pinned by the lock.

`murchalka-module-protocol-client-realtime` and `murchalka-admin` have no Phase 7 changes and remain pinned to their existing `v0.4.0` releases.
