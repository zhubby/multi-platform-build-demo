// [INPUT]: 显式传入包含服务地址和令牌的本机配置。
// [OUTPUT]: 执行真实服务 CRUD、409、缓存回归并清理创建记录。
// [POS]: 可选联机验收；默认核心测试不访问外部服务。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
using System.Text.Json;
using TaskNotes.Core;
static class Live {
    public static async Task Run(string path) {
        using var config = JsonDocument.Parse(File.ReadAllText(path));
        var url = config.RootElement.GetProperty("url").GetString()!;
        var token = config.RootElement.GetProperty("token").GetString()!;
        var marker = "CSharp验收-" + Guid.NewGuid();
        var root = Path.Combine(Path.GetTempPath(), marker);
        using var session = new Session(url, token, root);
        try {
            await session.Refresh();
            await session.Write("POST", "tasks", new { title = marker, completed = false });
            await session.Write("POST", "notes", new { title = marker, body = "真实服务中文 🚀" });
            var task = session.Snapshot.Tasks.Single(v => v.Title == marker);
            var note = session.Snapshot.Notes.Single(v => v.Title == marker);
            await session.Write("PUT", "tasks/" + task.Id, new { title = marker, completed = true, revision = task.Revision });
            await session.Write("PUT", "notes/" + note.Id, new { title = marker, body = "更新正文", revision = note.Revision });
            if (!session.Snapshot.Tasks.Single(v => v.Id == task.Id).Completed) throw new Exception("完成状态未同步");
            bool conflict = false;
            try { await session.Write("PUT", "tasks/" + task.Id, new { title = marker, completed = false, revision = task.Revision }); }
            catch (InvalidOperationException e) when (e.Message.StartsWith("409")) { conflict = true; }
            if (!conflict || session.Online) throw new Exception("409 未撤销写权限");
            using var dropped = new Session(url, token, root, new LosePostResponse());
            await dropped.Refresh();
            try { await dropped.Write("POST", "notes", new { title = marker + "-lost", body = "保留草稿" }); throw new Exception("丢响应未失败"); }
            catch (HttpRequestException) { }
            if (!dropped.PendingWriteReview || dropped.Online) throw new Exception("丢响应未标记结果不确定");
            dropped.SetToken(token);
            await dropped.Refresh();
            if (dropped.Snapshot.Notes.Count(v => v.Title == marker + "-lost") != 1) throw new Exception("真实服务未保存丢响应记录");
            try { await dropped.Write("POST", "notes", new { title = marker + "-lost", body = "保留草稿" }); throw new Exception("重复创建未阻止"); }
            catch (InvalidOperationException) { }
            dropped.AcknowledgeWrite();

        } finally {
            try {
                await session.Refresh();
                foreach (var task in session.Snapshot.Tasks.Where(v => v.Title.StartsWith(marker)).ToArray()) await session.Write("DELETE", $"tasks/{task.Id}?revision={task.Revision}");
                foreach (var note in session.Snapshot.Notes.Where(v => v.Title.StartsWith(marker)).ToArray()) await session.Write("DELETE", $"notes/{note.Id}?revision={note.Revision}");
                var cached = new Cache(root).Load(url) ?? throw new Exception("缓存未生成");
                if (cached.Tasks.Any(v => v.Title.StartsWith(marker)) || cached.Notes.Any(v => v.Title.StartsWith(marker))) throw new Exception("删除后缓存残留");
            } finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
        Console.WriteLine("真实 Go 服务回归通过：任务/笔记创建、修改、409、删除、缓存刷新；创建记录已清理。");
    }
}

sealed class LosePostResponse : DelegatingHandler {
    bool lost;
    public LosePostResponse() { InnerHandler = new HttpClientHandler(); }
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) {
        var response = await base.SendAsync(request, cancellationToken);
        if (request.Method == HttpMethod.Post && !lost) { lost = true; response.Dispose(); throw new HttpRequestException("测试主动丢弃已提交 POST 响应"); }
        return response;
    }
}
