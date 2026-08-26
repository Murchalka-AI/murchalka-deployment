# Coordinated release 0.2.14

Release `v0.2.14` pairs Deployment with Runtime `v0.2.14` to support capability-free nested network isolation on Docker hosts that reject self-written user namespace identity maps.

The Runtime image includes a minimal native network-namespace launcher. It creates the child user and network namespaces, then writes the child's single-identity UID/GID maps from the parent namespace before executing Bubblewrap. This follows the parent-mapping pattern required by the kernel without setuid helpers, `NET_ADMIN`, additional container capabilities, or privileged mode.

Modules without approved network permission inherit the launcher's empty network namespace. Bubblewrap shares that namespace, explicitly drops all capabilities, and applies the existing filesystem, PID, IPC, UTS, cgroup, and process isolation. The one-shot `sandbox-probe` executes the exact same native-launcher → Bubblewrap path before Runtime starts.

Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
