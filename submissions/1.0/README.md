# 1.0 —— 首次上架（Arinoa）

| 项 | 值 |
|---|---|
| 版本 / 构建号 | **1.0.0 (3)**（建议用 build 3 或之后包含语言切换的构建） |
| ASC App ID | 6827531369 |
| Bundle ID | `com.arinoa.beautycam` |
| SKU | `arinoa-beautycam`（API 读出） |
| 主语言 | en-US（API 读出，已设置） |
| 状态 | ⏳ 仅准备材料，**未提交审核** |

> ⚠️ ASC 里已有的 App Store 版本记录是 **"1.0"**（PREPARE_FOR_SUBMISSION），而构建的 MARKETING_VERSION 是 **1.0.0**。提交时版本号必须一致：要么在 ASC 把版本改成 1.0.0，要么把 project.yml 改成 1.0。建议 ASC 改成 1.0.0。

## 一、ASC 当前状态（2026-10-28 经 API 只读查询）

| 项 | API 结果 | 结论 |
|---|---|---|
| App 记录 | name=Arinoa, primaryLocale=en-US | ✅ 已有 |
| App Store 版本 | `1.0` / PREPARE_FOR_SUBMISSION / IOS | ✅ 已有（版本号需对齐，见上） |
| 主类别 primaryCategory | null | ❌ 未设置 → 选「摄影与录像 Photo & Video」 |
| 年龄分级问卷 | 所有题目 null | ❌ 未填写 |
| 本地化（App 信息） | 只有 en-US：name=Arinoa，subtitle/隐私政策URL 均为空 | ❌ 缺副标题、隐私政策 URL、zh-Hans/ja 本地化 |
| contentRightsDeclaration | null | ❌ 未回答 |
| 价格 appPriceSchedule | 记录存在，未确认具体价格档 | ⚠️ 需在网页确认「免费」 |
| 销售范围 appAvailabilities(v2) | 404 不存在 | ❌ 未设置 |
| App 隐私（营养标签） | API 无法读取 | ⚠️ 需网页确认 |
| 审核联系人（TestFlight 用） | Yang Liu / +81… / liuyang19900520@gmail.com | 可复用到 App Review 信息 |

## 二、ASC 填写清单

### App 信息
| 字段 | en-US | zh-Hans | ja |
|---|---|---|---|
| 名称（≤30） | `en-US/name.txt` Arinoa: Beauty Camera | Arinoa美颜相机 | Arinoa - 美肌カメラ |
| 副标题（≤30） | Real-time beauty & filters | 自然实时美颜，拍照录像都好看 | 自然なリアルタイム美肌・フィルター |
| 类别 | 主：摄影与录像；次（可选）：生活 / 美容（无美容类则留空） |||
| 内容版权 | 选「否，不包含第三方内容」（App 不含、也不显示第三方内容；滤镜/LUT 为自制） |||
| 版权 Copyright | `© 2026 Yang Liu` |||
| 隐私政策 URL | 待托管（见第四节） |||
| 支持 URL（必填） | 待托管，例如 `https://<域名>/arinoa/support.html` |||
| 营销 URL | 可选，可留空 |||

### 版本信息
推广文本（≤170）、描述（≤4000）、关键词（≤100 字节，逗号分隔不加空格）、新内容 —— 见各语言目录。首个版本「新内容」ASC 通常不显示/不要求，备用。

### 年龄分级问卷（全部回答「无/否」→ 预计 4+）
| 题目 | 回答 | 理由 |
|---|---|---|
| 暴力（卡通/真实/血腥） | 无 | 相机工具，无此类内容 |
| 色情/裸露、成人暗示主题 | 无 | 不提供此类内容；用户自拍不算 App 提供的内容 |
| 粗俗/低俗幽默、恐怖 | 无 | 无 |
| 酒精烟草药物、医疗信息、健康/养生话题 | 无 | 美颜≠医疗；描述里不要写“祛痘治疗”之类 |
| 赌博/模拟赌博/竞赛/开箱 | 无 | 无 |
| 不受限网页访问 | 否 | 无 WebView、不联网 |
| 用户生成内容/社交/聊天 | 否 | 照片只存本机相册，无分享社区、无聊天 |
| 广告 | 否 | 无广告 SDK |
| 家长控制/年龄验证 | 否 | 无 |
| Made for Kids | 否 | API 已显示 isOrEverWasMadeForKids=false |

