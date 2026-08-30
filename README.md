# Murchalka Deployment

Phase 5 Minimal Core profile, deterministic bindings, module configuration, and local Compose topology.

Phase 6 adds `profiles/nodes`, short-lived Node CA/task-signing material preparation, a least-privilege controller/Node Compose topology, and `scripts/phase6-e2e.sh`. Run `NODE_CA_PASSWORD=... scripts/prepare-node-security.sh` before the Node acceptance topology. Generated keys and certificates remain under ignored `runtime/node-security`.

Phase 7 adds the signed Client Extension delivery gate, the `releases/client-runtime.lock.json` coordinated component set, and `scripts/phase7-e2e.sh`. The gate starts an already-built Runtime, drops an already-signed diagnostics bundle into its inbox, verifies the live content-addressed catalog and server action, then proves immediate disable and re-enable revision propagation. The already-built Web shell and packaged Electron Desktop shell exercise the same Client Runtime against the live catalog: signed WASM, a dynamically supplied custom component, server-validated actions, accessible fallback, corrupt or unsigned rejection, activation rollback, immediate disable and re-enable, and verified offline cache reuse.

## Phase 6 acceptance

The `Phase 6 E2E` workflow downloads the signed diagnostics bundle and runs the released Node Controller and Node Runtime images. It proves one-time enrollment and approval, private-CA mTLS, capability discovery, signed bundle distribution, isolated facet activation, policy-bound task execution, immediate revocation, reconnect denial, and denial of new tasks. Deployment publication requires both the Phase 5 and Phase 6 acceptance jobs to pass.

For a local run, provide pinned controller/runtime images, the signed diagnostics bundle, an administrator token, a Node CA password, the trusted publisher public key, and its key identifier, then run `scripts/phase6-e2e.sh`. The script creates ephemeral security material, removes its containers and volumes on exit, and prints container logs when the gate fails.

## Start

1. Place the seventeen signed Minimal Core bundles in `runtime/modules/inbox`.
2. Prepare Runtime trust and least-privilege grants from those exact bundle digests. Keep both private keys outside this repository:
   `scripts/prepare-security.sh --bundles runtime/modules/inbox --publisher-key /safe/publisher-public.pem --publisher-key-id <release-key-id> --grant-private-key /safe/local-grant-private.pem --output runtime/security`.
3. Copy `.env.example` to `.env`; the supplied values match the immutable component versions in `releases/minimal-core.lock.json`.
4. Start the topology with `docker compose --env-file .env -f compose/compose.yaml up -d`. A one-shot sandbox probe must pass before Runtime starts. Runtime then applies `minimal-core` bindings and the checked-in module configuration snapshots after the trusted modules activate.
5. Bootstrap one Person, Character Identity, and Local Auth credential without exposing the password in process arguments:
   `printf '%s\n' '<strong-password>' | scripts/bootstrap.sh --password-stdin`.
6. Open the Web shell and connect to `ws://127.0.0.1:5080/v1/realtime`.

## Phase 5 acceptance

Install Chromium once with `cd ../murchalka-web && npx playwright install chromium`. With released bundles and local security material prepared as above, run:

`printf '%s\n' '<strong-password>' | scripts/phase5-e2e.sh --password-stdin`

The scenario starts the released containers, pulls the configured Ollama model, bootstraps the owner, drives the released React Web container through realtime, then uses the browser turn's exact conversation and session identifiers to verify durable messages, the closed Session, and product Audit Store evidence. Containers are stopped on exit; named volumes remain available for inspection.

The `Phase 5 E2E` GitHub Actions workflow executes the same released-artifact gate on Linux. Deployment releases call it as a required job before publication. It requires Actions secrets `BUNDLE_PUBLISHER_PUBLIC_KEY_PEM`, `MURCHALKA_BUNDLE_SIGNING_KEY_ID`, and `PHASE5_E2E_PASSWORD`; the private bundle-signing key is never exposed to Deployment, and the permission-grant authority key is ephemeral for each run.

## Coordinated interactive release

Run `python3 scripts/coordinated-release.py` from the deployment repository. The script discovers sibling Git repositories, shows everything that `git add -A` would stage, and asks `y/n` for each repository. It then asks once for the commit message, tag, remote name, and a hidden GitHub token before pushing each selected branch and its annotated tag. Clean repositories can be selected for tag-only publication. Existing local or remote tags are never moved. When deployment is selected, the coordinator chooses the unique `releases/*.lock.json` whose `deploymentTag` matches the requested tag. It reads the current `components` format (for `v0.4.1`, `releases/client-runtime.lock.json`) and remains compatible with the legacy nested lock format. Selected changed components must match the deployment tag, while unchanged components may remain pinned to an already published compatible release.

Use a fine-grained GitHub token with `Contents: Read and write` access to the selected repositories. The token is kept out of command arguments, remote configuration, and repository files; only `github.com` remotes are accepted. Before staging anything, the script disables stored credentials for its own Git processes and performs a dry-run push against every selected repository. Publication starts only when the complete preflight succeeds.

The Runtime control API stays on loopback. The realtime module also binds loopback-only. Generated `runtime/` security and state are ignored by Git. Canonical `vX.Y.Z` tags publish an immutable deployment archive.
