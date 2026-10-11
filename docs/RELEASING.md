# 发布维护

更新签名私钥保存在维护者本机 Keychain，账户名 `com.local.LightTranslate.sparkle`。仓库和应用中只有公开 Ed25519 验证公钥。不要将 API 密钥、签名私钥、证书导出文件或本机 UserDefaults 上传到 GitHub。

## 发新版

1. 修改 `Resources/Info.plist` 的 `CFBundleShortVersionString` 与递增 `CFBundleVersion`，同步发布说明。
2. 执行 `Scripts/test.sh` 和 `Scripts/package-release.sh`。
3. 审查源码并提交至 main；执行 `Scripts/publish-release.sh` 创建 GitHub Release。`gh` 必须已登录仓库维护者账户。

打包脚本生成 DMG、ZIP、签名 `appcast.xml`、SHA-256 清单及公开版本信息。公开更新地址固定为 GitHub 最新 Release 的 `appcast.xml`；包链接指向对应版本 tag。

`Sparkle/bin/sign_update` 从 Keychain 读取发布私钥，签名后会再验证 ZIP 和更新信息。移动开发机器前，应安全备份该 Keychain 项；不要生成一个无关新公钥直接替换，否则已有安装无法验证新更新。

GitHub Actions 运行源码与构建检查，只上传构建产物；它不包含 API 密钥，也不持有发布签名私钥。签名发布当前从本机完成。

## Developer ID 与公证

已有证书时设置 `SIGNING_IDENTITY`。构建脚本按嵌套组件顺序签名 Sparkle 辅助程序、框架和应用，并开启 hardened runtime。

已有 notarytool Keychain 配置时设置 `NOTARY_PROFILE`，打包脚本会提交 DMG 公证并附加票据。密钥通过系统 Keychain 读取，不放进源码。此首版尚未验证 Developer ID / 公证流程，因为维护者没有相应证书。

每次发布保持 bundle ID、公钥和配置存储方式稳定。版本号必须递增；安装包中的设置不应来自维护者的日常配置。
