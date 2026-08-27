# Coordinated release 0.3.3

Release `v0.3.3` restores the complete Phase 5 acceptance path on Runtime `v0.3.3`. Every Minimal Core module is rebuilt with an explicit Runtime and Module SDK `0.3.x` compatibility range, and every platform-specific publish is preceded by a matching RID-aware restore.

The immutable component lock pins Runtime and all 17 Phase 5 modules to `v0.3.3`. The already published Phase 6 Node components remain pinned independently to `v0.3.2`, while Module Protocol and Module SDK remain compatible at `v0.3.0`.

Phase 6 now stages private keys into service-specific named volumes before starting the rootless Controller and Node containers. The source directory remains owner-only, the runtime services receive only the files they need, and neither service is granted root privileges or Linux capabilities.
