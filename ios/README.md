# iOS 端

## 当前状态

**拼音键盘版（ccbroad）**。主场景是中文拼音输入，词库随键盘扩展打包，纯 Swift / UIKit、零第三方依赖。

- 词库：34.8 万条中文词 + 单字全部读音，生成 **710,935 条**「全拼 / 简拼 → 中文 + 词频」索引。
  二进制 PYD1 格式，`Data(..., .mappedIfSafe)` 内存映射 + 二分前缀查询，不占键盘扩展内存预算；
  另带 4 万条全局高频表，保证单/双字母输入也出好词。
- 输入：默认中文拼音，支持全拼 `nihao`、简拼 `nh`、多音字词组（`chongqing` → 重庆、
  `yinhang` → 银行、`yinyue` → 音乐）、连打（选带 `›` 的候选后剩余拼音继续出词）；
  空格 / 换行上屏首候选，删除键先退拼音再退正文。
- 「中」切英文直输，「123」切数字符号页，「粘贴」在用户手势上下文里读剪贴板并入库。
- 顶部「键盘 / 记录库」切换；记录库由键盘可见期的 0.8 秒轮询自动采集，点条目直接插入。
- 数据来源与许可见 `Resources/Pinyin/SOURCES.txt`（jieba / pinyin-data / pypinyin，均为 MIT）。
  生成脚本 `Tools/build_pinyin_dict.py`（Python 3 + pypinyin），CI 不运行它，仓库内提交的是已生成的 `.bin`。

签名描述文件必须带 `com.apple.security.application-groups`，当前使用的 group ID 是
`group.48bf5183109e5584.1`。没有这个权限时，主 App 和键盘各写各的沙盒，键盘列表会是空的。

剪贴板后台采集为什么改走键盘，见文末「已知结论」。

## 目录

```
ios/
  project.yml              工程配置，XcodeGen 读它生成 .xcodeproj
  Sources/
    App/                   主 App，SwiftUI + 后台采集探针
    Shared/                ClipStore，主 App 与键盘共用
    Keyboard/              键盘扩展，UIKit + 拼音引擎 + 候选栏
  Resources/Pinyin/         拼音词库二进制、数据来源与 MIT 许可证
  Tools/build_pinyin_dict.py 词库生成脚本（Python 3 + pypinyin）
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

装完检查键盘有没有一起进去：设置 › 通用 › 键盘 › 键盘 › 添加新键盘，看列表里有没有「ccbroad」。
记得打开「完全访问」，否则读不到剪贴板、共享记录库也是空的。

如果 App 能打开但键盘列表里没有，说明扩展没被签上，换个签名方式再试。

## 怎么验证

1. 任意输入框切到 ccbroad，敲 `nihao`，候选栏应出现「你好」，点一下上屏
2. 敲 `zg` 试简拼（中国 / 这个）、`chongqing` 试多音字（重庆）、
   `nihaoma` 试连打（选「你好 ›」后剩下的 `ma` 继续出候选）
3. 状态行会显示「词库 710935条」，若显示「词库缺失」说明资源没被打进 .appex
4. 切到「记录库」，保持键盘可见并连续复制几段文字，应逐条出现
5. 点任一条，文字插入当前输入框

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
Darwin 跨进程通知已失效。App Group 已确认对主 App 与键盘都生效。

真机结论：把「从其他 App 粘贴」设为「允许」只消掉弹窗；后台依然被完全屏蔽
（`changeCount` 报 0、`items=0`、`string`/`data` 全 nil），只有切回前台才读得到
当前那一条。剪贴板是单槽，中间复制的内容在被覆盖时永久丢失，所以会出现
「复制三四条只存一条」。

攻坚版结果（已定论）：`MonitorProbe` 在通知回调里同步立即读，真机 10 次采集事件中
后台 9 次全部「通道=全断」，只有切回前台那 1 次读到内容。第一条后台通知甚至
`items=1`（能看见有条目），但 `string` / `data` 仍被拒——说明是授权层拒绝，
与读取时机无关，再快也没用。Objective-C 反射列出 `PBServerConnection` 共 29 个方法，
其中有 `preauthorizePasteForAuditToken:` 与 `requestPatternDetections...needValues:`
等预授权 / 带值接口，属私有 API 逆向范畴，本项目不再投入。

**结论：iOS 27 上「后台自动攒剪贴板历史」做不出来。** 剪贴板单槽 + 后台内容层
被完全拒绝，中间复制的内容在被覆盖时永久丢失。iOS 端保留当前形态
（键盘插入最近一条），不再为自动采集发版。Android 端不受此限制。
