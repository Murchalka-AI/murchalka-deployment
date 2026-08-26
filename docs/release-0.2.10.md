# Coordinated release 0.2.10

Release `v0.2.10` is a Deployment-only correction for deterministic administrative bootstrap readiness. It keeps the verified Runtime image pinned to `v0.2.5` and all other Minimal Core components pinned to their existing immutable releases.

The bootstrap script now waits for the People, Character Identity, and Local Auth capabilities before sending state-changing requests. Each idempotent request is sent once from standard input after readiness, avoiding unsafe retries of a request body that cannot be rewound.

Administrative failures report the capability, HTTP status, and response body. A readiness timeout reports every missing bootstrap capability and the complete Runtime module lifecycle snapshot.

Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
