# Coordinated release 0.3.4

Release `v0.3.4` completes the Phase 6 acceptance path. Node Diagnostics now derives its protocol identity from the version stamped into the release assembly, so the process handshake always matches the signed bundle manifest. Node Runtime now preserves the child process exit code and bounded standard error when an artifact fails before its initial `Hello` frame.

The immutable component lock pins Node Runtime and Node Diagnostics to `v0.3.4`. The successful Phase 5 Runtime and all 17 Minimal Core modules remain pinned to `v0.3.3`; Node Controller and Admin remain pinned to `v0.3.2`; Module Protocol and Module SDK remain compatible at `v0.3.0`.

Publish `murchalka-node-runtime` and `murchalka-node-diagnostics` first. Publish `murchalka-deployment` last so its Phase 5 and Phase 6 acceptance gates consume the immutable releases from the component lock.
