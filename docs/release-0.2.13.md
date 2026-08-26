# Coordinated release 0.2.13

Release `v0.2.13` pairs Deployment with Runtime `v0.2.13` to support capability-free nested network isolation on container hosts that deny Bubblewrap permission to configure loopback interfaces.

Modules without an approved network permission are launched inside an empty network namespace created by unprivileged `unshare`. Bubblewrap shares that already-isolated namespace, so it does not issue privileged loopback configuration requests. Modules with an approved loopback permission or listener retain their existing network path. Bubblewrap explicitly drops all Linux capabilities before every module entrypoint starts.

The Runtime container remains non-root, keeps `cap_drop: ALL`, and does not receive `NET_ADMIN` or `privileged` access. The one-shot `sandbox-probe` now executes the same `unshare` → Bubblewrap sequence before Runtime starts.

Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
