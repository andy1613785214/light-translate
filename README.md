# 轻译 · LightTranslate

一个轻巧的原生 macOS 中英翻译工具。划选文字，按快捷键，读懂它。

[下载安装](https://github.com/andy1613785214/light-translate/releases/latest) · [安装与更新](docs/INSTALL.md) · [发布维护](docs/RELEASING.md)

等待状态布局示意：

![正在翻译](docs/loading.png)

- **原生 Liquid Glass**：macOS 26 使用苹果玻璃效果，macOS 14/15 使用系统磨砂材质。支持深色模式及系统辅助显示设置。
- **极简浮窗**：默认在当前屏幕右上角。等待时只显示“正在翻译”；返回结果后展开。
- **划句翻译，划词解释**：句子显示译文，原文和词汇默认折叠；单个英文单词直接展开音标、词性、释义、搭配与双语例句，基础词也会解释。
- **自带更新入口**：菜单栏或“…”菜单中检查更新；更新包和更新信息使用 Ed25519 签名验证。自动检查，安装需用户确认。

## 安装

支持 **Apple Silicon、macOS 14 或以上**。下载 Release 中的 `.dmg`，打开后将“轻译”拖入 Applications，再从应用程序目录启动。也提供 ZIP。

当前版本使用本地 **ad-hoc 签名，尚未获得 Developer ID 签名及苹果公证**。macOS 可能阻止网络下载后的首次启动。有关当前分发限制与升级方式，见[安装说明](docs/INSTALL.md)。

## 首次使用

1. 在“设置 → 翻译服务”中选择服务，填写 API 地址、模型和密钥，保存。
2. 在“设置 → 偏好”中打开辅助功能授权，为安装到应用程序目录的“轻译”启用权限。
3. 在其他应用划选文本，按 **⌥ Space**。可录制自己的快捷键；已有配置会保留。

云端兼容 Chat Completions；预设包括 Gemini、DeepSeek，以及 Qwen MT + 通用词解模型。API 服务、账户权限、额度和模型质量由所配置服务决定。Qwen MT 使用两个请求，词解失败时保留译文。单次上限 3,000 字符。

本地保留 Qwen3 0.6B / 1.7B 与独立 Ollama 服务，仅在手动选择本地模式后启动，不自动下载模型。小模型的详细词解质量有限，本地质量调优目前暂停。

## 数据与隐私

API 密钥按服务地址保存在 **macOS Keychain**；配置保存在本机 UserDefaults。密钥和个人配置不嵌入应用、不随源码或 Release 上传。默认不保存翻译历史或正文日志，最多 50 条会话内缓存，退出清空。

云端翻译将所提交文本发送至用户配置的 API；本地模式只使用本机服务。取词优先读取辅助功能选区，必要时复制并恢复剪贴板，不把旧剪贴板当作新选区。更新检查只访问公开发布地址，不携带翻译文本或 API 密钥。

美式音标优先来自内置词表，未收录的词可能使用模型音标；释义、词性和例句由模型生成，可能出错。缺失内容明确显示不可用。

## 构建

需要 macOS 26 SDK、Swift 6 或以上。可使用支持该 SDK 的 Command Line Tools，运行目标仍为 macOS 14。

```sh
Scripts/test.sh
Scripts/build-app.sh
Scripts/package-release.sh
```

Sparkle 2.10.0 官方二进制依赖由 SwiftPM 下载并校验 SHA-256。打包工具为固定版本 `ds_store` 和 `mac_alias`。生成的应用、安装包、私有评估与缓存均被 `.gitignore` 排除。

`Scripts/audit-release.py --source --bundle dist/轻译.app` 检查可发布文件、凭据模式、用户配置与个人构建路径。发布脚本再次检查 Git 暂存文件的白名单。

自动化检查包括 36 项核心场景、5 项真实本机 HTTP 场景；网络模拟只使用测试凭据。`--smoke-loading` 检查等待小窗到结果浮窗的布局转换。真实云端语言质量与跨应用兼容性仍需结合所用服务和应用验证。

## 边界

首版不包含 OCR、扫描 PDF、全文文档翻译、朗读、生词本、同步或 App Store 分发。部分应用无法读取选区，请使用手动粘贴。单词模式目前识别单个英文词、连字符词、缩写及 C++ 等单词形式；中文输入走中译英流程。

## 依赖与来源

- [Apple NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [Sparkle 更新框架](https://sparkle-project.org/documentation/)
- [IPA 词表及许可证](Sources/TranslationCore/Resources/ATTRIBUTION.txt)
- 云端预设接口依据：[Gemini](https://ai.google.dev/gemini-api/docs/openai)、[DeepSeek](https://api-docs.deepseek.com/guides/json_mode/)、[Qwen MT](https://help.aliyun.com/zh/model-studio/machine-translation)。模型名可在设置中修改。
