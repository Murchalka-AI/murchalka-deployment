# Coordinated release 0.3.0

Release `v0.3.0` completes Phase 6 by adding the Node Runtime, Node Controller, Admin Node operations, shared Node protocol and SDK packages, and the signed multi-target Node Diagnostics bundle. The Runtime also becomes target-aware so Node-only providers are never registered as local Runtime providers.

Deployment publication is gated by both acceptance paths. Phase 5 reuses the immutable Web and module releases pinned in `releases/minimal-core.lock.json` while validating Runtime `v0.3.0`. Phase 6 runs the `v0.3.0` Node images and diagnostics bundle through enrollment, private-CA mTLS, distribution, isolated activation, execution, revocation, reconnect denial, and denial of new tasks.

The dependency release waves publish Module Protocol first, Module SDK second, Runtime and Node-facing components third, and Deployment last. Canonical Git tags remain immutable and every changed repository verifies its source before publishing packages, archives, bundles, provenance, or container images.
