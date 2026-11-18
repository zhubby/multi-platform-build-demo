# Core/
> L2 | Parent: ../AGENTS.md
Core.csproj：net8.0 无界面库；开启 NuGet 锁文件。
packages.lock.json：核心项目依赖图；无第三方包。
Domain.cs：纯文本约束、协议记录、URL 规范化与原子缓存。
Session.cs：Bearer 请求与完整快照交换；失败撤销写权限；不确定提交需显式核对。
[PROTOCOL]: Update this header on change, then check AGENTS.md
