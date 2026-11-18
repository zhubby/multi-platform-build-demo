// [INPUT]: 使用 Core、公共样例与受控 HTTP 响应。
// [OUTPUT]: 验证 Unicode、缓存隔离、原子刷新和只读边界。
// [POS]: 无测试框架依赖的跨宿主核心回归入口。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
using TaskNotes.Core;
using System.Net;
using System.Text;
using System.Text.Json;
if (args.Length == 2 && args[0] == "--live-config") { await Live.Run(args[1]); return; }
static void Check(bool value, string message) { if (!value) throw new Exception(message); }
Check(!Domain.MatchesAddress("http://b", "http://a"), "Edited address must block old session");
Check(Domain.MatchesAddress("http://a/", "http://a"), "Normalized same address must reconnect");
Check(!Domain.MatchesAddress("invalid", "http://a"), "Invalid address must block refresh");
Check(Domain.ValidTitle("任务 🚀"), "Unicode title must be valid");
Check(!Domain.ValidTitle("  "), "Empty title must fail");
Check(!Domain.ValidTitle(new string("文"[0], 201)), "Long title must fail");
Check(Domain.ValidTitle(string.Concat(Enumerable.Repeat("🚀", 200))), "Count Unicode scalars");
Check(Domain.CacheKey("http://a") != Domain.CacheKey("http://b"), "URL caches must be isolated");
var project = AppContext.BaseDirectory;
while (!File.Exists(Path.Combine(project, "contracts", "fixtures.json"))) project = Directory.GetParent(project)?.FullName ?? throw new Exception("Fixture root not found");
using var fixtures = JsonDocument.Parse(File.ReadAllText(Path.Combine(project, "contracts", "fixtures.json")));
var tasks = fixtures.RootElement.GetProperty("tasks").GetRawText(); var notes = fixtures.RootElement.GetProperty("notes").GetRawText();
var root = Path.Combine(Path.GetTempPath(), "tasknotes-core-" + Guid.NewGuid());
try {
    using var session = new Session("http://test", "test-secret", root, new SequenceHandler(tasks, notes, "{\"items\":[]}", null));
    try { await session.Write("POST", "tasks", new { title = "blocked", completed = false }); throw new Exception("Offline write allowed"); } catch (InvalidOperationException) { }
    await session.Refresh(); Check(session.Online, "Refresh must permit writes");
    var previous = session.Snapshot;
    Check(previous.Notes[0].Body.Contains("🚀"), "Fixture note body"); Check(previous.Tasks[0].Revision == 1, "Fixture task revision");
    try { await session.Refresh(); throw new Exception("Failed notes accepted"); } catch (InvalidOperationException) { }
    Check(!session.Online, "Partial failure must be read only"); Check(ReferenceEquals(previous, session.Snapshot), "Partial snapshot leaked");
    var cache = new Cache(root); Check(cache.Load("http://other") == null, "Foreign URL leaked");
    Check(cache.Load("http://test")?.Tasks.Count == 1, "Atomic cache changed after failure");
    var content = File.ReadAllText(Directory.GetFiles(root, "*.json").Single());
    Check(!content.Contains("test-secret") && !content.Contains("Authorization"), "Token persisted");
    cache.Save(previous); Check(cache.Load("http://test")?.Notes.Count == 1, "Atomic replacement failed");
} finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
var uncertainRoot = Path.Combine(Path.GetTempPath(), "tasknotes-uncertain-" + Guid.NewGuid());
try {
    using var uncertain = new Session("http://test", "test-secret", uncertainRoot, new SequenceHandler(tasks, notes, fixtures.RootElement.GetProperty("tasks").GetProperty("items")[0].GetRawText(), tasks, null, tasks, notes));
    await uncertain.Refresh();
    try { await uncertain.Write("POST", "tasks", new { title = "draft", completed = false }); throw new Exception("Refresh failure accepted"); } catch (InvalidOperationException) { }
    Check(uncertain.PendingWriteReview && !uncertain.Online, "Accepted write plus refresh failure must be uncertain");
    uncertain.SetToken("test-secret"); Check(uncertain.PendingWriteReview, "Reconnection forgot uncertain write");
    await uncertain.Refresh();
    Check(uncertain.PendingWriteReview && uncertain.Online, "Refresh must require explicit review");
    try { await uncertain.Write("POST", "tasks", new { title = "draft", completed = false }); throw new Exception("Duplicate POST allowed"); } catch (InvalidOperationException) { }
    uncertain.AcknowledgeWrite(); Check(!uncertain.PendingWriteReview, "Explicit review did not unblock");
} finally { if (Directory.Exists(uncertainRoot)) Directory.Delete(uncertainRoot, true); }
Console.WriteLine("Core tests passed: Unicode, fixtures, cache isolation, atomic refresh, offline writes, token exclusion");
sealed class SequenceHandler(params string?[] responses) : HttpMessageHandler {
    int index;
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) {
        if (request.Headers.Authorization?.ToString() != "Bearer test-secret") throw new Exception("Bearer missing");
        var body = responses[index++];
        return Task.FromResult(new HttpResponseMessage(body == null ? HttpStatusCode.InternalServerError : HttpStatusCode.OK) { Content = new StringContent(body ?? "{\"error\":{\"message\":\"fail\"}}", Encoding.UTF8, "application/json") });
    }
}
