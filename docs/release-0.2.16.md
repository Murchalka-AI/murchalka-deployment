# Coordinated release 0.2.16

Release `v0.2.16` pairs Deployment with Runtime `v0.2.16` and makes the capability-free network sandbox portable to container hosts that expose cgroup namespaces but reject nested cgroup namespace creation.

Bubblewrap's `--unshare-cgroup-try` only skips cgroup isolation when the kernel does not expose a cgroup namespace. It still adds `CLONE_NEWCGROUP` when the namespace exists, allowing a host-level `EPERM` to fail the combined namespace clone. The Runtime rootless path now retains its container cgroup namespace while continuing to isolate mount, PID, IPC, UTS, user, network, session, filesystem, and process capabilities.

The one-shot `sandbox-probe` uses the same namespace set as Runtime. Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
