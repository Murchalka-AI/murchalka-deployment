# Murchalka Deployment

Phase 5 Minimal Core profile, deterministic bindings, module configuration, and local Compose topology.

## Start

1. Place the fourteen signed Minimal Core bundles in `runtime/modules/inbox`.
2. Prepare Runtime trust and least-privilege grants from those exact bundle digests. Keep both private keys outside this repository:
   `scripts/prepare-security.sh --bundles runtime/modules/inbox --publisher-key /safe/publisher-public.pem --publisher-key-id <release-key-id> --grant-private-key /safe/local-grant-private.pem --output runtime/security`.
3. Copy `.env.example` to `.env`; the supplied values pin the coordinated `0.2.1` images.
4. Start the topology with `docker compose --env-file .env -f compose/compose.yaml up -d`. Runtime applies `minimal-core` bindings and the checked-in module configuration snapshots after the trusted modules activate.
5. Bootstrap one Person, Character Identity, and Local Auth credential without exposing the password in process arguments:
   `printf '%s\n' '<strong-password>' | scripts/bootstrap.sh --password-stdin`.
6. Open the Web shell and connect to `ws://127.0.0.1:5080/v1/realtime`.

## Phase 5 acceptance

Install Chromium once with `cd ../murchalka-web && npx playwright install chromium`. With released bundles and local security material prepared as above, run:

`printf '%s\n' '<strong-password>' | scripts/phase5-e2e.sh --password-stdin`

The scenario starts the released containers, pulls the configured Ollama model, bootstraps the owner, drives both the realtime protocol and the real React UI, then verifies durable conversation messages, the closed Session, and product Audit Store evidence. Containers are stopped on exit; named volumes remain available for inspection.

The manual `Phase 5 E2E` GitHub Actions workflow executes the same released-artifact gate on Linux. It requires repository secrets `BUNDLE_PUBLISHER_PUBLIC_KEY_PEM`, `BUNDLE_SIGNING_KEY_ID`, and `PHASE5_E2E_PASSWORD`; the permission-grant authority key is ephemeral for each run.

## Coordinated interactive release

Run `python3 scripts/coordinated-release.py` from the deployment repository. The script discovers sibling Git repositories, shows everything that `git add -A` would stage, and asks `y/n` for each repository. It then asks once for the commit message, tag, remote name, and a hidden GitHub token before pushing each selected branch and its annotated tag. Clean repositories can be selected for tag-only publication. Existing local or remote tags are never moved.

Use a fine-grained GitHub token with `Contents: Read and write` access to the selected repositories. The token is kept out of command arguments, remote configuration, and repository files; only `github.com` remotes are accepted. Before staging anything, the script disables stored credentials for its own Git processes and performs a dry-run push against every selected repository. Publication starts only when the complete preflight succeeds.

The Runtime control API stays on loopback. The realtime module also binds loopback-only. Generated `runtime/` security and state are ignored by Git. Canonical `vX.Y.Z` tags publish an immutable deployment archive.