### App 隐私（营养标签）
**结论：「不收集数据 Data Not Collected」**。已核对代码：
- 无 `URLSession`/网络请求、无第三方 SDK（只用 AVFoundation、CoreImage、Vision、Photos、PhotosUI、SwiftUI）
- 相机/麦克风帧只在本地处理、写入本地文件；Vision 人脸检测在设备端
- `PHPhotoLibrary` 只做写入（NSPhotoLibraryAddUsageDescription）；选图用 PhotosPicker（不需要权限）
- PR #7 用 `@AppStorage`（UserDefaults）只存语言设置，本地，不算“收集”
- 无追踪 → 不需要 ATT

### 隐私清单 PrivacyInfo.xcprivacy（PLAN.md 待办）
合并 PR #7 后 App 使用 UserDefaults（@AppStorage），属于 Required Reason API，需要添加 `PrivacyInfo.xcprivacy` 声明 `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`，`NSPrivacyTracking=false`，收集数据为空（同 shadow-player 做法）。否则上传时可能收到 ITMS-91053 警告/拒绝。→ 需要一个单独的代码 PR。

### 出口合规
PR #4 在 project.yml 设置 `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO`。App 不联网、不使用加密 → 正确，ASC 不再询问。注意：该键要在合并后的 main 构建里存在。

### 权限文案
project.yml 中三个用途说明（相机/麦克风/相册写入）为中文；PR #7 加了 `InfoPlist.xcstrings` 三语本地化 → 提交用的构建必须包含 PR #7。

### App 审核信息
- 登录：不需要
- 联系人：Yang Liu, liuyang19900520@gmail.com, 电话同 TestFlight
- 备注：`review-notes.txt`

## 三、截图
2026 年 iPhone 要求：**6.9 英寸（1320×2868 或 1290×2796，竖屏）必须提供**，其他尺寸由 Apple 自动缩放；6.5 英寸（1284×2778 / 1242×2688）在没有 6.9 时才需要。App 只支持 iPhone（TARGETED_DEVICE_FAMILY=1），**不需要 iPad 截图**。每种语言 1–10 张（可三语共用一套，但建议本地化 UI）。

本 Linux 机器无法生成截图。方案：
1. **推荐**：在 Yang 的 iPhone（6.9 英寸机型，如 16/17 Pro Max）真机拍摄 —— 相机 App 在模拟器里没有摄像头画面，模拟器截图只会是黑屏。
2. Mac 上 Xcode 模拟器（iPhone 17 Pro Max）+ `xcrun simctl io booted screenshot`，但需 App 加 UI 测试用的示例图模式。
3. CI：`ci-draft/screenshots.yml`（macOS runner + xcodebuild test 导出附件），同样需要示例图模式，**未启用、未运行**。

## 四、隐私政策 / 支持页托管
shadow-player 的做法：仓库 `docs/privacy.html`、`docs/support.html`，GitHub Pages + 自定义域名（`https://shadowplayer.liuyang19900520.com/privacy.html`）。
建议 Arinoa 同样：把 `privacy/` 三语内容做成 `docs/privacy.html` + `docs/support.html`，开启 GitHub Pages（需要 Yang 在仓库设置里开启；公开仓库才能免费用 Pages），或直接放进 shadow-player 的站点下 `/arinoa/privacy.html`。

## 五、还缺什么 / 需要 Yang 做的
- [ ] Apple Developer 最新协议由账号持有人接受（若有未接受协议，提交按钮不可用）；免费 App 不需付费协议，但要确认无待签协议
- [ ] 托管隐私政策 & 支持页，填 URL（需决定：开 arinoa 的 GitHub Pages 还是挂在现有域名下）
- [ ] ASC 版本号 1.0 ↔ 构建 1.0.0 对齐
- [ ] 设置主类别 Photo & Video
- [ ] 确认年龄分级问卷答案（上表）
- [ ] 内容版权声明
- [ ] 价格=免费、销售范围（国家/地区）
- [ ] **中国大陆**：自 2023 年起大陆上架需 ICP 备案号（无网络的单机 App 是否必须、个人开发者能否备案 → **需验证**）；美颜/AI 类不涉及深度合成服务的话一般不需算法备案（**需验证**）。稳妥做法：首发先不勾选中国大陆
- [ ] App 隐私填「不收集数据」并发布
- [ ] 截图（6.9 英寸，三语）
- [ ] 图标最终版（PR #4/#7 里的 AppIcon.png 是否定稿；1024×1024、无透明）
- [ ] 添加 PrivacyInfo.xcprivacy（代码 PR）
- [ ] 显示名：现在 CFBundleDisplayName=「Arinoa美颜」，与商店名不同可以，但确认是否三语本地化
- [ ] 用合并 #4 + #7（+ 隐私清单）后的 main 打新构建（build 4），再选该构建提交
- [ ] 最终提交审核 —— **只有 Yang 明确同意后才做**
