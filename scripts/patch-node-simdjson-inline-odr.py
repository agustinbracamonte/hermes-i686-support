#!/usr/bin/env python3
"""Apply the i686 libstdc++-10 ODR fix to Node's pinned simdjson bundle."""

from __future__ import annotations

import os
import hashlib
import re
import stat
import sys
import tempfile
from pathlib import Path
from typing import NoReturn


HELPER_BLOCK = re.compile(
    r"(?m)^// --- describe\(\) string helpers \(constexpr; no std::to_string, which is not\) ---$"
)
APPEND_UINT = re.compile(
    r"(?m)^SIMDJSON_CONSTEXPR_STRING void append_uint\(std::string& s, std::size_t v\) \{"
)
APPEND_BYTE = re.compile(
    r"(?m)^SIMDJSON_CONSTEXPR_STRING void append_byte\(std::string& s, unsigned b\) \{"
)
INLINE_APPEND_UINT = re.compile(
    r"(?m)^inline SIMDJSON_CONSTEXPR_STRING void append_uint\(std::string& s, std::size_t v\) \{"
)
INLINE_APPEND_BYTE = re.compile(
    r"(?m)^inline SIMDJSON_CONSTEXPR_STRING void append_byte\(std::string& s, unsigned b\) \{"
)


def fail(message: str) -> NoReturn:
    print(f"simdjson i686 ODR patch: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: patch-node-simdjson-inline-odr.py path/to/deps/simdjson/simdjson.h")

    header = Path(sys.argv[1])
    try:
        original = header.read_text(encoding="utf-8")
        mode = stat.S_IMODE(header.stat().st_mode)
    except OSError as error:
        fail(f"cannot read pinned Node header: {error}")

    block_count = len(HELPER_BLOCK.findall(original))
    old_uint_count = len(APPEND_UINT.findall(original))
    old_byte_count = len(APPEND_BYTE.findall(original))
    inline_uint_count = len(INLINE_APPEND_UINT.findall(original))
    inline_byte_count = len(INLINE_APPEND_BYTE.findall(original))

    if block_count != 9:
        fail(f"expected 9 bundled helper sections, found {block_count}")
    if (old_uint_count, old_byte_count) == (0, 0) and (
        inline_uint_count,
        inline_byte_count,
    ) == (9, 9):
        print("simdjson_i686_odr_patch_status=already_applied")
        print(f"simdjson_odr_patcher_sha256={hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}")
        print(f"simdjson_header_sha256={hashlib.sha256(header.read_bytes()).hexdigest()}")
        print("simdjson_helper_sections=9")
        return
    if (old_uint_count, old_byte_count, inline_uint_count, inline_byte_count) != (
        9,
        9,
        0,
        0,
    ):
        fail(
            "unexpected helper definitions "
            f"(old append_uint={old_uint_count}, append_byte={old_byte_count}; "
            f"inline append_uint={inline_uint_count}, append_byte={inline_byte_count})"
        )

    updated, changed_uint = APPEND_UINT.subn(
        lambda match: "inline " + match.group(0), original
    )
    updated, changed_byte = APPEND_BYTE.subn(
        lambda match: "inline " + match.group(0), updated
    )
    if (changed_uint, changed_byte) != (9, 9):
        fail(f"unexpected replacement counts: append_uint={changed_uint}, append_byte={changed_byte}")

    temporary_name = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=header.parent, prefix=f".{header.name}.", delete=False
        ) as temporary:
            temporary_name = temporary.name
            temporary.write(updated)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.chmod(temporary_name, mode)
        os.replace(temporary_name, header)
    except OSError as error:
        if temporary_name is not None:
            try:
                Path(temporary_name).unlink()
            except OSError:
                pass
        fail(f"cannot atomically update pinned Node header: {error}")

    print("simdjson_i686_odr_patch_status=applied")
    print(f"simdjson_odr_patcher_sha256={hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}")
    print(f"simdjson_header_sha256={hashlib.sha256(header.read_bytes()).hexdigest()}")
    print("simdjson_helper_sections=9")


if __name__ == "__main__":
    main()
