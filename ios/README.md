# iOS 端

## 当前状态

正式版第一版：

- 主 App 靠静音音频在后台保活，每秒轮询 `UIPasteboard.general.changeCount`；
- 计数一变就读出文字，存入 App Group 共享库（去重、上限 99 条）；
- 键盘扩展读最近 15 条，点一条就插进当前输入框；
- 主界面显示记录条数、共享区是否可用、最近一条内容，方便判断链路有没有真的通。

炸开选词交互还没接。

签名描述文件必须带 `com.apple.security.application-groups`，当前使用的 group ID 是
`group.48bf5183109e5584.1`。没有这个权限时，主 App 和键盘各写各的沙盒，键盘列表会是空的。

## 目录

```
ios/
  project.yml              工程配置，XcodeGen 读它生成 .xcodeproj
  Sources/
    App/                   主 App，SwiftUI + 后台采集探针
    Shared/                ClipStore，主 App 与键盘共用
    Keyboard/              键盘扩展，UIKit
.github/workflows/ios.yml  云端编译
```

工程文件不提交，由 CI 里的 XcodeGen 现场生成。

## 怎么取包

改动推到 `main` 后，Actions 会自动编译，产物同时出现在 Artifacts 和
`build-<运行号>` 这个 Release 里。

工作流里有一个 `probe` 小作业跑在 Linux 上：如果它成功而 `build` 被秒取消，
说明账号的 macOS runner 没额度或被限流，不是代码问题。

## 怎么装

1. 把 ipa 传到手机（文件传输助手、网盘都行）
2. 用 LC Sign 打开它
3. 选证书签名安装

装完检查键盘有没有一起进去：设置 › 通用 › 键盘 › 键盘 › 添加新键盘，看列表里有没有「剪贴炸」。

如果 App 能打开但键盘列表里没有，说明扩展没被签上，换个签名方式再试。

## 怎么验证采集

1. 打开 App 一次，别上划杀掉，让它留在后台
2. 切到别的 App，复制两三样不同的文字
3. 回来看「记录库」条数有没有涨，日志里每条变化后面会写内容、入库结果、共享区状态
4. 键盘切到「剪贴炸」，列表里应该能看到刚才复制的内容

## 本地编译

有 Mac 的话：

```bash
brew install xcodegen
cd ios
xcodegen generate
open ClipBang.xcodeproj
```

## 已知结论

静音音频保活在 iOS 27 有效，后台轮询与进程内通知都能察觉剪贴板变化；
Darwin 跨进程通知已失效，但轮询足够，不依赖它。
仍待真机验证的是：后台状态下 `UIPasteboard.general.string` 能否读到文字，
以及重签名后的 App Group 是否真的对主 App 和键盘都生效。
