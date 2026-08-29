"""Tests for the coordinated release component-lock loader."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "coordinated-release.py"
SPEC = importlib.util.spec_from_file_location("coordinated_release", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load {SCRIPT_PATH}.")
COORDINATED_RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COORDINATED_RELEASE)


class ComponentLockTests(unittest.TestCase):
    """Verify current and legacy deployment component-lock formats."""

    def test_selects_current_components_lock_by_deployment_tag(self) -> None:
        """Select the Phase 7 lock and return every pinned component release."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory)
            self.write_lock(
                repository,
                "minimal-core.lock.json",
                self.legacy_lock("v0.3.4"),
            )
            self.write_lock(
                repository,
                "client-runtime.lock.json",
                {
                    "schemaVersion": 1,
                    "phase": 7,
                    "deploymentTag": "v0.4.0",
                    "components": [
                        {"repository": "murchalka-client-runtime", "tag": "v0.4.0"},
                        {"repository": "murchalka-desktop", "tag": "v0.4.0"},
                        {"repository": "murchalka-deployment", "tag": "v0.4.0"},
                    ],
                },
            )

            releases = COORDINATED_RELEASE.load_deployment_component_releases(
                repository,
                "v0.4.0",
            )

            self.assertEqual(
                releases,
                {
                    "murchalka-client-runtime": "v0.4.0",
                    "murchalka-desktop": "v0.4.0",
                    "murchalka-deployment": "v0.4.0",
                },
            )

    def test_parses_legacy_nested_lock(self) -> None:
        """Keep Phase 6 coordinated releases compatible with their nested lock."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory)
            self.write_lock(
                repository,
                "minimal-core.lock.json",
                self.legacy_lock("v0.3.4"),
            )

            releases = COORDINATED_RELEASE.load_deployment_component_releases(
                repository,
                "v0.3.4",
            )

            self.assertEqual(releases["murchalka-runtime"], "v0.3.4")
            self.assertEqual(releases["murchalka-web"], "v0.3.4")
            self.assertEqual(releases["murchalka-node-runtime"], "v0.3.4")
            self.assertEqual(releases["murchalka-module-example"], "v0.3.4")

    def test_reports_available_locks_when_tag_is_unknown(self) -> None:
        """Explain which deployment tags are available when no lock matches."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory)
            self.write_lock(
                repository,
                "minimal-core.lock.json",
                self.legacy_lock("v0.3.4"),
            )

            with self.assertRaisesRegex(RuntimeError, "v0.3.4"):
                COORDINATED_RELEASE.load_deployment_component_releases(
                    repository,
                    "v0.4.0",
                )

    def test_rejects_duplicate_repository_in_components(self) -> None:
        """Reject ambiguous component releases in the current lock format."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory)
            self.write_lock(
                repository,
                "client-runtime.lock.json",
                {
                    "schemaVersion": 1,
                    "deploymentTag": "v0.4.0",
                    "components": [
                        {"repository": "murchalka-runtime", "tag": "v0.4.0"},
                        {"repository": "murchalka-runtime", "tag": "v0.4.0"},
                    ],
                },
            )

            with self.assertRaisesRegex(RuntimeError, "дубликат repository"):
                COORDINATED_RELEASE.load_deployment_component_releases(
                    repository,
                    "v0.4.0",
                )

    @staticmethod
    def write_lock(repository: Path, name: str, payload: dict[str, object]) -> None:
        """Write one component lock fixture."""
        releases_directory = repository / "releases"
        releases_directory.mkdir(exist_ok=True)
        (releases_directory / name).write_text(
            json.dumps(payload),
            encoding="utf-8",
        )

    @staticmethod
    def legacy_lock(tag: str) -> dict[str, object]:
        """Create a minimal valid legacy component lock fixture."""
        return {
            "schemaVersion": 1,
            "deploymentTag": tag,
            "runtime": {"repository": "murchalka-runtime", "tag": tag},
            "web": {"repository": "murchalka-web", "tag": tag},
            "node": {
                "runtime": {"repository": "murchalka-node-runtime", "tag": tag}
            },
            "modules": [
                {"repository": "murchalka-module-example", "tag": tag}
            ],
        }


if __name__ == "__main__":
    unittest.main()
