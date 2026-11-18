// [INPUT]: 使用 HttpClient、领域模型与进程内令牌。
// [OUTPUT]: 提供快照、内存令牌更新与写入核对状态。
// [POS]: 界面唯一网络边界；两列表成功后原子替换快照。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
namespace TaskNotes.Core;
public sealed class Session : IDisposable {
    readonly HttpClient http;
    readonly Cache cache;
    public string Url { get; }
    public Snapshot Snapshot { get; private set; }
    public bool Online { get; set; }
    public bool PendingWriteReview { get; private set; }
    public void SetToken(string token) { http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token); Online = false; }
    public void AcknowledgeWrite() { if (!Online) throw new InvalidOperationException("请先刷新并检查列表。"); PendingWriteReview = false; }
    public Session(string url, string token, string cacheRoot, HttpMessageHandler? handler = null) {
        Url = url; cache = new Cache(cacheRoot);
        Snapshot = cache.Load(url) ?? new Snapshot(url, [], [], "");
        http = handler is null ? new HttpClient() : new HttpClient(handler);
        http.Timeout = TimeSpan.FromSeconds(12);
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
    }
    async Task<JsonDocument?> Request(string method, string path, object? value = null) {
        using var request = new HttpRequestMessage(new HttpMethod(method), $"{Url}/api/v1/{path}");
        if (value != null) request.Content = new StringContent(JsonSerializer.Serialize(value, Domain.Json), Encoding.UTF8, "application/json");
        using var response = await http.SendAsync(request);
        if (!response.IsSuccessStatusCode) {
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw new ApiException(401, "401：请重新输入令牌。");
            if (response.StatusCode == HttpStatusCode.Conflict) throw new ApiException(409, "409：记录已在其他设备修改。请刷新后检查保留的草稿。");
            string message = "请求失败";
            try { using var detail = JsonDocument.Parse(await response.Content.ReadAsStringAsync()); message = detail.RootElement.GetProperty("error").GetProperty("message").GetString() ?? message; } catch (JsonException) { } catch (KeyNotFoundException) { }
            throw new ApiException((int)response.StatusCode, $"{(int)response.StatusCode}：{message}");
        }
        return response.StatusCode == HttpStatusCode.NoContent ? null : JsonDocument.Parse(await response.Content.ReadAsStringAsync());
    }
    public async Task Refresh() {
        Online = false;
        using var tasks = await Request("GET", "tasks");
        using var notes = await Request("GET", "notes");
        var taskList = tasks!.RootElement.GetProperty("items").Deserialize<List<TaskRecord>>(Domain.Json) ?? throw new JsonException();
        var noteList = notes!.RootElement.GetProperty("items").Deserialize<List<NoteRecord>>(Domain.Json) ?? throw new JsonException();
        var next = new Snapshot(Url, taskList, noteList, DateTimeOffset.UtcNow.ToString("O"));
        cache.Save(next); Snapshot = next; Online = true;
    }
    public async Task Write(string method, string path, object? value = null) {
        if (!Online) throw new InvalidOperationException("当前只读，请先成功刷新。");
        if (PendingWriteReview) throw new InvalidOperationException("上次写入结果不确定。请刷新、检查列表并点击已核对结果。");
        bool accepted = false;
        try { using var response = await Request(method, path, value); accepted = true; await Refresh(); }
        catch (Exception e) { Online = false; PendingWriteReview = accepted || e is not ApiException api || api.Status >= 500; throw; }
    }
    public void Dispose() => http.Dispose();
}

public sealed class ApiException(int status, string message) : InvalidOperationException(message) { public int Status { get; } = status; }
