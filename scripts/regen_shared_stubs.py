#!/usr/bin/env python3
"""Regenerate the gitignored game/ tree of LSP stubs as re-export shims.

The .luaurc alias `@game` resolves to game/, so each stub requires the real
module under src/ and forwards its exported types. luau-lsp then sees a single
module identity whether code requires @game/ReplicatedStorage/Shared/X or the
sourcemap path. Run after adding or removing modules or `export type`
declarations under any of the mapped source dirs (scripts/analyze.sh runs it).

Usage: python3 scripts/regen_shared_stubs.py
"""

import os
import re
import shutil
import sys

# (alias subpath under game/, source dir under the repo)
MAPPINGS = [
    ("ReplicatedStorage/Shared", "src/shared"),
    ("ServerScriptService/GameData", "src/server/GameData"),
]

EXPORT_TYPE_RE = re.compile(r"^export type ([A-Za-z0-9_]+)(<[^=]+>)?\s*=", re.MULTILINE)


def regen(repo: str, alias_subpath: str, source_dir: str) -> int:
    src = os.path.join(repo, source_dir)
    dest = os.path.join(repo, "game", alias_subpath)

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

            depth = len(rel.split(os.sep)) + alias_subpath.count("/") + 1 + 1  # game/ + alias segments
            back = "/".join([".."] * depth)
            lines = [f'local Inner = require("{back}/{source_dir}/{module}")']
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
    print(f"{count} stubs written to {dest}")
    return count


def main() -> None:
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for alias_subpath, source_dir in MAPPINGS:
        regen(repo, alias_subpath, source_dir)


if __name__ == "__main__":
    main()
