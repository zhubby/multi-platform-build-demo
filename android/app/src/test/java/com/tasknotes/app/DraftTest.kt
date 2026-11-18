/**
 * [INPUT]: 依赖纯 Kotlin 草稿规则与明确的 HTTP 或传输错误。
 * [OUTPUT]: 验证响应丢失后禁止重复创建，以及刷新和用户核对边界。
 * [POS]: 写入结果不确定场景的设备无关回归入口。
 * [PROTOCOL]: Update this header on change, then check AGENTS.md
 */
package com.tasknotes.app

import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

class DraftTest {
    @Test fun lostResponseBlocksResubmittingNewDraft() {
        val draft = Draft("tasks", title = "不能重复创建")
        val retained = draft.afterFailedWrite(IOException("response lost after server commit"))
        assertEquals(draft.title, retained.title)
        assertNull(retained.id)
        assertTrue(retained.uncertain)
        assertFalse(retained.canSubmit)
    }
    @Test fun explicitContractRejectionsKeepKnownDraftEditable() {
        for (status in listOf(400, 401, 404, 405, 409, 413)) {
            val draft = Draft("notes", title = "仍然保留草稿", body = "正文")
            val retained = draft.afterFailedWrite(ApiException(status, "rejected"))
            assertEquals(draft, retained)
            assertTrue(retained.canSubmit)
        }
    }
    @Test fun unknownServerFailureAlsoRequiresConfirmation() {
        assertTrue(Draft("tasks", title = "正文").afterFailedWrite(ApiException(500, "unknown result")).uncertain)
    }
    @Test fun onlySuccessfulRefreshAllowsExplicitConfirmation() {
        val draft = Draft("tasks", title = "保留内容", uncertain = true)
        assertFalse(draft.canSubmit)
        assertThrows(IllegalArgumentException::class.java) { draft.acknowledgeAfterRefresh(false) }
        val confirmed = draft.acknowledgeAfterRefresh(true)
        assertEquals(draft.title, confirmed.title)
        assertFalse(confirmed.uncertain)
        assertTrue(confirmed.canSubmit)
    }
}
