/**
 * [INPUT]: 依赖 Core 协议入口、Draft 编辑规则和应用私有目录与 Compose 可观察状态。
 * [OUTPUT]: 提供内存令牌、按地址隔离草稿和写入结果锁定状态。
 * [POS]: Activity 与数据层之间的状态边界；网络串行执行，界面只在主线程更新。
 * [PROTOCOL]: Update this header on change, then check AGENTS.md
 */
package com.tasknotes.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import java.util.concurrent.Executors

internal class AppState(context: Context) {
    private val preferences = context.getSharedPreferences("connection", Context.MODE_PRIVATE)
    private val cache = SnapshotCache(File(context.filesDir, "snapshots"))
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    var url by mutableStateOf(preferences.getString("url", "").orEmpty())
        private set
    var token by mutableStateOf("")
        private set
    var snapshot by mutableStateOf(if (url.isBlank()) null else cache.read(url))
        private set
    var verified by mutableStateOf(false)
        private set
    var busy by mutableStateOf(false)
        private set
    var message by mutableStateOf("请输入令牌并刷新。连接验证前仅显示只读缓存。")
        private set
    var settingsVisible by mutableStateOf(url.isBlank())
    var editorVisible by mutableStateOf(false)
    private val drafts = mutableStateMapOf<String, Draft>()
    val draft get() = drafts[url]
    val writable get() = verified && !busy

    fun configure(address: String, credential: String): String? {
        if (busy) return "请求仍在进行。"
        val normalized = try { normalizeUrl(address) } catch (error: IllegalArgumentException) { return error.message }
        if (credential.isBlank()) return "请输入令牌。令牌仅保存在进程内存。"
        val changed = normalized != url
        url = normalized
        token = credential
        preferences.edit().putString("url", normalized).apply()
        verified = false
        if (changed) {
            snapshot = cache.read(url)
            editorVisible = false
        }
        settingsVisible = false
        refresh()
        return null
    }
    fun refresh() = execute(null)
    fun create(kind: String) {
        if (!writable) return
        if (draft == null) drafts[url] = Draft(kind)
        editorVisible = true
    }
    fun edit(task: Task) {
        if (draft == null) drafts[url] = Draft("tasks", task.title, completed = task.completed, task = task)
        editorVisible = true
    }
    fun edit(note: Note) {
        if (draft == null) drafts[url] = Draft("notes", note.title, note.body, note = note)
        editorVisible = true
    }
    fun update(draft: Draft) { drafts[url] = draft }
    fun discard() { drafts.remove(url); editorVisible = false }
    fun reloadDraft() {
        val current = draft ?: return
        val task = snapshot?.tasks?.find { it.id == current.id }
        val note = snapshot?.notes?.find { it.id == current.id }
        if (current.kind == "tasks" && task != null) drafts[url] = Draft("tasks", task.title, completed = task.completed, task = task)
        if (current.kind == "notes" && note != null) drafts[url] = Draft("notes", note.title, note.body, note = note)
    }
    fun confirmWriteOutcome() {
        if (!writable) return
        draft?.let { drafts[url] = it.acknowledgeAfterRefresh(verified) }
    }
    fun save() {
        val current = draft ?: return
        if (!writable || !current.canSubmit) return
        execute { api ->
            if (current.kind == "tasks") {
                val saved = current.task?.let { api.saveTask(it.copy(title = current.title, completed = current.completed)) }
                    ?: api.createTask(current.title, current.completed)
                current.copy(task = saved)
            } else {
                val saved = current.note?.let { api.saveNote(it.copy(title = current.title, body = current.body)) }
                    ?: api.createNote(current.title, current.body)
                current.copy(note = saved)
            }
        }
    }
    fun delete() {
        val current = draft ?: return
        if (!writable || current.id == null || current.deleted || current.uncertain) return
        execute { api ->
            api.delete(current.kind, current.id!!, current.task?.revision ?: current.note!!.revision)
            current.copy(deleted = true)
        }
    }
    private fun execute(write: ((ApiClient) -> Draft)?) {
        if (busy) return
        if (url.isBlank() || token.isBlank()) {
            verified = false
            message = "请在连接设置中输入服务地址与令牌，然后刷新。"
            return
        }
        val requestUrl = url
        val requestToken = token
        val originalDraft = draft
        busy = true
        message = if (write == null) "正在刷新任务与笔记…" else "正在保存并刷新…"
        executor.execute {
            var saved: Draft? = null
            try {
                val api = ApiClient(requestUrl, requestToken)
                saved = write?.invoke(api)
                val result = Repository(api, cache, requestUrl).refresh()
                main.post {
                    if (url == requestUrl) {
                        snapshot = result
                        verified = true
                        if (write != null) { drafts.remove(url); editorVisible = false }
                        message = "已连接，数据已刷新。"
                    }
                    busy = false
                }
            } catch (error: Exception) {
                val succeeded = saved != null
                val retained = saved ?: if (write != null) originalDraft?.afterFailedWrite(error) else null
                val detail = if (error is ApiException) error.message.orEmpty() else "连接失败或响应无效，请检查网络与地址后重试。"
                main.post {
                    if (url == requestUrl) {
                        verified = false
                        if (retained != null) drafts[url] = retained
                        message = when {
                            succeeded -> "写入已成功，但刷新失败。草稿已保留，请先刷新后核对。$detail"
                            retained?.uncertain == true -> "写入结果不确定。请先刷新并检查列表。核对后再决定是否继续；直接重复新建会产生重复记录。$detail"
                            else -> "$detail 草稿已保留，当前仅供读取。"
                        }
                    }
                    busy = false
                }
            }
        }
    }
}
