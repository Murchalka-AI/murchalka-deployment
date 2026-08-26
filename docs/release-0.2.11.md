# Coordinated release 0.2.11

Release `v0.2.11` is a Deployment-only correction for password transfer between the Phase 5 acceptance and administrative bootstrap scripts. It keeps the verified Runtime image pinned to `v0.2.5` and all other Minimal Core components pinned to their existing immutable releases.

The acceptance script stores the password as a complete newline-terminated input line. Both scripts also accept a final non-empty line terminated directly by end-of-file, avoiding a silent `set -e` exit after `read` has already captured the value.

The password remains confined to owner-only temporary files and standard input. It is not passed through process arguments, environment variables shared with containers, or logs.

Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
