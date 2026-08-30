# Release 0.5.1 — Protocol Modules Fix-Forward

> Superseded for Deployment only by the immutable `v0.5.2` fix-forward described in `release-0.5.2.md`. SDK, Gateway, MCP, and A2A `v0.5.1` remain the coordinated component releases.

The immutable Gateway `v0.5.0` tag failed its Windows TLS integration gate because Windows Schannel cannot use a server certificate imported with `X509KeyStorageFlags.EphemeralKeySet`. Gateway `v0.5.1` uses a temporary OS-backed key on Windows and macOS and retains in-memory-only key storage on Linux. Certificate and secret byte buffers remain zeroed, and the certificate is disposed when the listener stops.

The published `Murchalka.ModuleSdk.ProcessHost 0.5.0` package predates the serialized process-host writer present in the `v0.5.0` source tag. Concurrent protocol replies and granted dependency invocations can therefore interleave length-prefixed JSON frames and terminate MCP or A2A processes. SDK `v0.5.1` publishes the corrected writer and adds concurrent-frame regression coverage. MCP and A2A `v0.5.1` embed the corrected SDK package; their module, client-extension, provenance, and SBOM versions advance together.

Before creating immutable tags, push reviewed commits without tags and wait for every branch CI job in the five changed repositories, especially the Gateway Windows TLS matrix. Then run `python3 scripts/coordinated-release.py` once and select `murchalka-module-sdk`, `murchalka-module-protocol-gateway`, `murchalka-module-protocol-mcp`, `murchalka-module-protocol-a2a`, and `murchalka-deployment`. Use commit message `fix: stabilize Phase 8 protocol acceptance`, tag `v0.5.1`, and remote `origin`. The coordinator publishes SDK first and waits for its immutable package release before tagging Gateway, MCP, and A2A; Deployment is tagged only after all selected component releases exist. Protocol, Runtime, Admin, and TypeScript clients remain pinned to their existing successful releases.

Never delete or move `v0.5.0` or `v0.5.1`. Published component releases remain immutable; subsequent corrections use a new patch tag.
