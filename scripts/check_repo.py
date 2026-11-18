#!/usr/bin/env python3
# [INPUT]: Git 可见文件、OpenAPI 与跨语言样例。
# [OUTPUT]: 检查文档契约、文件行数与协议引用的静态一致性。
# [POS]: 不需要原生 SDK 的仓库完整性入口。
# [PROTOCOL]: Update this header on change, then check AGENTS.md
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUSINESS = {".go", ".swift", ".kt", ".cs", ".rs", ".py"}
PROTOCOL = "[PROTOCOL]: Update this header on change, then check AGENTS.md"


def check():
    errors = []
    document = json.loads((ROOT / "contracts/openapi.json").read_text())

    def references(value):
        if isinstance(value, dict):
            if "$ref" in value:
                node = document
                for key in value["$ref"].removeprefix("#/").split("/"):
                    node = node[key]
            for child in value.values():
                references(child)
        elif isinstance(value, list):
            for child in value:
                references(child)

    references(document)
    fixtures = json.loads((ROOT / "contracts/fixtures.json").read_text())
    for key, schema in [("tasks", "Task"), ("notes", "Note")]:
        required = set(document["components"]["schemas"][schema]["required"])
        for item in fixtures[key]["items"]:
            if set(item) != required:
                errors.append(f"样例与 {schema} 字段不一致")
    result = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT, capture_output=True, check=True)
    for name in set(result.stdout.decode().split("\0")) - {""}:
        path = ROOT / name
        if not path.is_file() or path.suffix in {".jar", ".png", ".ico", ".icns"}:
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        # 上游生成的依赖锁不可拆分；行数约束作用于人工维护的文件。
        generated_lock = path.name in {"Cargo.lock", "packages.lock.json", "gradle.lockfile"}
        if not generated_lock and len(text.splitlines()) > 800:
            errors.append(f"{name}: 超过 800 行")
        if path.suffix in BUSINESS:
            header = "\n".join(text.splitlines()[:25])
            if not all(part in header for part in ["[INPUT]", "[OUTPUT]", "[POS]", PROTOCOL]):
                errors.append(f"{name}: 缺失 L3 契约")
            mapping = path.parent / "AGENTS.md"
            if not mapping.is_file():
                errors.append(f"{name}: 缺失目录 L2")
            elif path.name not in mapping.read_text():
                errors.append(f"{name}: 未登记 L2")
        if path.name == "AGENTS.md" and PROTOCOL not in text:
            errors.append(f"{name}: 缺失 PROTOCOL")
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("OpenAPI、公共样例、L2/L3 契约与文件行数检查通过。")
    return 0


if __name__ == "__main__":
    sys.exit(check())
