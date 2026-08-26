# Coordinated release 0.2.8

Release `v0.2.8` is a Deployment-only correction for the least-privilege Runtime bootstrap loader. It keeps the verified Runtime image pinned to `v0.2.5` and all other Minimal Core components pinned to their existing immutable releases.

The loader applies owner-only modes exclusively to the security files and grants directory it creates. It does not require `CAP_FOWNER`; its capability set remains limited to `CHOWN` and `DAC_OVERRIDE` before it exits and the non-root Runtime starts.

Failure cleanup now emits container logs before removing the Compose containers, so errors from one-shot initialization services are retained in CI output.

Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
