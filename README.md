# 微信小程序开发者工具 Wine/Flatpak 兼容性验证

在 Debian/KDE Wayland 主机上，通过用户级 Wine Flatpak 验证 Windows 微信开发者
工具能否安装、启动和完成基础开发流程。测试使用独立 Wine 前缀，不影响企业微信。

## 推荐方案与固定版本

- 微信开发者工具：`2.02.2608070` Stable Build（2026-09-07）Windows x64
- 官方下载域名：`devtools.wxqcloud.qq.com.cn/WechatWebDev`
- SHA-256：`a502dead2e4fb6dcb0b5e157e1f2b9ac00c10a20f1940917112a1f8481ed5ed9`
- 应用层：`io.github.loveyu.WeChatDevToolsWine//stable-25.08`
- 共享基础包：`io.github.loveyu.Wine.Deepin//10.14deepin11-25.08`
- Wine：与企业微信一致的 Deepin Wine `10.14deepin11`，new WoW64

普通 `make install/run/status/stop` 和启动菜单默认使用 Deepin runner。基础包作为独立
Flatpak 扩展挂载到两个应用各自的 `/app/shared-wine`，只安装一份引擎、匹配的
wineserver、驱动覆盖与运行库。应用层只保存启动、宿主集成脚本和链接，开发者工具
仍使用自己的前缀、账号、项目和实例，不运行企业微信初始化脚本。

共享基础包的构建入口位于企业微信仓库的 `scripts/build-shared-wine-runtime.sh`，
可从已安装的完整企业微信包提取，也由企业微信完整构建自动生成。应用层只要求基础包
已经安装，不依赖企业微信应用本身。来源 commit 与引擎/DLL 摘要记录在基础包内
`/app/shared-wine/share/shared-wine/source.txt`。

Wine 11.17 Staging 的 `staging-*` 命令保留用于对照；历史 Wine 11.0 基线需要显式指定
`WECHAT_DEVTOOLS_RUNNER_VARIANT=baseline`。三者使用各自的数据目录，不原地降级旧前缀。
切换前先停止开发者工具，避免多个 Electron 进程树耗尽内存与交换区。

Wine 与 Staging 源码归档共享保存在 `/data/code/wine/source-cache/`，每次构建先校验
SHA-256，文件有效时不会再次下载。可用 `WINE_SOURCE_CACHE_DIR` 指向其他持久目录；
该缓存不进入 Git、Flatpak 或发布包。

仓库不提交或再分发腾讯安装包、Wine 前缀、登录数据、二维码和日志。

## 项目状态与适用范围

这是已完成真实桌面验证的兼容性项目，不是腾讯官方 Linux 客户端。仓库提供下载
校验、独立前缀、Flatpak 启动、DPI/Fcitx5 集成以及当前版本所需的本地修复；腾讯
程序始终由目标机器从官方地址下载。当前已覆盖游客项目、模拟器、编辑器、调试器、
扫码登录和登录态恢复，真实 AppID 的预览、上传及真机调试仍列在 `TODO.md`。

运行环境以 Debian 13、KDE Plasma 6 Wayland/XWayland 和 Fcitx5 为验证基准。
脚本依赖用户级 Flatpak、`bash`、`curl`、`sha256sum`、Python 3 以及构建 X11
控制辅助程序所需的 C 编译器和 Xlib 开发文件。Runner 封装与冒烟程序编译在
Freedesktop SDK 25.08 内完成，需安装其 `org.freedesktop.Sdk.Extension.mingw-w64`
扩展。不向宿主系统安装 Wine，也不依赖宿主 32 位 Wine 包。开发者工具不使用
.NET/Trident，启动环境会禁用 Wine Mono 与 Gecko 的首次安装提示。

## 使用

```bash
make check
make -C ../wecom-wine-flatpak shared-wine-runtime
make build-deepin-runner
make migrate-to-deepin  # 已安装 Staging 时复制迁移；全新环境改用 make install
make install-user-integration
make run
make status
./scripts/cli.sh --help
make prepare-sample
make stop
```

推荐执行顺序：

1. `make check` 检查脚本语法、宿主打开映射、Python 修复和二进制污染。
2. 在企业微信仓库运行 `make shared-wine-runtime`，先构建并安装共享基础包。
3. `make build-deepin-runner` 构建开发者工具应用层，引用同一基础包。
4. `make migrate-to-deepin` 停止旧实例，复制 Staging 前缀、登录态和修复备份到新的
   Deepin 目录，再由 Wine 10 更新 builtin DLL；旧前缀保持不变。目标非空时拒绝覆盖。
   全新环境使用 `make install` 下载并校验腾讯安装包，静默安装后创建启动菜单。
5. `make install-user-integration` 可单独修复或刷新启动菜单，不重装开发者工具。
6. `make run` 启动，`make status` 查看 runner、前缀、实例和日志位置。
7. `make stop` 按本项目 App ID 收拢 Deepin/Staging 残留实例，不停止企业微信。

更新开发工具版本时必须同步更新下载地址、摘要和登录/字体修复的精确匹配条件，
然后重新执行游客项目、扫码登录、冷启动和编辑保存回归。修复脚本遇到未知 ASAR
内容会中止而不是猜测修改。

