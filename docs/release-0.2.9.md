# Coordinated release 0.2.9

Release `v0.2.9` is a Deployment-only correction for clean-install bootstrap revisions. It keeps the verified Runtime image pinned to `v0.2.5` and all other Minimal Core components pinned to their existing immutable releases.

Minimal Core bindings now use revision one, the only valid first revision when the durable binding store is empty. Every module configuration bootstrap file uses the canonical revisioned snapshot envelope with revision one and a `values` object, including the model catalog configuration.

Deployment tests enforce these clean-install invariants so invalid bootstrap revisions or unwrapped configuration values fail before release acceptance.

Deployment publication remains blocked until the released Runtime image and every locked module bundle pass the correlated Browser → WebSocket → Local Auth → Sessions → Agent → Context → Model Router → Model Catalog → Ollama → SQLite → Audit acceptance path.
