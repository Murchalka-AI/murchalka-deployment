# Coordinated release 0.2.15

Release `v0.2.15` pairs Deployment with Runtime `v0.2.15` and removes the nested user-namespace requirement from the capability-free network sandbox.

The native launcher maps namespace root to the non-root container identity and enters an empty network namespace. Bubblewrap reuses those user and network namespaces instead of applying `--unshare-all`, which would request a second user namespace on hosts that prohibit nested unprivileged user namespaces.

Filesystem, PID, IPC, UTS, optional cgroup, session, and parent-death isolation remain active. Bubblewrap explicitly drops all capabilities before starting the module. The one-shot `sandbox-probe` executes the same launcher and namespace arguments before Runtime starts.

Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
