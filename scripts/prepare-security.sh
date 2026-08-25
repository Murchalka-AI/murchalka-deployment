#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec dotnet run \
  --project "${repository_root}/tools/Murchalka.Deployment.Security/Murchalka.Deployment.Security.csproj" \
  --configuration Release \
  -- "$@"
