<p align="center">
  <img src="assets/brand/bitree.svg" width="96" alt="BITree 理枝 logo" />
</p>

<h1 align="center">BITree 理枝</h1>

<p align="center">
  面向北京理工大学的本地跨平台工具集。
</p>

<p align="center">
  <a href="https://github.com/bitoolkit/bitree/releases/latest">下载正式版</a>
  &nbsp;|&nbsp;
  <a href="https://github.com/bitoolkit/bitree/releases?q=prerelease%3Atrue">下载测试版</a>
</p>

## 功能

- **课表**：同步学校课表，也可手动添加课程。按周查看，显示当前时间，支持导出 ICS。
- **日程**：管理 DDL、活动和考试，同步考试安排、乐学和新延河课堂的 DDL 与完成状态。
- **空教室查询**：按校区、教学楼和日期查看空闲时段，也可筛选指定时段内全程空闲的教室。
- **成绩与学业**：同步全部学期成绩，查看加权平均分、绩点和学期表现。绩点采用学校公布的[本科生计算规则](https://soe.bit.edu.cn/rcpy/bk/ffa622a7030b45bdadf33415bdffa364.htm)，同一课程取最高成绩。
- **成绩试算**：手动添加课程或选择重修课程，试算累计绩点，也可倒推达到目标所需的成绩；不修改原成绩。
- **毕业学分进度**：同步学校记录的总要求与已修学分，设置分类目标，并在课程详情中调整核对分类。
- **考试安排与冲突检查**：复用日程中的考试，检查考试之间以及考试与已保存课表的时间冲突。
- **Android 小组件**：在桌面查看课程和日程，提供单列、双列两种布局。

支持浅色、深色和跟随系统。已保存的课表和日程可离线查看。教学中心会同时探测校内直连和 WebVPN，选择先响应的线路；连接中断时再尝试另一路。乐学和新延河课堂直接访问。

## 下载

前往 [正式版](https://github.com/bitoolkit/bitree/releases/latest) 或 [测试版](https://github.com/bitoolkit/bitree/releases?q=prerelease%3Atrue)，按平台选择文件：

| 平台 | 下载文件 |
| --- | --- |
| Android | APK，提供 `arm64-v8a`、`armeabi-v7a` 和 `x86_64` 三种架构 |
| Windows | x64 EXE 安装包，包含运行依赖 |
| macOS | 通用版 ZIP，解压后使用，未签名 |
| Linux | x64 tar.xz，解压后运行 `bitree` |
| iOS | arm64 IPA，需自行签名后安装 |

## 数据与日志

课表和日程保存在本机，账号密码和登录会话使用系统安全存储。学校请求直接在本地发送，不经过第三方服务器。

日志在本地保留七天。遇到问题，可在 **设置 → 导出日志** 中预览最近 100 行，或导出日志文件。文件包含构建版本和运行环境，便于排查问题。

<details>
<summary>发布构建与堆栈还原</summary>

发布时会把 Dart 调试信息移出安装包，以减小包体。CI 将这些符号文件保存为 `debug-symbols-平台-版本`，保留 90 天。它们可在对应的 Actions 构建页面下载。Android 的 APK 和 AAB 符号分别位于 `apk/`、`appbundle/` 目录。

还原错误堆栈时，先下载与日志版本、平台和架构对应的符号文件，再把堆栈保存为 `stacktrace.txt`。以下以 Android arm64 为例：

```sh
flutter symbolize --debug-info=app.android-arm64.symbols --input=stacktrace.txt
```

</details>

## 开发

模块职责、数据流和验证命令见[代码结构与数据流](docs/architecture.md)。

## LICENSE

[Unlicense](LICENSE). Made by [BIToolkit](https://github.com/bitoolkit) with ♥️
