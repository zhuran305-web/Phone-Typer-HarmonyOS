# 文台 Phone-Typer（鸿蒙手机端）

「文台」是一款 HarmonyOS 手机应用，配合电脑端 [Phone-Typer Server](https://github.com/zhuran305-web/Phone-Typer/releases) 使用：在手机上打字，文字会实时同步键入到电脑当前光标位置。适合在电脑上打字不便（如外接键盘不在手边、输入法切换麻烦）的场景，把手机变成电脑的「无线键盘」。

## 功能特性

- **实时同步键入**：手机输入框内容变化后防抖同步到电脑，支持中文、换行、退格删除
- **一次性发送**：整段文字写完后一键发送，全部键入到电脑并清空输入框
- **扫码配对**：扫描电脑端展示的二维码，自动填入 IP、端口和 PIN 码
- **剪贴板推送**：电脑端可把剪贴板内容推送到手机，一键复制到手机剪贴板
- **断线自动重连**：连接断开后每 3 秒自动重连
- **PIN 码校验**：通过配对 PIN 码防止局域网内误连

## 使用方法

1. 下载并运行电脑端服务：[Phone-Typer Releases](https://github.com/zhuran305-web/Phone-Typer/releases)
2. 确保手机与电脑处于**同一局域网**，且路由器未开启「AP 隔离」
3. 电脑端放行防火墙入站端口（默认 HTTP `8766`、WebSocket `8767`）
4. 手机端扫码或手动填写电脑 IP、端口、PIN 码（默认 `1234`），连接后即可开始使用

## 构建

1. 使用 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) 打开本工程
2. 工程未内置签名配置，请通过 `File > Project Structure > Signing Configs` 配置自己的签名（Debug 签名可直接自动生成）
3. 连接设备后点击 Run 安装运行

- 编译 SDK：HarmonyOS 6.1.1(24)
- 最低兼容：HarmonyOS 6.1.1(24)
- 支持设备：phone / tablet

## 项目结构

```
entry/src/main/ets/
├── common/
│   ├── PtConstants.ets   # 常量定义（端口、PIN、防抖时间等）
│   ├── PtQrParser.ets    # 配对二维码解析
│   └── PtStore.ets       # 设置项持久化（Preferences）
├── net/
│   ├── PtApi.ets         # HTTP 配置接口（获取 WS 端口 / 版本）
│   └── PtWsClient.ets    # WebSocket 客户端（含自动重连）
├── pages/
│   ├── Index.ets         # 主页面：输入、发送、连接状态、剪贴板卡片
│   └── ScanPage.ets      # 扫码配对页
├── entryability/         # 应用入口
└── entrybackupability/   # 备份扩展
```

电脑端服务的对接协议（HTTP / WebSocket 帧格式、键入差量算法、二维码格式等）详见 [`电脑端对接需求.md`](./电脑端对接需求.md)。

## 许可证

[MIT](./LICENSE)
