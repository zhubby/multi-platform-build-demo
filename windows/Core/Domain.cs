// [INPUT]: 接收界面草稿、服务地址和 API JSON。
// [OUTPUT]: 导出记录、验证、URL 规范化与快照缓存。
// [POS]: WinUI 与控制台测试共用领域层；不依赖 Windows。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
namespace TaskNotes.Core;
public static class Domain {
    public static bool ValidTitle(string title) => title.Trim().EnumerateRunes().Count() is >= 1 and <= 200;
    public static string CacheKey(string url) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(url)));
    public static string NormalizeUrl(string value) {
        value = value.Trim().TrimEnd((char)47);
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https") || uri.Query.Length > 0 || uri.Fragment.Length > 0 || uri.UserInfo.Length > 0)
            throw new ArgumentException("请输入完整 HTTP 或 HTTPS 服务地址，且不含凭据与查询参数。");
        return value;
    }
    public static bool MatchesAddress(string input, string connected) { try { return NormalizeUrl(input) == connected; } catch (ArgumentException) { return false; } }
    public static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };
}
public sealed record TaskRecord(string Id, string Title, bool Completed, long Revision, string CreatedAt, string UpdatedAt);
public sealed record NoteRecord(string Id, string Title, string Body, long Revision, string CreatedAt, string UpdatedAt);
public sealed record Snapshot(string Url, List<TaskRecord> Tasks, List<NoteRecord> Notes, string RefreshedAt);
public sealed class Cache(string root) {
    public Snapshot? Load(string url) {
        try { var value = JsonSerializer.Deserialize<Snapshot>(File.ReadAllText(Path.Combine(root, Domain.CacheKey(url) + ".json")), Domain.Json); return value?.Url == url ? value : null; }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return null; }
    }
    public void Save(Snapshot snapshot) {
        Directory.CreateDirectory(root);
        var path = Path.Combine(root, Domain.CacheKey(snapshot.Url) + ".json");
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(snapshot, Domain.Json));
        File.Move(temporary, path, true);
    }
}