安装脚本在状态目录记录已安装版本；固定版本变化后，`make install` 会在保留
同一 Wine 前缀、账号和项目数据的前提下执行覆盖升级。

Deepin 运行数据位于：

- `~/.local/share/wechat-devtools-wine-flatpak-deepin/`
- `~/.local/state/wechat-devtools-wine-flatpak-deepin/`
- `~/.cache/wechat-devtools-wine-flatpak-deepin/`

旧 Staging 数据仍位于同名 `-staging` 目录。回退时执行 `make stop`、
`make staging-run`；菜单仍默认 Deepin。

## 启动菜单

`make install` 或 `make migrate-to-deepin` 会安装“微信开发者工具（Wine）”菜单项；也可运行
`make install-user-integration` 单独刷新。桌面入口位于
`~/.local/share/applications/io.github.loveyu.WeChatDevToolsWine.desktop`，启动器位于
`~/.local/bin/wechat-devtools-wine`。图标从已经校验并安装的腾讯官方 EXE 提取，只写入
用户图标目录，不提交到仓库或打包进 Flatpak。重复点击菜单项会激活已运行的项目列表
窗口，避免并发启动第二个 Wine 实例。菜单启动器默认加载 Deepin 专用的数据、状态和
缓存目录，不能只切换 runner 后复用旧 Wine 前缀。

`2.02.2608070` 使用 Electron 36，在 Wine/DXGI 硬件合成初始化失败时会留下无标题
黑色窗口。启动脚本默认传入 `--disable-gpu-compositing` 使用稳定的软件合成路径；需要
对照硬件合成时可临时执行 `WECHAT_DEVTOOLS_GPU_COMPOSITING=hardware make run`。
停止脚本会按独立 App ID 收拢启动早期尚未写入 instance 文件的残留实例。

Deepin runner 另行默认传入 `--no-sandbox --use-angle=d3d11`：Wine 10 无法启动
Electron 36 的 Chromium 沙箱 GPU 子进程，自动回退的 SwiftShader/Vulkan 也无法初始化。
应用仍在原有 Flatpak 沙箱内运行；显式传入 `--use-angle=...` 或 `--use-gl=...` 时尊重
该选择。Staging 与历史基线保留原来的 Electron 参数。

Wine 前缀保持窗口由 KWin 管理，但关闭 Wine 额外生成的宿主窗口装饰。微信开发者工具
的 Electron 主界面及“真机调试”等辅助窗口自行绘制标题区；若再叠加系统标题栏，窗口
最大化时约 42 像素的非客户区会挤压并遮挡内容。该设置仅作用于本项目独立前缀。

## 文件与目录打开

标准 Win32、`IFileDialog` 和 `SHBrowseForFolderW` 对话框通过 XDG Desktop Portal
进入宿主选择器；`explorer.exe /select` 通过 `org.freedesktop.FileManager1.ShowItems`
定位文件。常见文档和媒体文件由宿主默认应用打开，脚本与可执行文件仍由 Wine 处理。

仓库和 Flatpak 清单不声明整个 `/data`。需要访问该目录时单独执行本机用户级授权：

```bash
flatpak override --user --filesystem=/data io.github.loveyu.WeChatDevToolsWine
```

该 override 不会进入 runner、安装包或发布产物；撤销时使用
`flatpak override --user --nofilesystem=/data io.github.loveyu.WeChatDevToolsWine`。

## 验收边界

2026-10-19 已将默认底层切换为共享 Deepin Wine `10.14deepin11`。企业微信和开发者工具
应用层加载同一个基础包，Wine 与 wineserver 的实际路径及 SHA-256 一致。Staging
前缀复制迁移后，已有账号以 `hasUser=true,isTourist=false` 恢复，真实项目的编辑器、
文件树和模拟器正常渲染；150% 缩放生效。Portal 冒烟结果为 `OpenFile=5`、`SaveFile=3`。
预览、上传、真机调试和中文输入仍需在此底层上单独回归。

同日使用现有项目和模拟器完成两轮各 120 秒的资源采样。开发者工具总 PSS 峰值约
3.4 GiB，随后回落到 2.6–2.8 GiB，自身 swap 为 0。稳定阶段 CPU 约为单核的
7%–16%；启动恢复项目时前十几秒有多核峰值，最高约 11.4 个逻辑核（测试机共
16 个）。重复点击菜单保持单实例，近期内存压力 PSI 为 0。此结果只覆盖短时启动和
项目驻留，不代表大型项目长时间编译或预览/上传的资源上限。

2026-09-10 已按腾讯官方稳定版配置从 `2.02.2608050` 覆盖升级到
`2.02.2608070`。官方安装包摘要校验、静默升级、兼容修复、150% 缩放和项目列表窗口
均通过；冷启动后主进程和渲染进程仍以 `hasUser=true,isTourist=false` 恢复账号，确认
同一 Wine 前缀中的登录态得以保留。

