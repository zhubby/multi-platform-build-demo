#!/usr/bin/env python3
# [INPUT]: dist 内普通制品、VERSION 与固定源码提交。
# [OUTPUT]: 生成或验证版本化 JSON 清单与 SHA256SUMS。
# [POS]: 所有原生目标共用的交付边界；不读取凭据或环境转储。
# [PROTOCOL]: Update this header on change, then check AGENTS.md
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def git(root, *args):
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def atomic_write(path, content):
    fd, name = tempfile.mkstemp(prefix=".tasknotes-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def create(root, target, arch, artifacts, tools):
    if not re.fullmatch(r"[a-z][a-z0-9-]*", target) or not re.fullmatch(r"[a-z0-9]+", arch):
        raise ValueError("目标或架构名称无效")
    root = root.resolve()
    dist = root / "dist"
    dist.mkdir(exist_ok=True)
    entries = []
    for candidate in artifacts:
        if candidate.is_symlink() or not candidate.is_file() or candidate.resolve().parent != dist:
            raise ValueError("制品必须是 dist 内的普通文件")
        if "\n" in candidate.name or "\r" in candidate.name:
            raise ValueError("制品名称不能包含换行")
        entries.append({"file": candidate.name, "size": candidate.stat().st_size, "sha256": digest(candidate)})
    if not entries or len({entry["file"] for entry in entries}) != len(entries):
        raise ValueError("制品不能为空或重复")
    entries.sort(key=lambda entry: entry["file"])
    manifest = {
        "schema_version": 1,
        "application": "TaskNotes",
        "version": (root / "VERSION").read_text().strip(),
        "source_commit": git(root, "rev-parse", "HEAD"),
        "source_dirty": git(root, "status", "--porcelain", "--untracked-files=normal") != "",
        "target": target,
        "architecture": arch,
        "tools": dict(sorted(tools.items())),
        "artifacts": entries,
    }
    path = dist / f"tasknotes-{target}-{arch}-manifest.json"
    atomic_write(path, json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    sums = "".join(f"{entry['sha256']}  {entry['file']}\n" for entry in entries)
    sums += f"{digest(path)}  {path.name}\n"
    atomic_write(dist / f"tasknotes-{target}-{arch}-SHA256SUMS", sums)
    return path


def verify(path):
    manifest = json.loads(path.read_text())
    if manifest.get("schema_version") != 1 or not manifest.get("artifacts"):
        raise ValueError("清单版本或制品列表无效")
    for entry in manifest["artifacts"]:
        name = entry["file"]
        if not name or Path(name).name != name or "\\" in name:
            raise ValueError("清单制品路径越界")
        artifact = path.parent / name
        if artifact.is_symlink() or not artifact.is_file():
            raise ValueError("制品缺失或不是普通文件")
        if artifact.stat().st_size != entry["size"] or digest(artifact) != entry["sha256"]:
            raise ValueError(f"制品大小或摘要不一致: {name}")
    return manifest


def main():
    parser = argparse.ArgumentParser(description="TaskNotes 制品清单")
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("create")
    build.add_argument("--target", required=True)
    build.add_argument("--arch", required=True)
    build.add_argument("--artifact", type=Path, action="append", required=True)
    build.add_argument("--tool", action="append", default=[], help="名称=版本；不得传入凭据")
    check = commands.add_parser("verify")
    check.add_argument("manifest", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "verify":
            verify(args.manifest)
            print(f"制品校验通过: {args.manifest.name}")
        else:
            tools = {}
            for item in args.tool:
                key, sep, value = item.partition("=")
                if not sep or not key:
                    raise ValueError("工具版本使用 名称=版本")
                tools[key] = value
            root = Path(__file__).resolve().parent.parent
            print(create(root, args.target, args.arch, args.artifact, tools))
    except (ValueError, KeyError, OSError, json.JSONDecodeError) as error:
        parser.exit(1, f"制品清单失败: {error}\n")


if __name__ == "__main__":
    main()
