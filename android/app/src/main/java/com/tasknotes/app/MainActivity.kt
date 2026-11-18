/**
 * [INPUT]: 依赖 AppState 的连接、快照与草稿状态，以及 Compose 系统控件。
 * [OUTPUT]: 提供中文任务、笔记、搜索、编辑与连接设置界面。
 * [POS]: Android 原生界面入口；进程内共享状态支持 Activity 重建，不持久化令牌。
 * [PROTOCOL]: Update this header on change, then check AGENTS.md
 */
package com.tasknotes.app

import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

class MainActivity : ComponentActivity() {
    companion object { private var session: AppState? = null }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val state = session ?: AppState(applicationContext).also { session = it }
        setContent {
            val dark = isSystemInDarkTheme()
            val context = LocalContext.current
            val colors = if (Build.VERSION.SDK_INT >= 31) {
                if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
            } else if (dark) darkColorScheme() else lightColorScheme()
            MaterialTheme(colorScheme = colors) { TaskNotesScreen(state) }
        }
    }
    override fun onResume() {
        super.onResume()
        session?.refresh()
    }
}

@Composable
private fun TaskNotesScreen(state: AppState) {
    var tab by remember { mutableIntStateOf(0) }
    var search by remember { mutableStateOf("") }
    var filter by remember { mutableIntStateOf(0) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                NavigationBarItem(selected = tab == 0, onClick = { tab = 0 }, icon = { Text("✓") }, label = { Text("任务") })
                NavigationBarItem(selected = tab == 1, onClick = { tab = 1 }, icon = { Text("✎") }, label = { Text("笔记") })
            }
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("TaskNotes", Modifier.weight(1f), style = MaterialTheme.typography.headlineSmall)
                TextButton(onClick = { state.settingsVisible = true }, enabled = !state.busy) { Text("连接设置") }
                TextButton(onClick = state::refresh, enabled = !state.busy) { Text("刷新") }
            }
            if (state.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Surface(color = if (state.verified) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.errorContainer, shape = MaterialTheme.shapes.medium) {
                Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(if (state.verified) "已连接" else "只读模式", style = MaterialTheme.typography.labelLarge)
                    Text(state.message, style = MaterialTheme.typography.bodySmall)
                    Text("缓存时间：${state.snapshot?.refreshedAt ?: "尚无缓存"}", style = MaterialTheme.typography.bodySmall)
                }
            }
            OutlinedTextField(value = search, onValueChange = { search = it }, label = { Text(if (tab == 0) "搜索任务标题" else "搜索笔记标题和正文") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            if (tab == 0) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("全部", "未完成", "已完成").forEachIndexed { index, label ->
                    FilterChip(selected = filter == index, onClick = { filter = index }, label = { Text(label) })
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { state.create(if (tab == 0) "tasks" else "notes") }, enabled = state.writable) { Text(if (state.draft != null) "继续草稿" else if (tab == 0) "新建任务" else "新建笔记") }
                if (state.draft != null && !state.writable) OutlinedButton(onClick = { state.editorVisible = true }) { Text("查看草稿") }
            }
            val tasks = state.snapshot?.tasks.orEmpty().filter {
                it.title.contains(search, ignoreCase = true) && (filter == 0 || (filter == 1 && !it.completed) || (filter == 2 && it.completed))
            }
            val notes = state.snapshot?.notes.orEmpty().filter { it.title.contains(search, ignoreCase = true) || it.body.contains(search, ignoreCase = true) }
            val empty = if (tab == 0) tasks.isEmpty() else notes.isEmpty()
            if (empty) {
                Column(Modifier.fillMaxWidth().weight(1f), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(if (search.isNotBlank() || filter != 0 && tab == 0) "没有符合条件的记录" else if (tab == 0) "还没有任务" else "还没有笔记", style = MaterialTheme.typography.titleMedium)
                    Text(if (state.writable) "点击上方新建按钮开始记录。" else "连接服务后刷新，即可创建记录。", style = MaterialTheme.typography.bodyMedium)
                    TextButton(onClick = if (state.verified) ({ search = ""; filter = 0 }) else ({ state.settingsVisible = true })) { Text(if (state.verified) "清除筛选" else "配置连接") }
                }
            } else {
                LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(bottom = 16.dp)) {
                    if (tab == 0) items(tasks, key = { it.id }) { task ->
                        OutlinedCard(Modifier.fillMaxWidth().clickable { state.edit(task) }) {
                            Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(if (task.completed) "☑" else "☐", style = MaterialTheme.typography.titleLarge)
                                Spacer(Modifier.width(12.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(task.title, style = MaterialTheme.typography.titleMedium, textDecoration = if (task.completed) TextDecoration.LineThrough else null)
                                    Text(if (task.completed) "已完成 · 点击查看" else "未完成 · 点击编辑", style = MaterialTheme.typography.bodySmall)
                                }
                            }
                        }
                    }
                    if (tab == 1) items(notes, key = { it.id }) { note ->
                        OutlinedCard(Modifier.fillMaxWidth().clickable { state.edit(note) }) {
                            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(note.title, style = MaterialTheme.typography.titleMedium)
                                Text(note.body.ifEmpty { "无正文" }, maxLines = 3, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
            }
        }
    }
    if (state.settingsVisible) ConnectionDialog(state)
    if (state.editorVisible && state.draft != null) EditorDialog(state)
}

@Composable
private fun ConnectionDialog(state: AppState) {
    var address by remember { mutableStateOf(state.url) }
    var token by remember { mutableStateOf(state.token) }
    var error by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = { if (!state.busy) state.settingsVisible = false },
        title = { Text("连接设置") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("填写服务根地址。令牌只保留在进程内存，应用重启后须重新输入。")
                OutlinedTextField(value = address, onValueChange = { address = it }, enabled = !state.busy, label = { Text("服务地址，不含 /api/v1") }, placeholder = { Text("http://192.168.1.10:8080") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri), singleLine = true)
                OutlinedTextField(value = token, onValueChange = { token = it }, enabled = !state.busy, label = { Text("访问令牌") }, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), singleLine = true)
                if (error.isNotEmpty()) Text(error, color = MaterialTheme.colorScheme.error)
                Text("内网开发可用 HTTP。切换地址会读取该服务的独立缓存。", style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = { Button(onClick = { error = state.configure(address, token).orEmpty() }, enabled = !state.busy) { Text("连接并刷新") } },
        dismissButton = { TextButton(onClick = { state.settingsVisible = false }, enabled = !state.busy) { Text("关闭") } }
    )
}

@Composable
private fun EditorDialog(state: AppState) {
    val draft = state.draft ?: return
    var confirmDelete by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    val stale = draft.isStale(state.snapshot)
    Dialog(onDismissRequest = { if (!state.busy) state.editorVisible = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize().systemBarsPadding(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.fillMaxSize().imePadding().padding(16.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (draft.kind == "tasks") "任务详情" else "笔记详情", Modifier.weight(1f), style = MaterialTheme.typography.headlineSmall)
                    TextButton(onClick = { state.editorVisible = false }, enabled = !state.busy) { Text("暂存并关闭") }
                }
                if (state.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                Text(state.message, color = if (state.verified) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error)
                if (draft.uncertain) {
                    Text("上次写入的结果不确定。先刷新并检查列表；若记录已存在，请丢弃此草稿并从列表打开。", color = MaterialTheme.colorScheme.error)
                    OutlinedButton(onClick = state::confirmWriteOutcome, enabled = state.writable) { Text("已核对结果，继续编辑") }
                }
                if (draft.deleted) Text("此记录已删除。刷新后核对列表，再丢弃草稿。", color = MaterialTheme.colorScheme.error)
                if (stale && !draft.deleted) {
                    Text("其他设备已修改或删除此记录。请先核对最新内容。草稿不会自动覆盖更新。", color = MaterialTheme.colorScheme.error)
                    OutlinedButton(onClick = state::reloadDraft, enabled = state.writable) { Text("载入最新内容并替换草稿") }
                }
                if (!state.verified) OutlinedButton(onClick = state::refresh, enabled = !state.busy) { Text("刷新连接") }
                OutlinedTextField(value = draft.title, onValueChange = { state.update(draft.copy(title = it)) }, label = { Text("标题") }, enabled = state.writable && !draft.deleted && !draft.uncertain, supportingText = { Text("标题须包含 1–200 个字符。") }, modifier = Modifier.fillMaxWidth())
                if (draft.kind == "tasks") Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = draft.completed, onCheckedChange = { state.update(draft.copy(completed = it)) }, enabled = state.writable && !draft.deleted && !draft.uncertain)
                    Text("已完成")
                } else OutlinedTextField(value = draft.body, onValueChange = { state.update(draft.copy(body = it)) }, label = { Text("正文") }, enabled = state.writable && !draft.deleted && !draft.uncertain, minLines = 8, modifier = Modifier.fillMaxWidth(), supportingText = { Text("正文最多 1 MiB，支持中文和 emoji。") })
                Button(onClick = state::save, enabled = state.writable && draft.canSubmit && !stale, modifier = Modifier.fillMaxWidth()) { Text("保存并刷新") }
                if (draft.id != null) OutlinedButton(onClick = { confirmDelete = true }, enabled = state.writable && !stale && !draft.deleted && !draft.uncertain, modifier = Modifier.fillMaxWidth()) { Text("删除记录") }
                TextButton(onClick = { confirmDiscard = true }, enabled = !state.busy, modifier = Modifier.fillMaxWidth()) { Text("丢弃草稿并关闭") }
            }
        }
    }
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, title = { Text("删除记录？") }, text = { Text("此操作会从服务端删除记录。") }, confirmButton = { TextButton(onClick = { confirmDelete = false; state.delete() }) { Text("删除") } }, dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("取消") } })
    if (confirmDiscard) AlertDialog(onDismissRequest = { confirmDiscard = false }, title = { Text("丢弃草稿？") }, text = { Text("尚未保存的编辑将被清除。") }, confirmButton = { TextButton(onClick = { confirmDiscard = false; state.discard() }) { Text("丢弃") } }, dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text("取消") } })
}
