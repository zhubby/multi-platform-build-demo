// [INPUT]: 使用 WinUI 原生控件与 Core 会话。
// [OUTPUT]: 提供任务笔记编辑、筛选、连接和只读缓存界面。
// [POS]: 唯一业务窗口；网络刷新不改编辑草稿。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using TaskNotes.Core;
using System.Text;
namespace TaskNotes;
public sealed class MainWindow : Window {
    readonly TextBox address = new() { Header = "服务地址", MinWidth = 260 };
    readonly PasswordBox token = new() { Header = "令牌（仅内存）", MinWidth = 180 };
    readonly ComboBox kind = new() { ItemsSource = new[] { "任务", "笔记" }, SelectedIndex = 0, MinWidth = 90 };
    readonly ComboBox filter = new() { ItemsSource = new[] { "全部", "未完成", "已完成" }, SelectedIndex = 0, MinWidth = 100 };
    readonly TextBox search = new() { PlaceholderText = "搜索标题和笔记正文", MinWidth = 250 };
    readonly ListView list = new() { SelectionMode = ListViewSelectionMode.Single };
    readonly TextBox title = new() { Header = "标题" };
    readonly TextBox body = new() { Header = "正文", AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 260 };
    readonly CheckBox completed = new() { Content = "已完成" };
    readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap };
    readonly Button acknowledge = new() { Content = "已核对写入结果" };
    readonly Button save = new() { Content = "保存" }, delete = new() { Content = "删除所选" };
    readonly string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TaskNotes");
    Session session;
    bool busy;
    (string Id, long Revision)? selected;
    List<(string Id, long Revision)> visible = [];
    bool Notes => kind.SelectedIndex == 1;
    public MainWindow() {
        Title = "TaskNotes";
        Directory.CreateDirectory(root);
        string url;
        try { url = Domain.NormalizeUrl(File.ReadAllText(Path.Combine(root, "address.txt"))); } catch { url = "http://127.0.0.1:8080"; }
        address.Text = url; session = new Session(url, "", Path.Combine(root, "cache"));
        var outer = new Grid { Padding = new Thickness(20), RowSpacing = 12 };
        outer.RowDefinitions.Add(new() { Height = GridLength.Auto }); outer.RowDefinitions.Add(new() { Height = GridLength.Auto }); outer.RowDefinitions.Add(new() { Height = new GridLength(1, GridUnitType.Star) }); outer.RowDefinitions.Add(new() { Height = GridLength.Auto });
        var connection = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        var connect = new Button { Content = "连接 / 应用地址", VerticalAlignment = VerticalAlignment.Bottom };
        var refresh = new Button { Content = "刷新", VerticalAlignment = VerticalAlignment.Bottom };
        connection.Children.Add(address); connection.Children.Add(token); connection.Children.Add(connect); connection.Children.Add(refresh); outer.Children.Add(connection);
        var toolbar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 }; var create = new Button { Content = "新建" };
        toolbar.Children.Add(kind); toolbar.Children.Add(filter); toolbar.Children.Add(search); toolbar.Children.Add(create); Grid.SetRow(toolbar, 1); outer.Children.Add(toolbar);
        var split = new Grid { ColumnSpacing = 20 }; split.ColumnDefinitions.Add(new() { Width = new GridLength(2, GridUnitType.Star) }); split.ColumnDefinitions.Add(new() { Width = new GridLength(3, GridUnitType.Star) }); split.Children.Add(list);
        var editor = new StackPanel { Spacing = 12 }; editor.Children.Add(title); editor.Children.Add(completed); editor.Children.Add(body);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 }; actions.Children.Add(save); actions.Children.Add(delete); actions.Children.Add(acknowledge); editor.Children.Add(actions);
        var scroll = new ScrollViewer { Content = editor }; Grid.SetColumn(scroll, 1); split.Children.Add(scroll); Grid.SetRow(split, 2); outer.Children.Add(split); Grid.SetRow(status, 3); outer.Children.Add(status); Content = outer;
        connect.Click += async (_, _) => await ApplyAddress(); refresh.Click += async (_, _) => await Refresh();
        acknowledge.Click += (_, _) => { if (session.Online) { session.AcknowledgeWrite(); status.Text = "结果已核对。可继续编辑保留的草稿。"; Paint(); } };
        create.Click += (_, _) => { if (!busy) Clear(); }; save.Click += async (_, _) => await Save(); delete.Click += async (_, _) => await Delete();
        kind.SelectionChanged += (_, _) => Clear(); filter.SelectionChanged += (_, _) => Paint(); search.TextChanged += (_, _) => Paint();
        list.SelectionChanged += (_, _) => Select();
        address.TextChanged += (_, _) => { session.Online = false; save.IsEnabled = false; delete.IsEnabled = false; status.Text = "地址已编辑。连接后显示该服务快照。"; };
        Activated += async (_, e) => { if (e.WindowActivationState != WindowActivationState.Deactivated && !busy) await Refresh(); };
        Closed += (_, _) => session.Dispose();
        status.Text = "尚未验证连接。缓存只读；输入令牌后连接。"; Paint();
    }
    bool CheckAddress() {
        if (Domain.MatchesAddress(address.Text, session.Url)) return true;
        session.Online = false; save.IsEnabled = delete.IsEnabled = acknowledge.IsEnabled = false;
        status.Text = "地址已编辑。请先点击连接应用新地址，再刷新或写入。"; return false;
    }
    async Task Refresh() { if (CheckAddress()) await Run(session.Refresh); }
    async Task ApplyAddress() {
        if (busy) return;
        try {
            var url = Domain.NormalizeUrl(address.Text);
            File.WriteAllText(Path.Combine(root, "address.txt"), url);
            if (url != session.Url) { session.Dispose(); session = new Session(url, token.Password, Path.Combine(root, "cache")); Clear(); }
            else session.SetToken(token.Password);
            await Run(session.Refresh);
        } catch (Exception e) { status.Text = e.Message; }
    }
    async Task Run(Func<Task> action, bool clearAfterSuccess = false) {
        if (busy) return; busy = true; save.IsEnabled = false; delete.IsEnabled = false;
        title.IsEnabled = body.IsEnabled = completed.IsEnabled = kind.IsEnabled = address.IsEnabled = list.IsEnabled = false;
        try { await action(); if (clearAfterSuccess) Clear(); status.Text = $"已连接 · 缓存时间：{session.Snapshot.RefreshedAt}" + (session.PendingWriteReview ? " · 上次写入结果不确定。请检查列表，再点击已核对写入结果。" : ""); }
        catch (Exception e) { session.Online = false; status.Text = $"只读 · {e.Message} · 缓存时间：{session.Snapshot.RefreshedAt}" + (session.PendingWriteReview ? " · 写入结果不确定；请刷新后检查列表，避免重复创建。" : ""); }
        finally { busy = false; title.IsEnabled = body.IsEnabled = completed.IsEnabled = kind.IsEnabled = address.IsEnabled = list.IsEnabled = true; Paint(); }
    }
    void Paint() {
        var items = new List<string>(); visible = [];
        var query = search.Text.Trim();
        if (Notes) foreach (var note in session.Snapshot.Notes) {
            if (!(note.Title + " " + note.Body).Contains(query, StringComparison.OrdinalIgnoreCase)) continue;
            items.Add(note.Title); visible.Add((note.Id, note.Revision));
        } else foreach (var task in session.Snapshot.Tasks) {
            if (!task.Title.Contains(query, StringComparison.OrdinalIgnoreCase) || filter.SelectedIndex == 1 && task.Completed || filter.SelectedIndex == 2 && !task.Completed) continue;
            items.Add($"{(task.Completed ? "☑" : "☐")}  {task.Title}"); visible.Add((task.Id, task.Revision));
        }
        if (items.Count == 0) items.Add("暂无匹配记录。点击“新建”开始。");
        list.ItemsSource = items; body.Visibility = Notes ? Visibility.Visible : Visibility.Collapsed; completed.Visibility = Notes ? Visibility.Collapsed : Visibility.Visible; filter.Visibility = Notes ? Visibility.Collapsed : Visibility.Visible;
        title.IsReadOnly = body.IsReadOnly = !session.Online; completed.IsEnabled = session.Online && !busy;
        save.IsEnabled = session.Online && !busy && !session.PendingWriteReview; delete.IsEnabled = save.IsEnabled && selected.HasValue;
        acknowledge.IsEnabled = session.Online && !busy && session.PendingWriteReview;
    }
    void Clear() { selected = null; title.Text = ""; body.Text = ""; completed.IsChecked = false; Paint(); }
    void Select() {
        int index = list.SelectedIndex; if (index < 0 || index >= visible.Count) return;
        selected = visible[index];
        if (Notes) { var item = session.Snapshot.Notes.First(v => v.Id == selected.Value.Id); title.Text = item.Title; body.Text = item.Body; }
        else { var item = session.Snapshot.Tasks.First(v => v.Id == selected.Value.Id); title.Text = item.Title; completed.IsChecked = item.Completed; }
        delete.IsEnabled = session.Online && !busy && !session.PendingWriteReview;
    }
    async Task Save() {
        if (!CheckAddress()) return;
        if (!Domain.ValidTitle(title.Text) || Notes && Encoding.UTF8.GetByteCount(body.Text) > 1024 * 1024) { status.Text = "标题需为 1–200 字符，正文最多 1 MiB。"; return; }
        var value = new Dictionary<string, object> { ["title"] = title.Text.Trim() };
        if (Notes) value["body"] = body.Text; else value["completed"] = completed.IsChecked == true;
        var path = Notes ? "notes" : "tasks"; var method = "POST";
        if (selected is { } item) { path += "/" + item.Id; value["revision"] = item.Revision; method = "PUT"; }
        await Run(() => session.Write(method, path, value), true);
    }
    async Task Delete() {
        if (!CheckAddress()) return;
        if (selected is not { } item) return;
        await Run(() => session.Write("DELETE", $"{(Notes ? "notes" : "tasks")}/{item.Id}?revision={item.Revision}"), true);
    }
}