2026-09-09 已完成 Wine 11.17 Staging 新 runner 验证：源码与 Staging 补丁校验通过，
new WoW64 Flatpak 成功构建安装；Portal 冒烟结果为 `OpenFile=5`、`SaveFile=3`；固定版
开发者工具可静默安装，登录/游客界面在 150% 缩放（Wine 144 DPI）下完整渲染且没有
黑屏。真实扫码后日志完成动态 `main-sync`、`renderer-sync` 和 `login-complete`；重启后
以 `source=initial` 恢复 `hasUser=true,isTourist=false`，登录态持久化通过。`/data` 只
存在于本机用户级 override。游客项目和中文输入仍需在新 runner 上回归。

2026-09-01 已在 Debian 13、KDE Plasma 6、Wayland/XWayland 上完成以下验证：

- Windows x64 安装包可在独立 Wine 11.0 前缀中安装和启动；
- 游客模式可创建默认小程序，编译器、Skyline 模拟器和 Chromium DevTools 均可渲染；
- Noto CJK 字体映射可完整显示中文，Wine XIM 可使用宿主 Fcitx5 拼音；
- 启动时读取 KDE/X11 的 `Xft.dpi`，当前系统 150% 缩放会同时设置 Wine 144 DPI 和
  Electron `--force-device-scale-factor=1.5`；
- 工具内置 `codicon` 与 `vscode-iconfont-patch` 在 Wine 首次渲染时加载失败的问题已
  自动修复，工作台工具栏、资源树和调试器图标均能正常显示；
- 通知中心扫码可登录真实微信账号，登录状态可同步到项目窗口并持久化，冷启动后无需
  再次扫码；
- 编辑器可输入中文并保存，CLI 可在运行实例内执行，不会误停同一 runner 中的企业微信；
- GPU、renderer、network、Node、TypeScript 等子进程可持续运行。

日志中仍会出现 Wine 网络服务发现和 TCP `10051` 错误，但插件下载、编译和模拟器
均未受影响。真实 AppID 的预览/上传和真机调试仍需要具体项目或设备，单独记录在
`TODO.md`。

## 缩放与内置图标

缩放倍率在每次进程启动时自动读取。检测顺序是 `Xft.dpi / 96`、KScreen 主输出倍率、
最后回退到 1；可用下面的方式临时覆盖：

```bash
WECHAT_DEVTOOLS_SCALE_FACTOR=1.25 make run
# 两个开发工具共用的覆盖变量也可使用 DEVTOOLS_SCALE_FACTOR
```

Wine/XWayland 使用进程级全局 DPI，因此修改 KDE 缩放后需要重启开发工具；当前不承诺
窗口跨不同缩放倍率显示器时动态切换。

`scripts/repair-codicon-font.py` 从已经校验的官方 `app.asar` 提取工作台 `codicon`，并从
官方 `static/app.css` 的 data URI 提取资源树使用的 `vscode-iconfont-patch`，写入当前项目
Wine 前缀后对两处 CSS 做等长字体源替换。原 CSS 条目备份在
`~/.local/state/wechat-devtools-wine-flatpak/repairs/codicon/`。字体注册也只写入该独立
Wine 前缀，不安装宿主字体、不下载第三方字体，后续工具升级会按新版 ASAR 再次校验和
修复。

## 扫码登录兼容性

Windows Electron 版本在 Wine 下会遇到两层登录 IPC 问题：通知中心二维码换票成功后，
成功事件可能无法回到项目渲染进程；即使事件到达，渲染进程等待主进程登录 RPC 时，
主进程又会同步回写渲染进程的全局状态，从而形成循环等待。

启动修复脚本会对固定版本 `app.asar` 中的二维码服务和两处登录 action 做等长替换：

- 主进程在二维码换票完成后延迟写入登录服务，再向 GUI 发出成功事件；
- 渲染进程的登录 action 不再同步等待主进程 RPC，并为可选教育信息传入空对象；
- 二维码弹层收到延迟成功事件后按原流程关闭；
- 每个 ASAR 条目长度和偏移保持不变，原条目保存在
  `~/.local/state/wechat-devtools-wine-flatpak/repairs/login-ipc/`。

补丁只匹配当前固定版本的精确模块内容；升级后若模块不匹配会中止启动并报告错误，避免
静默修改未知代码。登录凭据仍只保存在项目的独立 Wine 前缀中，不写入宿主配置目录。

## 状态检查、恢复与公开边界

`make status` 会给出当前 Flatpak instance、日志和前缀位置。启动异常时先执行
`./scripts/stop.sh`，确认本项目实例退出后再运行 `make run`；字体或登录补丁的原始
条目备份位于状态目录，可结合状态输出定位，但不要把整个 Wine 前缀作为故障附件。

公开仓库和 Release 不应包含腾讯安装包、解包后的 `app.asar`、字体提取结果、Wine
前缀、登录凭据、二维码、真实 AppID、业务项目或运行日志。仓库中的最小小程序 fixture
只用于无敏感数据的渲染与编辑验证。腾讯软件及其内置资源仍受各自许可条款约束；公开
本兼容脚本不代表获得重新分发腾讯二进制的授权。
