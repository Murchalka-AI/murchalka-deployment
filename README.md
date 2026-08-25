# Murchalka Deployment

Phase 5 Minimal Core profile, deterministic bindings, module configuration, and local Compose topology.

## Start

1. Place the twelve signed Phase 5 bundles plus Storage SQLite and Secrets Local bundles in `runtime/modules/inbox`.
2. Copy `.env.example` to `.env` and pin released image versions.
3. Start Ollama and Runtime with `docker compose -f compose/compose.yaml up -d`.
4. Bootstrap one Person, Character Identity, and Local Auth credential through an administrative capability client.
5. Open the Web shell and connect to `ws://127.0.0.1:5080/v1/realtime`.

The Runtime control API stays on loopback. The realtime module also binds loopback-only. Canonical `vX.Y.Z` tags publish an immutable deployment archive.

