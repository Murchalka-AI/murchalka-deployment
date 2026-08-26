# Coordinated release 0.2.12

Release `v0.2.12` is a Deployment-only correction for rootless module sandbox creation inside the released Runtime container. It keeps the verified Runtime image pinned to `v0.2.5` and all other Minimal Core components pinned to their existing immutable releases.

The Runtime still runs as a non-root user with every outer Linux capability dropped. The Compose profile now uses the host user-namespace mode and relaxes only the container restrictions required for nested rootless Bubblewrap namespaces and mounts: seccomp, AppArmor, and protected system paths.

A one-shot `sandbox-probe` service executes Bubblewrap under the same user-namespace, security-option, filesystem, and capability constraints as Runtime. Runtime starts only after this probe succeeds, so an incompatible Docker host fails immediately with Bubblewrap diagnostics instead of reporting a delayed cascade of module dependency failures.

Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
