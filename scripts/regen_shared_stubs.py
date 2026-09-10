#!/usr/bin/env python3
"""Regenerate game/ReplicatedStorage/Shared LSP stubs as re-export shims.

Each stub requires the real module in src/shared and forwards its exported
types, so luau-lsp sees a single module identity whether code requires
@game/ReplicatedStorage/Shared/X or the sourcemap path. Run after adding,
removing, or changing `export type` declarations in src/shared modules.

Usage: python3 scripts/regen_shared_stubs.py
"""

import os
import re
import shutil
import sys

EXPORT_TYPE_RE = re.compile(r"^export type ([A-Za-z0-9_]+)(<[^=]+>)?\s*=", re.MULTILINE)


def main() -> None:
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = os.path.join(repo, "src", "shared")
    dest = os.path.join(repo, "game", "ReplicatedStorage", "Shared")

    if os.path.islink(dest):
        os.remove(dest)
    elif os.path.isdir(dest):
        shutil.rmtree(dest)

    count = 0
    for root, _, files in os.walk(src):
        for name in sorted(files):
            if not name.endswith(".luau"):
                continue
            src_file = os.path.join(root, name)
            rel = os.path.relpath(src_file, src)
            module = os.path.splitext(rel)[0]
            text = open(src_file).read()

            depth = len(rel.split(os.sep)) + 2  # game/ReplicatedStorage/Shared
            back = "/".join([".."] * depth)
            lines = [f'local Inner = require("{back}/src/shared/{module}")']
            for type_name, generics in EXPORT_TYPE_RE.findall(text):
                if generics:
                    sys.exit(f"generic export type {type_name}{generics} in {rel}: teach this script to forward generics")
                lines.append(f"export type {type_name} = Inner.{type_name}")
            lines.append("return Inner")

            out = os.path.join(dest, rel)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "w") as f:
                f.write("\n".join(lines) + "\n")
            count += 1
    print(f"{count} shared stubs written to {dest}")


if __name__ == "__main__":
    main()
