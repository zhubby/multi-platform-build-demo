<!--
[INPUT]: 已批准的单用户联机同步需求。
[OUTPUT]: 提供五端共用的请求、响应、缓存和错误契约。
[POS]: 服务端与客户端实现的唯一业务协议。
[PROTOCOL]: Update this header on change, then check AGENTS.md
-->
# TaskNotes API v1

服务地址不包含 `/api/v1`。所有业务请求附带 `Authorization: Bearer <token>`。
令牌只保留在进程内存，不写入配置、缓存、日志或制品。
`GET /healthz` 不鉴权，返回 `{"status":"ok"}`。
请求与响应均使用 UTF-8 JSON。时间使用 UTC RFC3339，允许小数秒。

## 数据

Task: `id: string(UUID)`、`title: string`、`completed: boolean`、
`revision: integer`、`created_at: string`、`updated_at: string`。

Note: `id: string(UUID)`、`title: string`、`body: string`、
`revision: integer`、`created_at: string`、`updated_at: string`。

ID、时间与 revision 由服务端生成。初始 revision 为 1，每次更新递增。
title 去除首尾空白后包含 1–200 个 Unicode 字符。body 允许为空，最多 1 MiB UTF-8。
标题和正文是纯文本。任务搜索匹配标题，笔记搜索匹配标题与正文。

## 路由

下表 `resources` 为 `tasks` 或 `notes`。

| 方法 | 路径 | 请求 | 成功响应 |
|---|---|---|---|
| GET | `/api/v1/resources` | 无 | 200 `{"items":[...]}` |
| GET | `/api/v1/resources/{id}` | 无 | 200 单条记录 |
| POST | `/api/v1/tasks` | `{"title":"买牛奶","completed":false}` | 201 Task |
| POST | `/api/v1/notes` | `{"title":"想法","body":"正文"}` | 201 Note |
| PUT | `/api/v1/tasks/{id}` | `{"title":"买牛奶","completed":true,"revision":1}` | 200 Task |
| PUT | `/api/v1/notes/{id}` | `{"title":"想法","body":"正文","revision":1}` | 200 Note |
| DELETE | `/api/v1/resources/{id}?revision=1` | 无 | 204，无响应体 |

列表按 `updated_at DESC, id ASC` 排序。创建请求包含全部可编辑字段。
PUT 是完整更新，包含全部可编辑字段和已读取的 revision。
DELETE 必须携带 revision。记录已被删除返回 404；修订号过期返回 409。

## 错误

统一格式：`{"error":{"code":"conflict","message":"记录已在其他设备修改，请刷新后重试。"}}`。
状态码：400 `invalid_request`、401 `unauthorized`、404 `not_found`、
409 `conflict`、405 `method_not_allowed`、413 `request_too_large`、500 `internal_error`。
未知 JSON 字段、非法 JSON、缺失必需字段返回 400。请求体上限 2 MiB。
内部错误不返回数据库路径、令牌或底层 SQL。

## 客户端行为

每次刷新分别请求任务与笔记。两个读取均成功后，以一个快照原子替换缓存。
缓存保存服务地址、两类完整列表与最后成功刷新时间。按服务地址隔离缓存。
连接地址改变后不得显示前一个服务的数据。令牌不进入缓存。
启动、回到前台与手动刷新触发读取。没有后台轮询和离线写入队列。
未验证连接或刷新失败时保持只读，显示缓存时间与可重试错误。
写入成功后刷新完整快照；写入失败、409 或刷新失败不丢弃用户草稿。
搜索和完成状态筛选在当前完整快照上执行。列表为空显示可操作的空状态。
401 提示重新输入令牌；409 提示刷新后检查草稿；不自动覆盖其他端更新。
设置页仅持久化服务地址。内网开发配置允许 HTTP，正式分发需要 HTTPS。
