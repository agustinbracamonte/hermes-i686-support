#!/usr/bin/env python3
"""Offline audit of a resolved Python plan against its uv lock and wheelhouse.

This tool never downloads, builds, renames, or installs wheels and never edits
the supplied lock or wheelhouse. Run it beside the existing wheelhouse on the
target interpreter; the default tag source is that interpreter's pip debug
output.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path
from urllib.parse import unquote, urlparse


REQUIREMENT = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)(?:\[[A-Za-z0-9_,.-]+\])?==([^\s;\\]+)")
TAG = re.compile(r"^[A-Za-z0-9_.]+-[A-Za-z0-9_.]+-[A-Za-z0-9_.]+$")
WHEEL = re.compile(
    r"^(?P<distribution>[^-]+)-(?P<version>[^-]+)(?:-(?P<build>\d[^-]*))?"
    r"-(?P<python>[^-]+)-(?P<abi>[^-]+)-(?P<platform>[^-]+)\.whl$",
    re.IGNORECASE,
)


def canonical_name(value: str) -> str:
    return re.sub(r"[-_.]+", "-", value).lower()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_wheel_filename(filename: str) -> tuple[str, str, set[str]] | None:
    match = WHEEL.fullmatch(filename)
    if not match:
        return None
    py_tags = match.group("python").split(".")
    abi_tags = match.group("abi").split(".")
    platform_tags = match.group("platform").split(".")
    tags = {
        f"{py}-{abi}-{platform}"
        for py, abi, platform in itertools.product(py_tags, abi_tags, platform_tags)
    }
    return canonical_name(match.group("distribution")), match.group("version"), tags


def parse_requirements(path: Path) -> dict[str, str]:
    plan: dict[str, str] = {}
    unsupported: list[str] = []
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("--hash="):
            continue
        if line.endswith("\\"):
            line = line[:-1].rstrip()
        if line.startswith("--"):
            continue
        match = REQUIREMENT.match(line)
        if not match:
            unsupported.append(f"line {line_number}")
            continue
        if line[match.end():].strip():
            unsupported.append(f"line {line_number}")
            continue
        name, version = match.groups()
        key = canonical_name(name)
        if key in plan and plan[key] != version:
            raise ValueError(f"resolved plan contains multiple versions of {name}")
        plan[key] = version
    if unsupported:
        raise ValueError(
            "requirements export must contain exact name==version pins only; "
            + ", ".join(unsupported)
        )
    if not plan:
        raise ValueError("resolved requirements plan is empty")
    return plan


def tags_from_text(contents: str) -> set[str]:
    return {line.strip() for line in contents.splitlines() if TAG.fullmatch(line.strip())}


def interpreter_tags(executable: str) -> tuple[set[str], dict[str, object]]:
    probe = subprocess.run(
        [
            executable,
            "-c",
            "import json,struct,sys,sysconfig; "
            "print(json.dumps({'bits':struct.calcsize('P')*8,"
            "'platform':sysconfig.get_platform(),'sys_platform':sys.platform,"
            "'version':sys.version.split()[0]}))",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    identity = json.loads(probe.stdout.strip().splitlines()[-1])
    if (
        identity.get("sys_platform") != "linux"
        or identity.get("bits") != 32
        or not str(identity.get("platform", "")).lower().endswith("i686")
    ):
        raise ValueError(
            "the supplied interpreter must be Linux i686 (32-bit pointer and "
            "Linux sys.platform and sysconfig platform ending in i686; "
            f"saw {identity}"
        )
    debug = subprocess.run(
        [executable, "-m", "pip", "debug", "--verbose"],
        check=True,
        capture_output=True,
        text=True,
    )
    tags = tags_from_text(debug.stdout)
    if not tags:
        raise ValueError("pip debug output contains no compatible tags")
    return tags, identity


def validate_output_path(
    output: Path | None,
    lock_path: Path,
    requirements_path: Path,
    wheelhouse: Path,
    tags_file: Path | None,
    python: str,
) -> None:
    if output is None:
        return

    resolved_output = output.resolve()
    file_inputs = [
        ("lock", lock_path),
        ("requirements", requirements_path),
    ]
    if tags_file is not None:
        file_inputs.append(("tags file", tags_file))
    python_executable = shutil.which(python) or python
    file_inputs.append(("target interpreter", Path(python_executable)))

    for label, input_path in file_inputs:
        resolved_input = input_path.resolve()
        same_file = output.exists() and input_path.exists() and output.samefile(input_path)
        if resolved_output == resolved_input or same_file:
            raise ValueError(f"--output must not replace the {label}")

    resolved_wheelhouse = wheelhouse.resolve()
    try:
        resolved_output.relative_to(resolved_wheelhouse)
    except ValueError:
        pass
    else:
        raise ValueError("--output must be outside the supplied wheelhouse")

    if output.exists():
        for entry in wheelhouse.rglob("*"):
            if entry.is_file() and not entry.is_symlink() and output.samefile(entry):
                raise ValueError("--output must not alias a file in the supplied wheelhouse")


def lock_wheels(lock_path: Path) -> tuple[dict[tuple[str, str], list[dict[str, str]]], dict[str, object]]:
    raw = lock_path.read_bytes()
    lock = tomllib.loads(raw.decode("utf-8"))
    packages: dict[tuple[str, str], list[dict[str, str]]] = {}
    for package in lock.get("package", []):
        name = canonical_name(str(package.get("name", "")))
        version = str(package.get("version", ""))
        if not name or not version:
            continue
        entries = packages.setdefault((name, version), [])
        for wheel in package.get("wheels", []):
            url = str(wheel.get("url", ""))
            filename = Path(unquote(urlparse(url).path)).name
            digest = str(wheel.get("hash", ""))
            if filename.endswith(".whl") and digest.startswith("sha256:"):
                parsed = parse_wheel_filename(filename)
                if parsed and parsed[:2] == (name, version):
                    entries.append({"filename": filename, "sha256": digest.removeprefix("sha256:").lower(), "url": url})
    metadata = {
        "lock_sha256": hashlib.sha256(raw).hexdigest(),
        "locked_wheel_count": sum(map(len, packages.values())),
    }
    return packages, metadata


def local_wheels(wheelhouse: Path) -> list[dict[str, object]]:
    found: list[dict[str, object]] = []
    for path in sorted(wheelhouse.rglob("*.whl")):
        parsed = parse_wheel_filename(path.name)
        if not parsed:
            continue
        if path.is_symlink():
            raise ValueError(f"wheelhouse wheel is a symlink: {path.name}")
        if not path.is_file():
            raise ValueError(f"wheelhouse entry is not a regular file: {path.name}")
        name, version, tags = parsed
        found.append(
            {
                "path": path,
                "filename": path.name,
                "name": name,
                "version": version,
                "tags": tags,
                "sha256": sha256(path),
            }
        )
    return found


def reconcile(
    plan: dict[str, str],
    lock: dict[tuple[str, str], list[dict[str, str]]],
    wheels: list[dict[str, object]],
    target_tags: set[str],
) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []
    for name, version in sorted(plan.items()):
        key = (name, version)
        if key not in lock:
            results.append({"name": name, "version": version, "status": "package-not-in-lock"})
            continue
        locked = lock[key]
        locked_compatible = [
            wheel
            for wheel in locked
            if (parsed := parse_wheel_filename(wheel["filename"]))
            and parsed[2] & target_tags
        ]
        local = [wheel for wheel in wheels if wheel["name"] == name and wheel["version"] == version]
        compatible = [wheel for wheel in local if wheel["tags"] & target_tags]
        matched = [
            wheel
            for wheel in compatible
            for expected in locked
            if wheel["filename"] == expected["filename"]
            and wheel["sha256"] == expected["sha256"]
        ]
        if matched:
            chosen = matched[0]
            results.append(
                {
                    "name": name,
                    "version": version,
                    "status": "verified",
                    "filename": chosen["filename"],
                    "sha256": chosen["sha256"],
                }
            )
            continue
        if compatible:
            locked_names = {expected["filename"] for expected in locked}
            status = (
                "hash-mismatch"
                if any(wheel["filename"] in locked_names for wheel in compatible)
                else "wheel-not-in-lock"
            )
        elif not locked_compatible:
            status = "no-compatible-wheel"
        else:
            status = "compatible-wheel-not-present"
        results.append({"name": name, "version": version, "status": status})
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, required=True, help="uv.lock for the resolved plan")
    parser.add_argument(
        "--requirements",
        type=Path,
        required=True,
        help="exact target-resolved requirements export from uv",
    )
    parser.add_argument("--wheelhouse", type=Path, required=True, help="existing local wheelhouse")
    parser.add_argument(
        "--python",
        default=sys.executable,
        help="target CPython executable; must be Linux i686 and have pip (default: this interpreter)",
    )
    parser.add_argument(
        "--tags-file",
        type=Path,
        help="captured compatible-tag list for offline auditing; intended for tests or a saved target report",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="write the JSON result outside the lock, tag inputs, interpreter, and wheelhouse",
    )
    args = parser.parse_args()

    if not args.lock.is_file() or not args.requirements.is_file() or not args.wheelhouse.is_dir():
        parser.error("--lock, --requirements, and --wheelhouse must point to existing inputs")

    try:
        validate_output_path(
            args.output,
            args.lock,
            args.requirements,
            args.wheelhouse,
            args.tags_file,
            args.python,
        )
        if args.tags_file:
            tags_raw = args.tags_file.read_bytes()
            target_tags = tags_from_text(tags_raw.decode("utf-8"))
            identity: dict[str, object] = {"source": "tags-file"}
            tags_sha = hashlib.sha256(tags_raw).hexdigest()
        else:
            target_tags, identity = interpreter_tags(args.python)
            tags_sha = hashlib.sha256("\n".join(sorted(target_tags)).encode()).hexdigest()
        if not target_tags:
            raise ValueError("target compatible-tag set is empty")

        plan = parse_requirements(args.requirements)
        lock, lock_metadata = lock_wheels(args.lock)
        results = reconcile(plan, lock, local_wheels(args.wheelhouse), target_tags)
        counts: dict[str, int] = {}
        for result in results:
            status = str(result["status"])
            counts[status] = counts.get(status, 0) + 1
        report = {
            "schema": "hermes-v0232-wheel-reconciliation-v1",
            "target": identity,
            "target_tag_count": len(target_tags),
            "target_tags_sha256": tags_sha,
            "plan_sha256": sha256(args.requirements),
            **lock_metadata,
            "wheelhouse_file_count": len(list(args.wheelhouse.rglob("*.whl"))),
            "summary": {"plan": len(results), **counts},
            "packages": results,
        }
        encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(encoded, encoding="utf-8")
        else:
            sys.stdout.write(encoded)
        return 0 if all(item["status"] == "verified" for item in results) else 1
    except (OSError, ValueError, tomllib.TOMLDecodeError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
        print(f"wheel reconciliation: ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
