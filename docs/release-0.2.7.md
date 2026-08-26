# Coordinated release 0.2.7

Release `v0.2.7` is a Deployment-only correction for Runtime bootstrap security-file ownership. It keeps the verified Runtime image pinned to `v0.2.5` and all other Minimal Core components pinned to their existing immutable releases.

Docker Compose file-backed secrets preserve host ownership and do not implement the requested `uid`, `gid`, or `mode` attributes. The one-shot module loader now copies the administrative token, publisher trust, and digest-bound permission grants into the private Runtime volume, applies owner-only permissions, transfers ownership to the Runtime image's unprivileged application user, and exits before Runtime starts.

The Runtime container remains non-root, read-only, and stripped of every outer Linux capability. The sensitive bootstrap files are not exposed through environment variables or made world-readable.

The acceptance script detects an early Runtime restart and reports container logs immediately instead of waiting for the complete readiness timeout.

Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
