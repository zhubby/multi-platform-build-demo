# [INPUT]: 临时制品、版本与 package.py 的公开入口。
# [OUTPUT]: 验证摘要、篡改拒绝与路径隔离。
# [POS]: 构建交付行为测试，不依赖真实 SDK。
# [PROTOCOL]: Update this header on change, then check AGENTS.md
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("package.py")


class PackageTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("tasknotes_package", MODULE_PATH)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "dist").mkdir()
        (self.root / "VERSION").write_text("0.1.0\n")
        self.artifact = self.root / "dist" / "tasknotes-linux-x64.tar.gz"
        self.artifact.write_bytes(b"native application")

    def test_manifest_verifies_then_detects_tampering(self):
        path = self.module.create(self.root, "linux", "x64", [self.artifact], {"rust": "1.95.0"})
        self.module.verify(path)
        doc = json.loads(path.read_text())
        self.assertEqual(doc["version"], "0.1.0")
        self.assertEqual(doc["tools"], {"rust": "1.95.0"})
        self.artifact.write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "摘要|大小"):
            self.module.verify(path)

    def test_rejects_outside_artifact_and_symlink(self):
        outside = self.root / "outside.zip"
        outside.write_bytes(b"outside")
        with self.assertRaises(ValueError):
            self.module.create(self.root, "linux", "x64", [outside], {})
        link = self.root / "dist" / "link.zip"
        link.symlink_to(outside)
        with self.assertRaises(ValueError):
            self.module.create(self.root, "linux", "x64", [link], {})

    def test_rejects_manifest_path_traversal(self):
        path = self.module.create(self.root, "linux", "x64", [self.artifact], {})
        doc = json.loads(path.read_text())
        doc["artifacts"][0]["file"] = "../VERSION"
        path.write_text(json.dumps(doc))
        with self.assertRaises(ValueError):
            self.module.verify(path)


if __name__ == "__main__":
    unittest.main()
