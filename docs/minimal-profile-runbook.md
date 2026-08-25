# Minimal profile runbook

1. Verify release checksums and publisher provenance for every bundle.
2. Place bundles through `scripts/install-bundle.sh`; never copy an incomplete archive directly into inbox.
3. Trust the publisher key out-of-band, review requested grants, and generate digest-bound grants with `scripts/prepare-security.sh`.
4. Start Runtime with installation `minimal-core`; it applies `bindings/minimal.bindings.yaml` after providers are installed. The logical provider instance is `default`.
5. Runtime applies the three versioned configuration snapshots after their modules activate.
6. Configure Ollama model `llama3.2`, then activate modules in dependency order.
7. Bootstrap a People record, Character Identity, and Local Auth credential linked to that Person.
8. Confirm `client.realtime.status`, authenticate a WebSocket, and execute a text turn.
9. Verify both Root audit and product Audit Store contain correlation evidence without prompt or password contents.
10. Disable and re-enable Conversations to confirm durable history; exercise side-by-side upgrade and rollback before promotion.

`scripts/phase5-e2e.sh` automates steps 6–9 against released Runtime/Web images and the actual browser shell. It also verifies that Realtime closes its durable Session.
