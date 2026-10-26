<p align="center">
  <img src="assets/brand/bitree.svg" width="160" alt="BITree 理枝 logo" />
</p>

<h1 align="center">BITree 理枝</h1>

<p align="center">
  面向北京理工大学的本地跨平台工具集。
</p>

<p align="center">
  <a href="https://github.com/so1ve/bitree/releases/latest">下载正式版</a>
  &nbsp;|&nbsp;
  <a href="https://github.com/so1ve/bitree/releases/tag/dev">下载测试版</a>
</p>

> [!WARNING]
>
> 数据保存在本机，登录凭据使用系统安全存储。账号密码只用于学校认证，请求直接发往学校，没有中转服务器。

## 发布构建与日志

发布构建会分离 Dart 调试信息，减少安装包中的代码和元数据。CI 将符号文件单独保存为 `debug-symbols-平台-版本`，保留 90 天，不放进安装包或预发布下载列表。Android 的 APK 和 AAB 符号分别放在 `apk/`、`appbundle/` 下。

导出的日志包含构建版本和运行环境。还原 Dart 堆栈时，从对应构建下载同一平台、架构的符号文件，将堆栈保存为 `stacktrace.txt`，再运行：

```sh
flutter symbolize --debug-info=app.android-arm64.symbols --input=stacktrace.txt
```

## LICENSE

[Unlicense](LICENSE). Made with ❤️ by [Ray](https://github.com/so1ve)
