# Wine Portal 补丁

本目录复用 `wecom-wine-flatpak` 中已在 KDE Portal 验证的通用 Wine 补丁，来源基线为
`a9eded93b2ef52f150c162c801abe6e5847c3bd3`。仅保留微信开发者工具需要的部分：

- `comdlg32` 的 Win32 与 `IFileDialog` 打开、保存和文件夹选择；
- Document Portal 长路径、事件回调和结果视图兼容；
- `SHBrowseForFolderW` 的 Portal 路由；
- `explorer.exe /select` 到宿主文件管理器的转发。

未引入企业微信专用的 RichEdit、剪贴板和图片粘贴补丁。`0017` 只将自定义 URI
scheme 改为 `wechat-devtools-select:`；宿主路径转换由 `scripts/wechat-devtools-host-open.sh` 实现。
升级 Wine 时必须按顺序执行 dry-run，并重新运行 Portal smoke test。
