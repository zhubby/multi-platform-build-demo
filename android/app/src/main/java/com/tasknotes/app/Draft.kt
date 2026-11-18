/**
 * [INPUT]: 依赖 Core 协议模型与服务器错误状态。
 * [OUTPUT]: 提供可测试草稿、修订比较与写入结果确认状态。
 * [POS]: 界面和网络状态共用的纯 Kotlin 编辑规则，不访问 Android 存储。
 * [PROTOCOL]: Update this header on change, then check AGENTS.md
 */
package com.tasknotes.app

internal data class Draft(
    val kind: String,
    val title: String = "",
    val body: String = "",
    val completed: Boolean = false,
    val task: Task? = null,
    val note: Note? = null,
    val deleted: Boolean = false,
    val uncertain: Boolean = false
) {
    val id get() = task?.id ?: note?.id
    val valid get(): Boolean {
        val trimmed = title.trim()
        return trimmed.codePointCount(0, trimmed.length) in 1..200 && body.toByteArray(Charsets.UTF_8).size <= 1024 * 1024
    }
    val canSubmit get() = valid && !deleted && !uncertain
    fun afterFailedWrite(error: Exception): Draft = copy(
        uncertain = uncertain || error !is ApiException || error.status !in setOf(400, 401, 404, 405, 409, 413)
    )
    fun acknowledgeAfterRefresh(verified: Boolean): Draft {
        require(verified) { "先刷新并核对服务端记录，再确认写入结果。" }
        return copy(uncertain = false)
    }
    fun isStale(snapshot: Snapshot?): Boolean = when {
        task != null -> snapshot?.tasks?.find { it.id == task.id }?.revision != task.revision
        note != null -> snapshot?.notes?.find { it.id == note.id }?.revision != note.revision
        else -> false
    }
}
