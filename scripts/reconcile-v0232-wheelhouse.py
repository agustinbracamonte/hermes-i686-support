#!/usr/bin/env python3
"""Offline audit of a resolved Python plan against its uv lock and wheelhouse.

This tool never downloads, builds, renames, or installs wheels and never edits
the supplied lock or wheelhouse. Run it beside the existing wheelhouse on the
target interpreter; the default tag source is that interpreter's pip debug
output.
"""

from __future__ import annotations

import argparse
import errno
import hashlib
import itertools
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote, urlparse


REQUIREMENT = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)(?:\[[A-Za-z0-9_,.-]+\])?==([^\s;\\]+)")
TAG = re.compile(r"^[A-Za-z0-9_.]+-[A-Za-z0-9_.]+-[A-Za-z0-9_.]+$")
WHEEL = re.compile(
    r"^(?P<distribution>[^-]+)-(?P<version>[^-]+)(?:-(?P<build>\d[^-]*))?"
    r"-(?P<python>[^-]+)-(?P<abi>[^-]+)-(?P<platform>[^-]+)\.whl$",
    re.IGNORECASE,
)
SDIST_SHA256 = re.compile(r"^sha256:([0-9a-f]{64})$", re.IGNORECASE)


@dataclass(frozen=True)
class OutputPathGuard:
    parent_identity: tuple[int, int] | None
    wheelhouse_identity: tuple[int, int]
    protected_file_identities: frozenset[tuple[int, int]]


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
) -> OutputPathGuard | None:
    if output is None:
        return None

    if output.is_symlink():
        raise ValueError("--output must not be a symlink")
    if output.exists():
        if not output.is_file():
            raise ValueError("--output must be a regular file")
        if output.stat().st_nlink > 1:
            raise ValueError("--output must not be a hard link")

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

    wheelhouse_stat = wheelhouse.stat()
    protected_file_identities: set[tuple[int, int]] = set()
    for _, input_path in file_inputs:
        try:
            input_stat = input_path.stat()
        except OSError:
            continue
        protected_file_identities.add((input_stat.st_dev, input_stat.st_ino))

    try:
        parent_stat = output.parent.stat()
    except FileNotFoundError:
        parent_identity = None
    else:
        if not stat.S_ISDIR(parent_stat.st_mode):
            raise ValueError("--output parent must be a directory")
        parent_identity = (parent_stat.st_dev, parent_stat.st_ino)
    return OutputPathGuard(
        parent_identity=parent_identity,
        wheelhouse_identity=(wheelhouse_stat.st_dev, wheelhouse_stat.st_ino),
        protected_file_identities=frozenset(protected_file_identities),
    )


def open_directory_chain(path: Path, *, create: bool = False) -> int:
    """Open every output-parent component without following symlinks."""
    if not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
        raise OSError("safe --output parent traversal is unavailable on this platform")
    if os.open not in os.supports_dir_fd:
        raise OSError("safe --output parent traversal requires dir_fd support")

    absolute = Path(os.path.abspath(path))
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    descriptor = os.open(absolute.anchor or os.sep, flags)

    def open_child(component: str, parent_fd: int) -> int:
        try:
            return os.open(component, flags, dir_fd=parent_fd)
        except OSError as exc:
            if exc.errno in (errno.ELOOP, errno.ENOTDIR):
                raise ValueError(
                    "--output parent components must be real directories; symlinks are not followed"
                ) from exc
            raise

    try:
        for component in absolute.parts[1:]:
            try:
                child = open_child(component, descriptor)
            except FileNotFoundError:
                if not create:
                    raise
                try:
                    os.mkdir(component, mode=0o777, dir_fd=descriptor)
                except FileExistsError:
                    pass
                child = open_child(component, descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def require_output_parent_stable(
    output: Path,
    parent_fd: int,
    guard: OutputPathGuard,
) -> None:
    pinned = os.fstat(parent_fd)
    identity = (pinned.st_dev, pinned.st_ino)
    if guard.parent_identity is not None and identity != guard.parent_identity:
        raise ValueError("--output parent changed after validation")
    if output_parent_is_within_wheelhouse(parent_fd, guard.wheelhouse_identity):
        raise ValueError("--output parent must remain outside the supplied wheelhouse")
    named_fd = open_directory_chain(output.parent)
    try:
        named = os.fstat(named_fd)
        if (named.st_dev, named.st_ino) != identity:
            raise ValueError("--output parent changed during report writing")
    finally:
        os.close(named_fd)


def output_parent_is_within_wheelhouse(parent_fd: int, wheelhouse_identity: tuple[int, int]) -> bool:
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
    current_fd = os.dup(parent_fd)
    try:
        while True:
            current = os.fstat(current_fd)
            if (current.st_dev, current.st_ino) == wheelhouse_identity:
                return True
            ancestor_fd = os.open("..", flags, dir_fd=current_fd)
            ancestor = os.fstat(ancestor_fd)
            if (ancestor.st_dev, ancestor.st_ino) == (current.st_dev, current.st_ino):
                os.close(ancestor_fd)
                return False
            os.close(current_fd)
            current_fd = ancestor_fd
    finally:
        os.close(current_fd)


def require_output_name_not_protected(
    name: str,
    parent_fd: int,
    protected_identities: frozenset[tuple[int, int]],
) -> None:
    try:
        existing = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    if (existing.st_dev, existing.st_ino) in protected_identities:
        raise ValueError("--output destination now aliases a protected input")


def write_report_atomically(
    output: Path,
    encoded: str,
    guard: OutputPathGuard,
) -> None:
    """Write through a pinned output directory and reject parent-path swaps."""
    parent_fd = open_directory_chain(output.parent, create=True)
    temporary_name: str | None = None
    try:
        require_output_parent_stable(output, parent_fd, guard)
        require_output_name_not_protected(output.name, parent_fd, guard.protected_file_identities)
        flags = (
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
            | getattr(os, "O_CLOEXEC", 0)
        )
        for _ in range(10):
            candidate = f".{output.name}.{secrets.token_hex(8)}.tmp"
            try:
                descriptor = os.open(candidate, flags, 0o600, dir_fd=parent_fd)
            except FileExistsError:
                continue
            temporary_name = candidate
            break
        else:
            raise FileExistsError("could not allocate a unique --output temporary file")

        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        require_output_parent_stable(output, parent_fd, guard)
        require_output_name_not_protected(output.name, parent_fd, guard.protected_file_identities)
        os.replace(
            temporary_name,
            output.name,
            src_dir_fd=parent_fd,
            dst_dir_fd=parent_fd,
        )
        temporary_name = None
        try:
            require_output_parent_stable(output, parent_fd, guard)
        except (OSError, ValueError):
            try:
                os.unlink(output.name, dir_fd=parent_fd)
            except FileNotFoundError:
                pass
            raise
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name, dir_fd=parent_fd)
            except FileNotFoundError:
                pass
        os.close(parent_fd)


