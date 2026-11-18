// [INPUT]: 使用 WinRT 与 WinUI DispatcherQueue。
// [OUTPUT]: 启动 STA 原生消息循环与 UI 同步上下文。
// [POS]: 纯 C# WinUI 入口，不需要 XAML 代码生成。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
namespace TaskNotes;
public static class Program {
    [STAThread]
    public static void Main(string[] args) {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(p => {
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            _ = new App();
        });
    }
}
