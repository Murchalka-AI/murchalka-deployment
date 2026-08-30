# Release 0.5.0 — Protocol Modules

Phase 8 adds a generic installable Protocol Gateway plus independent MCP and A2A bundles. Runtime validates and catalogs generic protocol contributions and grants the gateway only resolved handler endpoints; it contains no MCP or A2A parser or route.

MCP exports and A2A skills are explicit configuration/grant intersections. Peer and outbound authentication are delegated to granted security adapters, external content remains untrusted, and private-network destinations are denied by default. Web and Desktop receive signed declarative Mini Apps without shell changes.

The release gate validates manifests, capability and UI schemas, security policy, signed bundles, hot route addition/removal, discovery, progress, cancellation, denied exports, Agent Card publication, task artifacts, client-runtime compatibility, SBOM, provenance, and rollback metadata.

## Coordinated publication order

Run `python3 scripts/coordinated-release.py` from this repository with tag `v0.5.0`. Before the run:

1. Create `Murchalka-AI/murchalka-module-protocol-gateway`, `Murchalka-AI/murchalka-module-protocol-mcp`, and `Murchalka-AI/murchalka-module-protocol-a2a`, then add each HTTPS or SSH URL as its local `origin`. The coordinator supports creating their first commits.
2. Add `MURCHALKA_BUNDLE_SIGNING_KEY_PEM` and `MURCHALKA_BUNDLE_SIGNING_KEY_ID` to all three new repositories. Use the same publisher identity for the three official bundles.
3. Set `BUNDLE_PUBLISHER_PUBLIC_KEY_PEM` and the matching `MURCHALKA_BUNDLE_SIGNING_KEY_ID` in `murchalka-deployment`. The public key must correspond to the private signing key above.
4. Allow GitHub Actions to read organization packages and publish repository Releases and attestations. The token supplied to the coordinator must be able to push branches and tags and read Releases for every selected repository.
5. Keep `v0.5.0` absent locally and remotely. If it was already published, update every `0.5.0` version and lock entry and release a new patch instead of moving the tag.

Select exactly these changed repositories in the coordinator: `murchalka-module-protocol`, `murchalka-module-sdk`, `murchalka-runtime`, `murchalka-module-protocol-gateway`, `murchalka-module-protocol-mcp`, `murchalka-module-protocol-a2a`, `murchalka-admin`, and `murchalka-deployment`. Use one release commit message, tag `v0.5.0`, and remote `origin`.

The coordinator publishes dependency waves and waits for immutable GitHub Releases before continuing:

1. `murchalka-module-protocol` publishes the `0.5.0` contract and schema packages.
2. `murchalka-module-sdk` publishes the `0.5.0` SDK packages that consume those contracts.
3. `murchalka-runtime`, `murchalka-module-protocol-gateway`, `murchalka-module-protocol-mcp`, `murchalka-module-protocol-a2a`, and `murchalka-admin` publish `v0.5.0`. These repositories may run in parallel after the SDK release exists.
4. `murchalka-deployment` publishes last. Its release workflow consumes the immutable Runtime image and protocol bundles and must pass the Phase 5–8 released-artifact gates before promotion.

`murchalka-client-runtime`, `murchalka-web`, and `murchalka-desktop` remain pinned to their already published `v0.4.3` artifacts because the Phase 8 Mini Apps use the existing declarative, TypeScript, cross-platform extension host. Do not create replacement tags for these unchanged repositories. Never move a failed tag; correct the lock and fix forward with a new patch version.

Runtime process bundles are released for Linux and macOS on x64 and arm64. Windows remains a CI compile/test target, but Phase 8 process bundles are intentionally not advertised or published until Runtime has an equivalent fail-closed Windows sandbox. The declarative Web and Desktop Mini Apps remain cross-platform.
