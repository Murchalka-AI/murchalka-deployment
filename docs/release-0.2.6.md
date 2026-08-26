# Coordinated release 0.2.6

Release `v0.2.6` is a Deployment-only correction to the Phase 5 acceptance secret contract. It keeps the verified Runtime image pinned to `v0.2.5` and all other Minimal Core components pinned to their existing immutable releases.

The release workflow explicitly forwards `BUNDLE_PUBLISHER_PUBLIC_KEY_PEM`, `MURCHALKA_BUNDLE_SIGNING_KEY_ID`, and `PHASE5_E2E_PASSWORD` to the reusable acceptance workflow. Deployment receives only the public bundle verification key and never receives the private bundle-signing key.

Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
