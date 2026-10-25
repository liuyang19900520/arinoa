# BeautyCam (美图 美颜相机) teardown notes

Source: black-box observation through iPhone Mirroring, 2026-10-15. Camera preview is black under Mirroring.

## Camera screen (photo mode)

- **Top bar:** close (X) · 帮拍 (help-shoot) · aspect ratio (3:4) · more (···, with red dot) · flip camera
- **Preview overlays:** top-left icon (looks like "watermark/AI off"); bottom-right two icons (compare-ish, collapse)
- **Shooting-mode strip** above the shutter: 苹果模式 · **经典** (selected) · 原生 · CCD · 更多
- **Bottom row:** 贴纸 (stickers) · 风格 (styles) · shutter (pink→purple gradient circle) · 滤镜 (filters) · 美颜 (beauty)
- **Below:** 相册 (album) on the left · 视频 / 照片 tabs

## Beauty panel (美颜)

- Strength slider across the top of the panel, with a "saved look" icon on the left and a hold-to-compare icon on the right
- "多人美颜" (multi-face beauty) floating button on the right edge of the preview
- **Top tabs:** 美颜 · 美妆 (makeup) · 美体 (body) · 3D打光 (3D lighting)
- **Sub-tabs under 美颜:** 无 (off) · 脸型 (face shape) · **皮肤** (skin) · 眼部 (eyes) · 鼻部 (nose) · 眉毛 (brows) · 其他 (other)
- **皮肤 items:** 肤质▸ · 原肤 · **磨皮** · 肤色▸ (New) · 立体 · 清晰 … (row scrolls; ▸ = has sub-options)
- **Bottom:** 默认美颜 (reset to default) · small shutter · collapse (⌄)

## Not yet observed (blocked)

- Filter panel (滤镜): tapping it shows the membership upsell instead
- 风格, 贴纸, 脸型/眼部/鼻部/眉毛/其他 items, 美妆, 美体, 3D打光, video mode, ··· menu

## Redundant features to cut

- **Membership upsell modal** ("很高兴您喜欢美颜相机！升级成为会员…立即升级 / 取消"): appeared on almost every tap,
  with both background clicks and real full-screen clicks through iPhone Mirroring, and the tap never reached
  the control underneath. Remaining screens need on-device screenshots.
- 帮拍, 贴纸, 3D打光, 美体 → candidates to drop for the lean version (to confirm)
