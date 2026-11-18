// [INPUT]: 使用 WinUI 生命周期和 MainWindow。
// [OUTPUT]: 启动并保持原生窗口。
// [POS]: Windows 应用入口。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
using Microsoft.UI.Xaml;
namespace TaskNotes;
public sealed class App : Application {
    Window? window;
    public App() { Resources.MergedDictionaries.Add(new Microsoft.UI.Xaml.Controls.XamlControlsResources()); }
    protected override void OnLaunched(LaunchActivatedEventArgs args) { window = new MainWindow(); window.Activate(); }
}
