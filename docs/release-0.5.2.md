# Release 0.5.2 — Phase 8 Deployment Acceptance Fix-Forward

Deployment `v0.5.1` completed the MCP, A2A, UI, audit, disable, and re-enable checks but failed when hot-installing the first negative conformance fixture. The fixture bundles were generated after `umask 077` and therefore mounted as owner-readable only. Runtime intentionally runs under a distinct unprivileged container user and could not read the public bundle from `/release-bundles`.

Deployment `v0.5.2` normalizes all public `.murchalka` acceptance artifacts to container-readable permissions before Runtime starts. No secret files are affected. The release lock continues to pin SDK, Gateway, MCP, and A2A to their successful `v0.5.1` releases; only Deployment advances to `v0.5.2`.

Before tagging, push the reviewed Deployment commit without a tag and wait for its branch CI. Then run `python3 scripts/coordinated-release.py`, select only `murchalka-deployment`, use commit message `fix: make Phase 8 fixtures container-readable`, tag `v0.5.2`, and remote `origin`. The coordinator verifies that every component release in `protocol-modules.lock.json` already exists before publishing Deployment.

Never delete or move `v0.5.1`. If `v0.5.2` fails after publication, use the next Deployment patch tag.