def lock_artifacts(
    lock_path: Path,
) -> tuple[
    dict[tuple[str, str], list[dict[str, str]]],
    dict[tuple[str, str], list[dict[str, object]]],
    dict[str, object],
]:
    raw = lock_path.read_bytes()
    lock = tomllib.loads(raw.decode("utf-8"))
    packages: dict[tuple[str, str], list[dict[str, str]]] = {}
    source_distributions: dict[tuple[str, str], list[dict[str, object]]] = {}
    for package in lock.get("package", []):
        name = canonical_name(str(package.get("name", "")))
        version = str(package.get("version", ""))
        if not name or not version:
            continue
        key = (name, version)
        entries = packages.setdefault(key, [])
        for wheel in package.get("wheels", []):
            url = str(wheel.get("url", ""))
            filename = Path(unquote(urlparse(url).path)).name
            digest = str(wheel.get("hash", ""))
            if filename.endswith(".whl") and digest.startswith("sha256:"):
                parsed = parse_wheel_filename(filename)
                if parsed and parsed[:2] == (name, version):
                    entries.append({"filename": filename, "sha256": digest.removeprefix("sha256:").lower(), "url": url})

        sdist = package.get("sdist")
        if sdist is not None:
            if not isinstance(sdist, dict):
                raise ValueError(f"locked source distribution for {name}=={version} is not a table")
            sdist_url = str(sdist.get("url", ""))
            sdist_filename = Path(unquote(urlparse(sdist_url).path)).name
            sdist_hash = str(sdist.get("hash", ""))
            hash_match = SDIST_SHA256.fullmatch(sdist_hash)
            if not sdist_filename or not hash_match:
                raise ValueError(
                    f"locked source distribution for {name}=={version} must have a filename and SHA-256"
                )
            source_record: dict[str, object] = {
                "filename": sdist_filename,
                "sha256": hash_match.group(1).lower(),
            }
            size = sdist.get("size")
            if isinstance(size, int) and not isinstance(size, bool) and size >= 0:
                source_record["size_bytes"] = size
            source_entries = source_distributions.setdefault(key, [])
            if source_record not in source_entries:
                source_entries.append(source_record)
    metadata = {
        "lock_sha256": hashlib.sha256(raw).hexdigest(),
        "locked_wheel_count": sum(map(len, packages.values())),
        "locked_sdist_count": sum(map(len, source_distributions.values())),
    }
    return packages, source_distributions, metadata


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
    source_distributions: dict[tuple[str, str], list[dict[str, object]]],
    wheels: list[dict[str, object]],
    target_tags: set[str],
) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []
    for name, version in sorted(plan.items()):
        key = (name, version)
        if key not in lock:
            result: dict[str, object] = {"name": name, "version": version, "status": "package-not-in-lock"}
        else:
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
                result = {
                    "name": name,
                    "version": version,
                    "status": "verified",
                    "filename": chosen["filename"],
                    "sha256": chosen["sha256"],
                }
            elif compatible:
                locked_names = {expected["filename"] for expected in locked}
                if any(wheel["filename"] in locked_names for wheel in compatible):
                    status = "hash-mismatch"
                elif locked_compatible:
                    # An unrelated compatible wheel cannot replace a target wheel pinned by the lock.
                    status = "compatible-wheel-not-present"
                else:
                    status = "wheel-not-in-lock"
                result = {"name": name, "version": version, "status": status}
            elif not locked_compatible:
                result = {"name": name, "version": version, "status": "no-compatible-wheel"}
            else:
                result = {"name": name, "version": version, "status": "compatible-wheel-not-present"}
        if source_distributions.get(key):
            result["source_distributions"] = source_distributions[key]
        result["classification"] = classify_result(
            str(result["status"]), bool(source_distributions.get(key))
        )
        results.append(result)
    return results


