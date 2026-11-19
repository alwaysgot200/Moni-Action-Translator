#!/usr/bin/env python3
"""把翻译动作打成 Moni 可导入的 zip；zip 根必须直接是 action.json。

发行包只含运行时文件：清单、入口、lib、locales、README；tests/tools/.git/*.zip/*.sig
一律不进包。签名在打包之后进行（见 docs/ACTION_DEVELOPER_GUIDE.md §7.3）。
"""
import json
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = json.loads((ROOT / "action.json").read_text(encoding="utf-8"))
OUT = ROOT.parent / f"{MANIFEST['id']}-{MANIFEST['version']}.zip"

INCLUDE = ["action.json", "main.lua", "lib", "locales", "README.md"]
SKIP_PARTS = {"__pycache__", ".git", "tests", "tools", "dist"}


def iter_files(path: pathlib.Path):
    if path.is_file():
        yield path
        return
    for child in sorted(path.rglob("*")):
        if child.is_file() and not (SKIP_PARTS & set(child.relative_to(ROOT).parts)):
            yield child


def main() -> int:
    for name in INCLUDE:
        if not (ROOT / name).exists():
            print(f"missing {name}", file=sys.stderr)
            return 1
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for name in INCLUDE:
            for file in iter_files(ROOT / name):
                zf.write(file, file.relative_to(ROOT).as_posix())
    print(f"{OUT} {OUT.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
