/**
 * [INPUT]: 依赖系统 JSON、HTTP、UTC 时间与应用私有文件目录。
 * [OUTPUT]: 提供协议模型、请求、URL 隔离缓存与双列表刷新。
 * [POS]: 界面的唯一数据入口；缓存只接收完整快照，不接收令牌。
 * [PROTOCOL]: Update this header on change, then check AGENTS.md
 */
package com.tasknotes.app

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.time.Instant

data class Task(val id: String, val title: String, val completed: Boolean, val revision: Long, val createdAt: String, val updatedAt: String)
data class Note(val id: String, val title: String, val body: String, val revision: Long, val createdAt: String, val updatedAt: String)
data class Snapshot(val tasks: List<Task>, val notes: List<Note>, val refreshedAt: String)

fun normalizeUrl(value: String): String {
    val uri = try { URI(value.trim().trimEnd('/')) } catch (_: Exception) { throw IllegalArgumentException("请输入有效的服务地址。") }
    require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrBlank() && uri.userInfo == null && uri.query == null && uri.fragment == null) {
        "服务地址须为 HTTP 或 HTTPS，且不含账号、查询或片段。"
    }
    require(!uri.path.orEmpty().endsWith("/api/v1")) { "服务地址不包含 /api/v1。" }
    return uri.toASCIIString()
}

object Codec {
    fun task(json: JSONObject) = Task(json.getString("id"), json.getString("title"), json.getBoolean("completed"), json.getLong("revision"), json.getString("created_at"), json.getString("updated_at"))
    fun note(json: JSONObject) = Note(json.getString("id"), json.getString("title"), json.getString("body"), json.getLong("revision"), json.getString("created_at"), json.getString("updated_at"))
    fun tasks(json: String): List<Task> = JSONObject(json).getJSONArray("items").let { array -> List(array.length()) { task(array.getJSONObject(it)) } }
    fun notes(json: String): List<Note> = JSONObject(json).getJSONArray("items").let { array -> List(array.length()) { note(array.getJSONObject(it)) } }
    fun taskJson(task: Task): JSONObject = JSONObject().put("id", task.id).put("title", task.title).put("completed", task.completed).put("revision", task.revision).put("created_at", task.createdAt).put("updated_at", task.updatedAt)
    fun noteJson(note: Note): JSONObject = JSONObject().put("id", note.id).put("title", note.title).put("body", note.body).put("revision", note.revision).put("created_at", note.createdAt).put("updated_at", note.updatedAt)
}

class SnapshotCache(private val folder: File) {
    private fun file(url: String): File {
        val key = MessageDigest.getInstance("SHA-256").digest(normalizeUrl(url).toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
        return File(folder, "$key.json")
    }
    @Synchronized fun write(url: String, snapshot: Snapshot) {
        check(folder.isDirectory || folder.mkdirs()) { "无法创建缓存目录。" }
        val json = JSONObject().put("url", normalizeUrl(url)).put("refreshed_at", snapshot.refreshedAt)
            .put("tasks", JSONArray(snapshot.tasks.map(Codec::taskJson)))
            .put("notes", JSONArray(snapshot.notes.map(Codec::noteJson)))
        val destination = file(url)
        val temporary = File.createTempFile("snapshot-", ".tmp", folder)
        try {
            temporary.outputStream().use { output -> output.write(json.toString().toByteArray(Charsets.UTF_8)); output.fd.sync() }
            Files.move(temporary.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } finally { temporary.delete() }
    }
    @Synchronized fun read(url: String): Snapshot? = try {
        val json = JSONObject(file(url).readText(Charsets.UTF_8))
        require(json.getString("url") == normalizeUrl(url))
        Snapshot(Codec.tasks(JSONObject().put("items", json.getJSONArray("tasks")).toString()), Codec.notes(JSONObject().put("items", json.getJSONArray("notes")).toString()), json.getString("refreshed_at"))
    } catch (_: Exception) { null }
}

class ApiException(val status: Int, message: String): IOException(message)

class ApiClient(url: String, private val token: String) {
    private val baseUrl = normalizeUrl(url)
    private fun segment(value: String) = URLEncoder.encode(value, "UTF-8").replace("+", "%20")
    private fun request(method: String, path: String, payload: JSONObject? = null): String {
        if (token.isBlank()) throw ApiException(401, "请在连接设置中重新输入令牌。")
        val connection = URI("$baseUrl/api/v1/$path").toURL().openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.connectTimeout = 8000
        connection.readTimeout = 12000
        connection.instanceFollowRedirects = false
        connection.setRequestProperty("Authorization", "Bearer $token")
        connection.setRequestProperty("Accept", "application/json")
        try {
            if (payload != null) {
                val bytes = payload.toString().toByteArray(Charsets.UTF_8)
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                connection.setFixedLengthStreamingMode(bytes.size)
                connection.outputStream.use { it.write(bytes) }
            }
            val status = connection.responseCode
            if (status !in 200..299) {
                val raw = connection.errorStream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
                val message = when (status) {
                    401 -> "认证失败，请在连接设置中重新输入令牌。"
                    409 -> "记录已在其他设备修改。请刷新后检查草稿，再决定是否重新编辑。"
                    404 -> "记录已被删除。请刷新后检查草稿。"
                    else -> try { JSONObject(raw).getJSONObject("error").getString("message") } catch (_: Exception) { "服务请求失败（HTTP $status）。" }
                }
                throw ApiException(status, message)
            }
            return if (status == 204) "" else connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } finally { connection.disconnect() }
    }
    fun tasks(): List<Task> = Codec.tasks(request("GET", "tasks"))
    fun notes(): List<Note> = Codec.notes(request("GET", "notes"))
    fun createTask(title: String, completed: Boolean): Task = Codec.task(JSONObject(request("POST", "tasks", JSONObject().put("title", title.trim()).put("completed", completed))))
    fun saveTask(task: Task): Task = Codec.task(JSONObject(request("PUT", "tasks/${segment(task.id)}", JSONObject().put("title", task.title.trim()).put("completed", task.completed).put("revision", task.revision))))
    fun createNote(title: String, body: String): Note = Codec.note(JSONObject(request("POST", "notes", JSONObject().put("title", title.trim()).put("body", body))))
    fun saveNote(note: Note): Note = Codec.note(JSONObject(request("PUT", "notes/${segment(note.id)}", JSONObject().put("title", note.title.trim()).put("body", note.body).put("revision", note.revision))))
    fun delete(kind: String, id: String, revision: Long) {
        require(kind in listOf("tasks", "notes"))
        request("DELETE", "$kind/${segment(id)}?revision=$revision")
    }
}

class Repository(private val api: ApiClient, private val cache: SnapshotCache, private val url: String) {
    fun refresh(): Snapshot {
        val tasks = api.tasks()
        val notes = api.notes()
        return Snapshot(tasks, notes, Instant.now().toString()).also { cache.write(url, it) }
    }
}