def wheelhouse_anomalies(
    plan: dict[str, str],
    lock: dict[tuple[str, str], list[dict[str, str]]],
    wheels: list[dict[str, object]],
    target_tags: set[str],
) -> list[dict[str, str]]:
    """List target-compatible local wheels that are not an exact locked plan artifact."""
    anomalies: list[dict[str, str]] = []
    for wheel in wheels:
        if not (wheel["tags"] & target_tags):
            continue
        name = str(wheel["name"])
        version = str(wheel["version"])
        key = (name, version)
        if plan.get(name) != version:
            status = "package-not-in-plan"
        elif key not in lock:
            status = "package-not-in-lock"
        else:
            locked = lock[key]
            filename_matches = [
                item for item in locked if item["filename"] == wheel["filename"]
            ]
            if any(item["sha256"] == wheel["sha256"] for item in filename_matches):
                continue
            status = "hash-mismatch" if filename_matches else "wheel-not-in-lock"
        anomalies.append(
            {
                "name": name,
                "version": version,
                "filename": str(wheel["filename"]),
                "sha256": str(wheel["sha256"]),
                "status": status,
                "classification": classify_result(status, False),
            }
        )
    return anomalies


def classify_result(status: str, has_source_distribution: bool) -> str:
    """Separate artifact inventory outcomes from integrity failures and build gaps."""
    if status == "verified":
        return "verified-wheel"
    if status == "hash-mismatch":
        return "integrity-failure"
    if status == "wheel-not-in-lock":
        return "unlocked-wheel"
    if status == "package-not-in-lock":
        return "plan-lock-mismatch"
    if status == "package-not-in-plan":
        return "unexpected-wheel"
    if status == "no-compatible-wheel":
        if has_source_distribution:
            return "source-build-candidate"
        return "unresolved-artifact-gap"
    if status == "compatible-wheel-not-present":
        return "locked-wheel-missing-locally"
    raise ValueError(f"unknown reconciliation status: {status}")


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
        help="write JSON atomically outside inputs/wheelhouse; parent components cannot be symlinks",
    )
    args = parser.parse_args()

    if not args.lock.is_file() or not args.requirements.is_file() or not args.wheelhouse.is_dir():
        parser.error("--lock, --requirements, and --wheelhouse must point to existing inputs")

    try:
        output_path_guard = validate_output_path(
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
        lock, source_distributions, lock_metadata = lock_artifacts(args.lock)
        wheels = local_wheels(args.wheelhouse)
        results = reconcile(plan, lock, source_distributions, wheels, target_tags)
        anomalies = wheelhouse_anomalies(plan, lock, wheels, target_tags)
        counts: dict[str, int] = {}
        classifications: dict[str, int] = {}
        for result in results:
            status = str(result["status"])
            counts[status] = counts.get(status, 0) + 1
            classification = str(result["classification"])
            classifications[classification] = classifications.get(classification, 0) + 1
        anomaly_counts: dict[str, int] = {}
        for anomaly in anomalies:
            classification = anomaly["classification"]
            anomaly_counts[classification] = anomaly_counts.get(classification, 0) + 1
        report = {
            "schema": "hermes-v0232-wheel-reconciliation-v4",
            "target": identity,
            "target_tag_count": len(target_tags),
            "target_tags_sha256": tags_sha,
            "plan_sha256": sha256(args.requirements),
            **lock_metadata,
            "wheelhouse_file_count": len(list(args.wheelhouse.rglob("*.whl"))),
            "summary": {"plan": len(results), **counts},
            "classification_summary": classifications,
            "wheelhouse_anomaly_summary": anomaly_counts,
            "wheelhouse_anomalies": anomalies,
            "packages": results,
        }
        encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
        if args.output:
            if output_path_guard is None:
                raise ValueError("--output validation did not return a path guard")
            write_report_atomically(args.output, encoded, output_path_guard)
        else:
            sys.stdout.write(encoded)
        return 0 if all(item["status"] == "verified" for item in results) and not anomalies else 1
    except (OSError, ValueError, tomllib.TOMLDecodeError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
        print(f"wheel reconciliation: ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
