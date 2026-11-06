# iOS 端

## 当前状态

骨架版本。只验证一件事：云端能不能编译出包、能不能装进手机。

剪贴板监听、炸开交互都还没接。

## 目录

```
ios/
  project.yml              工程配置，XcodeGen 读它生成 .xcodeproj
  Sources/
    App/                   主 App，SwiftUI
    Keyboard/              键盘扩展，UIKit
.github/workflows/ios.yml  云端编译
```

工程文件不提交，由 CI 里的 XcodeGen 现场生成。

## 怎么取包

改动推到 `main` 后，GitHub 的 Actions 页面会自动跑一次编译，五六分钟出结果。

跑完在对应那次运行的页面底部，Artifacts 里下载 `ClipBang-ipa`，解压得到 `ClipBang.ipa`。

## 怎么装

1. 把 ipa 传到手机（文件传输助手、网盘都行）
2. 用 LC Sign 打开它
3. 选证书签名安装

装完检查键盘有没有一起进去：设置 › 通用 › 键盘 › 键盘 › 添加新键盘，看列表里有没有「剪贴炸」。

如果 App 能打开但键盘列表里没有，说明扩展没被签上，换个签名方式再试。

## 本地编译

有 Mac 的话：

```bash
brew install xcodegen
cd ios
xcodegen generate
open ClipBang.xcodeproj
```

## 下一步

链路通了之后，接 Clip 那套后台监听，先验证在 iOS 27 上还灵不灵。不灵就得换思路。

诊断进度：静音音频保活有效，后台轮询与进程内通知都能察觉剪贴板变化；Darwin 跨进程通知已失效。当前在验证后台能否读到剪贴板文字内容。
