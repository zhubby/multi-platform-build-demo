/**
 * [INPUT]: 依赖共享 JSON 样例、JVM 临时目录与本地 HTTP 服务。
 * [OUTPUT]: 验证解码、URL 隔离、令牌排除和冲突错误。
 * [POS]: Android 业务层的设备无关回归入口。
 * [PROTOCOL]: Update this header on change, then check AGENTS.md
 */
package com.tasknotes.app

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files

class CoreTest {
    private fun fixtures() = JSONObject(File("../../contracts/fixtures.json").readText())
    @Test fun decodesSharedFixturesWithoutLosingUnicodeOrRevision() {
        val fixture = fixtures()
        val tasks = Codec.tasks(fixture.getJSONObject("tasks").toString())
        val notes = Codec.notes(fixture.getJSONObject("notes").toString())
        assertEquals("准备五端构建验收", tasks.single().title)
        assertFalse(tasks.single().completed)
        assertEquals(2L, notes.single().revision)
        assertTrue(notes.single().body.contains("🚀"))
        assertTrue(Codec.tasks(fixture.getJSONObject("empty").toString()).isEmpty())
    }
    @Test fun cacheIsAtomicAndIsolatedByNormalizedUrl() {
        val folder = Files.createTempDirectory("tasknotes-cache").toFile()
        try {
            val cache = SnapshotCache(folder)
            val snapshot = Snapshot(Codec.tasks(fixtures().getJSONObject("tasks").toString()), Codec.notes(fixtures().getJSONObject("notes").toString()), "2026-11-18T09:00:00Z")
            cache.write("http://localhost:8080/", snapshot)
            assertEquals(snapshot, cache.read("http://localhost:8080"))
            assertNull(cache.read("http://localhost:9090"))
            assertFalse(folder.walkTopDown().filter { it.isFile }.any { it.readText().contains("Bearer") })
        } finally { folder.deleteRecursively() }
    }
    @Test fun realHttpReports409AndSendsMemoryToken() {
        var authorization: String? = null
        var received = ""
        LocalHttpServer { request ->
            authorization = request.authorization
            received = request.body
            HttpReply(409, fixtures().getJSONObject("conflict").toString())
        }.use { server ->
            val api = ApiClient(server.url, "private-token")
            try { api.saveTask(Task("id", "草稿", false, 2, "", "")); fail("must report conflict") }
            catch (error: ApiException) { assertEquals(409, error.status); assertTrue(error.message!!.contains("刷新")) }
            assertEquals("Bearer private-token", authorization)
            assertEquals(2L, JSONObject(received).getLong("revision"))
        }
    }
    @Test fun failedSecondReadDoesNotReplaceCachedSnapshot() {
        val folder = Files.createTempDirectory("tasknotes-cache").toFile()
        LocalHttpServer { request ->
            if (request.path == "/api/v1/tasks") HttpReply(200, fixtures().getJSONObject("tasks").toString()) else HttpReply(500, "")
        }.use { server ->
            try {
                val cache = SnapshotCache(folder)
                val old = Snapshot(emptyList(), emptyList(), "old")
                cache.write(server.url, old)
                try { Repository(ApiClient(server.url, "token"), cache, server.url).refresh(); fail("must reject partial snapshot") } catch (_: ApiException) { }
                assertEquals(old, cache.read(server.url))
            } finally { folder.deleteRecursively() }
        }
    }
}
