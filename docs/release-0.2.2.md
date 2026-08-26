# Coordinated release 0.2.2

Release `v0.2.2` is ordered and immutable. Protocol remains pinned to its compatible `v0.2.1` packages. The interactive coordinator publishes SDK and ProcessHost first, waits for those packages, and then publishes the changed Runtime, Web, and modules. Deployment is tagged only after every component Release referenced by `releases/minimal-core.lock.json` exists.

The component lock deliberately keeps unchanged Minimal Core modules on `v0.2.1` and pins changed or newly introduced components to `v0.2.2`. A coordinated deployment release therefore does not require meaningless rebuilds of unchanged repositories.

The deployment release workflow blocks publication until the released-artifact Phase 5 gate passes the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit path.

Create the three empty GitHub repositories before running the coordinator:

- `murchalka-module-model-catalog`
- `murchalka-module-model-router-basic`
- `murchalka-module-observability`

Do not initialize those remote repositories with generated README or license commits; their local repositories already contain the canonical initial content.
