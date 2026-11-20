#!/usr/bin/env python3
"""Offline fixture tests for the v0.23.2 wheelhouse reconciler."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "scripts" / "reconcile-v0232-wheelhouse.py"


class WheelReconcileTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.wheelhouse = self.root / "wheelhouse"
        self.wheelhouse.mkdir()
        self.lock = self.root / "uv.lock"
        self.requirements = self.root / "requirements.txt"
        self.tags = self.root / "i686-tags.txt"
        self.report = self.root / "report.json"
        self.requirements.write_text(
            "cffi==2.1.1\npsutil==7.2.2\nnot-in-lock==1.0\n",
            encoding="utf-8",
        )
        self.tags.write_text(
            "cp314-cp314-manylinux_2_17_i686\ncp314-cp314-linux_i686\npy3-none-any\n",
            encoding="utf-8",
        )

    def tearDown(self):
        self.temporary.cleanup()

    def write_lock(self, cffi_body: bytes, *, psutil_platform: str = "manylinux_2_28_x86_64"):
        cffi_name = "cffi-2.1.1-cp314-cp314-manylinux_2_17_i686.whl"
        cffi_hash = hashlib.sha256(cffi_body).hexdigest()
        self.lock.write_text(
            f'''version = 1

[[package]]
name = "cffi"
version = "2.1.1"
wheels = [
  {{ url = "https://files.pythonhosted.org/packages/cffi/{cffi_name}", hash = "sha256:{cffi_hash}" }},
]

[[package]]
name = "psutil"
version = "7.2.2"
wheels = [
  {{ url = "https://files.pythonhosted.org/packages/psutil/psutil-7.2.2-cp314-cp314-{psutil_platform}.whl", hash = "sha256:{'a' * 64}" }},
]
''',
            encoding="utf-8",
        )
        return cffi_name

    def run_tool(self, *, python: str | None = None, use_tags_file: bool = True):
        command = [
            sys.executable,
            str(TOOL),
            "--lock",
            str(self.lock),
            "--requirements",
            str(self.requirements),
            "--wheelhouse",
            str(self.wheelhouse),
            "--output",
            str(self.report),
        ]
        if use_tags_file:
            command.extend(["--tags-file", str(self.tags)])
        if python:
            command.extend(["--python", python])
        return subprocess.run(command, text=True, capture_output=True, check=False)

    def test_reconciles_hash_and_tag_and_reports_missing_target_wheel(self):
        body = b"fixture wheel contents"
        filename = self.write_lock(body)
        (self.wheelhouse / filename).write_bytes(body)
        before = self.lock.read_bytes()

        result = self.run_tool()

        self.assertEqual(result.returncode, 1, result.stderr)
        report = json.loads(self.report.read_text(encoding="utf-8"))
        self.assertEqual(
            report["summary"],
            {"plan": 3, "no-compatible-wheel": 1, "package-not-in-lock": 1, "verified": 1},
        )
        statuses = {item["name"]: item["status"] for item in report["packages"]}
        self.assertEqual(
            statuses,
            {
                "cffi": "verified",
                "psutil": "no-compatible-wheel",
                "not-in-lock": "package-not-in-lock",
            },
        )
        self.assertEqual(self.lock.read_bytes(), before)
        self.assertNotIn(str(self.root), self.report.read_text(encoding="utf-8"))

    def test_rejects_local_wheel_that_does_not_match_locked_hash(self):
        body = b"expected lock bytes"
        filename = self.write_lock(body)
        (self.wheelhouse / filename).write_bytes(b"changed bytes")

        result = self.run_tool()

        self.assertEqual(result.returncode, 1, result.stderr)
        report = json.loads(self.report.read_text(encoding="utf-8"))
        statuses = {item["name"]: item["status"] for item in report["packages"]}
        self.assertEqual(statuses["cffi"], "hash-mismatch")

    def test_refuses_symlinked_wheel_even_when_target_hash_matches_lock(self):
        body = b"synthetic wheel bytes outside the wheelhouse"
        filename = self.write_lock(body)
        outside = self.root / "outside" / filename
        outside.parent.mkdir()
        outside.write_bytes(body)
        (self.wheelhouse / filename).symlink_to(outside)

        result = self.run_tool()

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("wheelhouse wheel is a symlink", result.stderr)
        self.assertFalse(self.report.exists())

    def test_refuses_directory_named_as_wheel_before_reading_it(self):
        filename = self.write_lock(b"synthetic wheel bytes")
        (self.wheelhouse / filename).mkdir()

        result = self.run_tool()

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("wheelhouse entry is not a regular file", result.stderr)
        self.assertFalse(self.report.exists())

    def test_refuses_non_i686_interpreter_independent_of_host_arch(self):
        body = b"fixture wheel contents"
        self.write_lock(body)
        fake_python = self.root / "fake-non-i686-python"
        fake_python.write_text(
            f"#!{sys.executable}\n"
            "print('{\"bits\":64,\"platform\":\"linux-x86_64\",\"version\":\"3.12.14\"}')\n",
            encoding="utf-8",
        )
        fake_python.chmod(0o755)

        result = self.run_tool(python=str(fake_python), use_tags_file=False)

        self.assertEqual(result.returncode, 2)
        self.assertIn("must be Linux i686", result.stderr)

    def test_rejects_universal_export_markers_instead_of_counting_them_as_i686(self):
        self.write_lock(b"fixture wheel contents")
        self.requirements.write_text(
            "cffi==2.1.1; sys_platform == 'linux'\n",
            encoding="utf-8",
        )

        result = self.run_tool()

        self.assertEqual(result.returncode, 2)
        self.assertIn("exact name==version pins only", result.stderr)
        self.assertFalse(self.report.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
