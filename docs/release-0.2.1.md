# Coordinated release 0.2.1

Create annotated `v0.2.1` tags only after every repository is green at the same commit intended for release. Published tags and artifacts are immutable.

## Order

1. Publish `murchalka-module-protocol` so the `0.2.1` Contracts, Json, Client, Transport, and Grpc packages exist.
2. Publish `murchalka-module-sdk` so the `0.2.1` Abstractions and Testing packages exist.
3. Publish `murchalka-runtime`, the fourteen Minimal Core module providers, and `murchalka-web`. These releases may run in parallel after steps 1 and 2 complete.
4. Publish `murchalka-deployment` last, after the Runtime and Web container tags and every Linux x64 module bundle are available.
5. Run the deployment repository's `Phase 5 E2E` workflow for version `0.2.1`. Treat this released-artifact gate as required promotion evidence.

The fourteen module repositories are People, Character Identity, Conversations, Sessions, Agent Runtime, Context, Model Ollama, Auth Local, Authorization, Audit Store, Agent UI, Protocol Client Realtime, Storage SQLite, and Secrets Local.

Do not retag a failed release. Fix forward with a new patch version and update the deployment image pins and profile metadata together.
