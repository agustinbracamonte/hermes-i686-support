#!/usr/bin/env python3
"""Offline fixture tests for the v0.23.2 wheelhouse reconciler."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


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
        cffi_sdist_hash = hashlib.sha256(b"synthetic cffi source bytes").hexdigest()
        psutil_sdist_hash = hashlib.sha256(b"synthetic psutil source bytes").hexdigest()
        cffi_sdist_size = len(b"synthetic cffi source bytes")
        psutil_sdist_size = len(b"synthetic psutil source bytes")
        self.lock.write_text(
            f'''version = 1

[[package]]
name = "cffi"
version = "2.1.1"
sdist = {{ url = "https://files.pythonhosted.org/packages/cffi/cffi-2.1.1.tar.gz", hash = "sha256:{cffi_sdist_hash}", size = {cffi_sdist_size} }}
wheels = [
  {{ url = "https://files.pythonhosted.org/packages/cffi/{cffi_name}", hash = "sha256:{cffi_hash}" }},
]

[[package]]
name = "psutil"
version = "7.2.2"
sdist = {{ url = "https://files.pythonhosted.org/packages/psutil/psutil-7.2.2.tar.gz?fixture=redacted", hash = "sha256:{psutil_sdist_hash}", size = {psutil_sdist_size} }}
wheels = [
  {{ url = "https://files.pythonhosted.org/packages/psutil/psutil-7.2.2-cp314-cp314-{psutil_platform}.whl", hash = "sha256:{'a' * 64}" }},
]
''',
            encoding="utf-8",
        )
        return cffi_name

    def run_tool(
        self,
        *,
        python: str | None = None,
        use_tags_file: bool = True,
        output: Path | None = None,
    ):
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
            str(output or self.report),
        ]
        if use_tags_file:
            command.extend(["--tags-file", str(self.tags)])
        if python:
            command.extend(["--python", python])
        return subprocess.run(command, text=True, capture_output=True, check=False)

    def run_main_with_output_swap(self, swap_output, *, output: Path | None = None):
        spec = importlib.util.spec_from_file_location("wheel_reconciler_fixture", TOOL)
        module = importlib.util.module_from_spec(spec)
        self.assertIsNotNone(spec.loader)
        spec.loader.exec_module(module)
        original_validate = module.validate_output_path

        def validate_then_swap(*args, **kwargs):
            expected_parent_identity = original_validate(*args, **kwargs)
            swap_output()
            return expected_parent_identity

        module.validate_output_path = validate_then_swap
        argv = [
            str(TOOL), "--lock", str(self.lock), "--requirements", str(self.requirements),
            "--wheelhouse", str(self.wheelhouse), "--tags-file", str(self.tags),
            "--output", str(output or self.report),
        ]
        with mock.patch.object(sys, "argv", argv):
            return module.main()

    def test_atomic_report_write_does_not_follow_raced_symlink(self):
        self.write_lock(b"fixture wheel contents")
        protected = self.root / "protected.json"
        protected.write_text("preserve this synthetic sentinel", encoding="utf-8")

        result = self.run_main_with_output_swap(lambda: self.report.symlink_to(protected))

        self.assertEqual(result, 1)  # The fixture intentionally has missing wheels.
        self.assertEqual(protected.read_text(encoding="utf-8"), "preserve this synthetic sentinel")
        self.assertFalse(self.report.is_symlink())
        self.assertEqual(json.loads(self.report.read_text(encoding="utf-8"))["schema"],
                         "hermes-v0232-wheel-reconciliation-v2")
        self.assertEqual(list(self.root.glob(".report.json.*.tmp")), [])

    def test_atomic_report_write_does_not_truncate_raced_hardlink(self):
        self.write_lock(b"fixture wheel contents")
        protected = self.root / "protected.json"
        protected.write_text("preserve this synthetic sentinel", encoding="utf-8")

        result = self.run_main_with_output_swap(lambda: os.link(protected, self.report))

        self.assertEqual(result, 1)  # The fixture intentionally has missing wheels.
        self.assertEqual(protected.read_text(encoding="utf-8"), "preserve this synthetic sentinel")
        self.assertFalse(self.report.is_symlink())
        self.assertEqual(json.loads(self.report.read_text(encoding="utf-8"))["schema"],
                         "hermes-v0232-wheel-reconciliation-v2")
        self.assertEqual(list(self.root.glob(".report.json.*.tmp")), [])

    def test_atomic_report_write_does_not_follow_raced_parent_symlink(self):
        self.write_lock(b"fixture wheel contents")
        report_parent = self.root / "reports"
        report_parent.mkdir()
        outside = self.root / "outside"
        outside.mkdir()
        output = report_parent / "summary.json"

        def replace_parent_with_symlink():
            report_parent.rename(self.root / "reports-before-swap")
            report_parent.symlink_to(outside, target_is_directory=True)

        result = self.run_main_with_output_swap(
            replace_parent_with_symlink,
            output=output,
        )

        self.assertFalse((outside / output.name).exists())
        self.assertEqual(result, 2)
        self.assertEqual(list(outside.iterdir()), [])

    def test_atomic_report_write_refuses_replaced_real_parent(self):
        self.write_lock(b"fixture wheel contents")
        report_parent = self.root / "reports"
        report_parent.mkdir()
        replacement = self.root / "replacement"
        replacement.mkdir()
        output = report_parent / "summary.json"

        def replace_parent_with_another_directory():
            report_parent.rename(self.root / "reports-before-swap")
            replacement.rename(report_parent)

        result = self.run_main_with_output_swap(
            replace_parent_with_another_directory,
            output=output,
        )

        self.assertEqual(result, 2)
        self.assertFalse(output.exists())
        self.assertEqual(list(report_parent.iterdir()), [])

    def test_atomic_report_write_cleans_up_after_parent_moves_at_replace(self):
        self.write_lock(b"fixture wheel contents")
        report_parent = self.root / "reports"
        report_parent.mkdir()
        saved_parent = self.root / "reports-before-replace"
        outside = self.root / "outside"
        outside.mkdir()
        output = report_parent / "summary.json"
        original_replace = os.replace
        swapped = False

        def replace_after_parent_swap(source, destination, *, src_dir_fd=None, dst_dir_fd=None):
            nonlocal swapped
            if not swapped:
                report_parent.rename(saved_parent)
                report_parent.symlink_to(outside, target_is_directory=True)
                swapped = True
            return original_replace(
                source,
                destination,
                src_dir_fd=src_dir_fd,
                dst_dir_fd=dst_dir_fd,
            )

        with mock.patch.object(os, "replace", side_effect=replace_after_parent_swap):
            result = self.run_main_with_output_swap(lambda: None, output=output)

        self.assertTrue(swapped)
        self.assertEqual(result, 2)
        self.assertFalse((outside / output.name).exists())
        self.assertEqual(list(saved_parent.iterdir()), [])
        self.assertEqual(list(outside.iterdir()), [])

    def test_atomic_report_write_creates_missing_parent_directories(self):
        self.write_lock(b"fixture wheel contents")
        output = self.root / "new" / "nested" / "summary.json"

        result = self.run_tool(output=output)

        self.assertEqual(result.returncode, 1)  # The fixture intentionally has missing wheels.
        self.assertEqual(json.loads(output.read_text(encoding="utf-8"))["schema"],
                         "hermes-v0232-wheel-reconciliation-v2")

    def test_refuses_output_that_would_overwrite_file_inputs(self):
        self.write_lock(b"fixture wheel contents")
        for input_path, label in (
            (self.lock, "lock"),
            (self.requirements, "requirements"),
            (self.tags, "tags file"),
        ):
            with self.subTest(input=label):
                self.write_lock(b"fixture wheel contents")
                self.requirements.write_text(
                    "cffi==2.1.1\npsutil==7.2.2\nnot-in-lock==1.0\n",
                    encoding="utf-8",
                )
                self.tags.write_text(
                    "cp314-cp314-manylinux_2_17_i686\ncp314-cp314-linux_i686\npy3-none-any\n",
                    encoding="utf-8",
                )
                before = input_path.read_bytes()
                result = self.run_tool(output=input_path)

                self.assertEqual(input_path.read_bytes(), before)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn(f"--output must not replace the {label}", result.stderr)

    def test_refuses_output_that_would_overwrite_the_target_interpreter(self):
        self.write_lock(b"fixture wheel contents")
        fake_python = self.root / "fake-i686-python"
        fake_python.write_text(
            f"#!{sys.executable}\n"
            "import json, sys\n"
            "if sys.argv[1:2] == ['-c']:\n"
            "    print(json.dumps({'bits': 32, 'platform': 'linux-i686', "
            "'sys_platform': 'linux', 'version': '3.12.14'}))\n"
            "elif sys.argv[1:3] == ['-m', 'pip']:\n"
            "    print('cp314-cp314-linux_i686')\n"
            "else:\n"
            "    raise SystemExit(3)\n",
            encoding="utf-8",
        )
        fake_python.chmod(0o755)
        before = fake_python.read_bytes()

        result = self.run_tool(
            python=str(fake_python),
            use_tags_file=False,
            output=fake_python,
        )

        self.assertEqual(fake_python.read_bytes(), before)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("--output must not replace the target interpreter", result.stderr)

    def test_refuses_output_inside_wheelhouse(self):
        self.write_lock(b"fixture wheel contents")
        output = self.wheelhouse / "report.json"

        result = self.run_tool(output=output)

        self.assertFalse(output.exists())
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("--output must be outside the supplied wheelhouse", result.stderr)

    def test_refuses_output_hardlink_to_wheelhouse_file(self):
        body = b"fixture wheel contents"
        filename = self.write_lock(body)
        wheel = self.wheelhouse / filename
        wheel.write_bytes(body)
        output = self.root / "report.json"
        os.link(wheel, output)
        before = wheel.read_bytes()

        result = self.run_tool(output=output)

        self.assertEqual(wheel.read_bytes(), before)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("--output must not be a hard link", result.stderr)

    def test_refuses_output_hardlink_to_external_file(self):
        self.write_lock(b"fixture wheel contents")
        protected = self.root / "protected.txt"
        protected.write_bytes(b"keep this synthetic file unchanged")
        output = self.root / "report.json"
        os.link(protected, output)
        before = protected.read_bytes()

        result = self.run_tool(output=output)

        self.assertEqual(protected.read_bytes(), before)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("--output must not be a hard link", result.stderr)

    def test_refuses_output_symlink_to_unrelated_file(self):
        self.write_lock(b"fixture wheel contents")
        protected = self.root / "protected.txt"
        protected.write_bytes(b"keep this synthetic file unchanged")
        output = self.root / "report.json"
        output.symlink_to(protected)
        before = protected.read_bytes()

        result = self.run_tool(output=output)

        self.assertEqual(protected.read_bytes(), before)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("--output must not be a symlink", result.stderr)

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

    def test_reports_locked_sdist_metadata_for_missing_compatible_wheel(self):
        self.write_lock(b"fixture wheel contents")

        result = self.run_tool()

        self.assertEqual(result.returncode, 1, result.stderr)
        report = json.loads(self.report.read_text(encoding="utf-8"))
        packages = {item["name"]: item for item in report["packages"]}
        self.assertEqual(packages["psutil"]["status"], "no-compatible-wheel")
        self.assertEqual(
            packages["psutil"]["source_distributions"],
            [{
                "filename": "psutil-7.2.2.tar.gz",
                "sha256": hashlib.sha256(b"synthetic psutil source bytes").hexdigest(),
                "size_bytes": len(b"synthetic psutil source bytes"),
            }],
        )
        self.assertEqual(report["locked_sdist_count"], 2)
        self.assertNotIn("files.pythonhosted.org", self.report.read_text(encoding="utf-8"))
        self.assertNotIn("fixture=redacted", self.report.read_text(encoding="utf-8"))

    def test_rejects_locked_sdist_without_a_sha256_digest(self):
        self.write_lock(b"fixture wheel contents")
        invalid_hash = "sha256:" + hashlib.sha256(b"synthetic psutil source bytes").hexdigest()
        self.lock.write_text(
            self.lock.read_text(encoding="utf-8").replace(invalid_hash, "sha256:not-a-sha256"),
            encoding="utf-8",
        )

        result = self.run_tool()

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("must have a filename and SHA-256", result.stderr)
        self.assertFalse(self.report.exists())

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
            "print('{\"bits\":64,\"platform\":\"linux-x86_64\",\"sys_platform\":\"linux\",\"version\":\"3.12.14\"}')\n",
            encoding="utf-8",
        )
        fake_python.chmod(0o755)

        result = self.run_tool(python=str(fake_python), use_tags_file=False)

        self.assertEqual(result.returncode, 2)
        self.assertIn("must be Linux i686", result.stderr)

    def test_refuses_cygwin_i686_as_a_linux_tag_source_before_pip_probe(self):
        self.write_lock(b"fixture wheel contents")
        fake_python = self.root / "fake-cygwin-i686-python"
        pip_probe_marker = self.root / "pip-debug-was-called"
        fake_python.write_text(
            f"#!{sys.executable}\n"
            "import json, pathlib, sys\n"
            "if sys.argv[1:2] == ['-c']:\n"
            "    print(json.dumps({'bits': 32, 'platform': 'cygwin-3.5.3-i686', "
            "'sys_platform': 'cygwin', 'version': '3.12.14'}))\n"
            "elif sys.argv[1:3] == ['-m', 'pip']:\n"
            f"    pathlib.Path({str(pip_probe_marker)!r}).write_text('called')\n"
            "    print('cp314-cp314-linux_i686')\n"
            "else:\n"
            "    raise SystemExit(3)\n",
            encoding="utf-8",
        )
        fake_python.chmod(0o755)

        result = self.run_tool(python=str(fake_python), use_tags_file=False)

        self.assertFalse(pip_probe_marker.exists())
        self.assertEqual(result.returncode, 2, result.stderr)
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
