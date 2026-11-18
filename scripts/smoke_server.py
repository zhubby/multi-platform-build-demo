#!/usr/bin/env python3
# [INPUT]: 已启动服务地址与 TASKNOTES_TOKEN。
# [OUTPUT]: 验证真实 HTTP 下的任务、笔记、冲突、删除与健康检查。
# [POS]: 二进制或容器部署后的业务烟测；令牌不进入输出。
# [PROTOCOL]: Update this header on change, then check AGENTS.md
import argparse
import json
import os
import urllib.error
import urllib.request
import uuid


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8080")
    args = parser.parse_args()
    token = os.environ["TASKNOTES_TOKEN"]

    def request(method, path, body=None, expected=200, auth=True):
        headers = {"Content-Type": "application/json"}
        if auth:
            headers["Authorization"] = "Bearer " + token
        req = urllib.request.Request(args.url.rstrip("/") + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
        try:
            response = urllib.request.urlopen(req, timeout=10)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            raw = response.read()
            if response.status != expected:
                raise RuntimeError(f"{method} {path}: 预期 {expected}，实际 {response.status}")
            return json.loads(raw) if raw else None

    request("GET", "/healthz", auth=False)
    request("GET", "/api/v1/tasks", expected=401, auth=False)
    created = []
    try:
        for kind, content in [("tasks", {"title": "验收任务 🚀 " + uuid.uuid4().hex[:8], "completed": False}), ("notes", {"title": "验收笔记", "body": "第一行\n第二行"})]:
            item = request("POST", "/api/v1/" + kind, content, expected=201)
            path = "/api/v1/" + kind + "/" + item["id"]
            created.append((path, item["revision"]))
            assert any(entry["id"] == item["id"] for entry in request("GET", "/api/v1/" + kind)["items"])
            if kind == "tasks":
                content["completed"] = True
            else:
                content["body"] = "已从另一客户端编辑"
            updated = request("PUT", path, {**content, "revision": 1})
            created[-1] = (path, updated["revision"])
            assert updated["revision"] == 2
            request("PUT", path, {**content, "revision": 1}, expected=409)
        print("真实 HTTP 烟测通过：健康、鉴权、中文 CRUD、列表刷新与修订冲突。")
    finally:
        for path, revision in created:
            request("DELETE", path + f"?revision={revision}", expected=204)


if __name__ == "__main__":
    main()
