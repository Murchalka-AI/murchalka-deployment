# Coordinated release 0.2.5

Release `v0.2.5` is an immutable patch release for Linux Runtime process identity verification. Runtime and Deployment advance to `v0.2.5`; Web and the Phase 5 modules remain pinned to their verified `v0.2.2` or `v0.2.1` releases in `releases/minimal-core.lock.json`.

Runtime creates its private `/tmp` mount before binding module bundles, state, and gateway sockets. This preserves explicit paths located below the host temporary directory when Bubblewrap applies mount operations in order.

Ubuntu 24.04 CI and release jobs install and load the restricted `bwrap-userns-restrict` AppArmor profile when unprivileged user namespaces are restricted. A real Bubblewrap sandbox self-test runs before the .NET build, producing the launcher error directly instead of allowing opaque module activation failures later.

The module gateway authenticates the Linux Unix-domain-socket peer with `SO_PEERCRED`, verifies that the peer belongs to the launched Bubblewrap process tree, and maps the module's namespace-local PID through `/proc/<pid>/status`. This preserves strict process identity validation across Bubblewrap PID namespaces without weakening the signed protocol handshake.

The Runtime container drops every outer Linux capability and remains read-only with `no-new-privileges`. Its outer seccomp and AppArmor profiles are explicitly unconfined so rootless Bubblewrap can create the inner user and mount namespaces used to isolate each module process.

Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
