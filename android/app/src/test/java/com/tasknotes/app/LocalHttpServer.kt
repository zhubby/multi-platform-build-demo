/**
 * [INPUT]: 依赖 JVM ServerSocket 与 HTTP 请求字节。
 * [OUTPUT]: 提供真实本地 TCP 响应，供协议与错误回归测试使用。
 * [POS]: 测试夹具；不依赖 Android 不存在的 JDK HTTP Server 模块。
 * [PROTOCOL]: Update this header on change, then check AGENTS.md
 */
package com.tasknotes.app

import java.io.BufferedInputStream
import java.io.Closeable
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread

internal data class HttpRequest(val path: String, val authorization: String?, val body: String)
internal data class HttpReply(val status: Int, val body: String)
internal class LocalHttpServer(private val respond: (HttpRequest) -> HttpReply) : Closeable {
    private val socket = ServerSocket(0, 10, InetAddress.getByName("127.0.0.1"))
    val url = "http://127.0.0.1:${socket.localPort}"
    private val worker = thread(isDaemon = true, name = "test-http") {
        while (!socket.isClosed) {
            try {
                socket.accept().use { client ->
                    client.soTimeout = 5000
                    val input = BufferedInputStream(client.getInputStream())
                    val path = line(input).split(" ")[1]
                    val headers = mutableMapOf<String, String>()
                    while (true) {
                        val header = line(input)
                        if (header.isEmpty()) break
                        headers[header.substringBefore(':').lowercase()] = header.substringAfter(':').trim()
                    }
                    val body = ByteArray(headers["content-length"]?.toInt() ?: 0)
                    var offset = 0
                    while (offset < body.size) {
                        val count = input.read(body, offset, body.size - offset)
                        check(count > 0)
                        offset += count
                    }
                    val reply = respond(HttpRequest(path, headers["authorization"], body.toString(Charsets.UTF_8)))
                    val bytes = reply.body.toByteArray(Charsets.UTF_8)
                    client.getOutputStream().use { output ->
                        output.write("HTTP/1.1 ${reply.status} Result\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: ${bytes.size}\r\n\r\n".toByteArray(Charsets.US_ASCII))
                        output.write(bytes)
                    }
                }
            } catch (failure: Exception) { if (!socket.isClosed) throw failure }
        }
    }
    override fun close() { socket.close(); worker.join(2000) }
    private fun line(input: BufferedInputStream): String {
        val text = StringBuilder()
        while (true) {
            val byte = input.read()
            check(byte >= 0)
            if (byte == 10) return text.toString().trimEnd('\r')
            text.append(byte.toChar())
        }
    }
}
