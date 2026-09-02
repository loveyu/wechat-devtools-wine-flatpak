# 微信小程序开发者工具 Wine/Flatpak 兼容性验证

在 Debian/KDE Wayland 主机上，通过用户级 Wine Flatpak 验证 Windows 微信开发者
工具能否安装、启动和完成基础开发流程。测试使用独立 Wine 前缀，不影响企业微信。

## 固定版本

- 微信开发者工具：`2.02.2608050` Windows x64
- 官方下载域名：`dldir1.qq.com/WechatWebDev`
- SHA-256：`34082f779984e1f5654f7e99f7fbaa7402af0e4c3c9574d8441778429069daab`
- Wine runner：`io.github.huzhiyu.WeComWine//stable-25.08`（Wine 11.0）

仓库不提交或再分发腾讯安装包、Wine 前缀、登录数据、二维码和日志。

## 项目状态与适用范围

这是已完成真实桌面验证的兼容性项目，不是腾讯官方 Linux 客户端。仓库提供下载
校验、独立前缀、Flatpak 启动、DPI/Fcitx5 集成以及当前版本所需的本地修复；腾讯
程序始终由目标机器从官方地址下载。当前已覆盖游客项目、模拟器、编辑器、调试器、
扫码登录和登录态恢复，真实 AppID 的预览、上传及真机调试仍列在 `TODO.md`。

运行环境以 Debian 13、KDE Plasma 6 Wayland/XWayland 和 Fcitx5 为验证基准。
脚本依赖用户级 Flatpak、`bash`、`curl`、`sha256sum`、Python 3 以及构建 X11
控制辅助程序所需的 C 编译器和 Xlib 开发文件。运行时不会向宿主系统安装 Wine，
但要求已安装本项目使用的 `io.github.huzhiyu.WeComWine//stable-25.08` runner。

## 使用

```bash
make check
make download
make install
make run
make status
./scripts/stop.sh
./scripts/cli.sh --help
./scripts/prepare-sample.sh
```

推荐执行顺序：

1. `make check` 检查脚本语法、Python 修复脚本和二进制污染。
2. `make download` 从腾讯官方地址下载并核对固定 SHA-256。
3. `make install` 初始化独立 Wine 前缀并安装开发工具。
4. `make run` 启动，`make status` 查看实例、进程和日志位置。
5. `./scripts/stop.sh` 只停止本项目记录的 Flatpak 实例，不按模糊进程名清理。

更新开发工具版本时必须同步更新下载地址、摘要和登录/字体修复的精确匹配条件，
然后重新执行游客项目、扫码登录、冷启动和编辑保存回归。修复脚本遇到未知 ASAR
内容会中止而不是猜测修改。

运行数据位于：

- `~/.local/share/wechat-devtools-wine-flatpak/`
- `~/.local/state/wechat-devtools-wine-flatpak/`
- `~/.cache/wechat-devtools-wine-flatpak/`

## 验收边界

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
