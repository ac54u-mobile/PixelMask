# PixelMask

图片隐私自动打码 iOS App。选择图片后自动识别其中的敏感信息并打码，全程离线，图片不会离开设备。

- 自动检测：电话/手机号、邮箱、身份证号、长数字、IP 地址、车牌、人脸、二维码、姓名/地名/机构（实验性，NLTagger），各类别可在设置中单独开关
- 实时预览：选中区域立即打码，切换样式即时生效
- 轻点图中文字整行打码；轻点已打码区域取消；一键全选/清空
- 拖动框选任意矩形区域打码，已打码区域可整体拖动调整位置、双指捻转旋转角度，支持撤销/重做
- 打码样式：色块（可选颜色）、像素化、模糊、马克笔、隐藏文字（取背景色填充），默认样式自动记忆
- 自定义文字水印（斜向平铺整图）
- 批量处理：一次最多选 9 张图，缩略图切换，一键全部保存
- 拍照打码：直接调用相机拍摄后进入编辑
- 长按图片对比原图
- 导出格式可选 JPEG（可调画质）/ PNG，导出时自动移除 EXIF/GPS 等元数据

技术：SwiftUI + Vision（OCR/人脸/二维码）+ CoreImage + NaturalLanguage，无第三方依赖，iOS 17+。

## 安装（TrollStore）

1. 打开仓库的 GitHub Actions，选择最新一次 `Build Unsigned IPA` 运行
2. 下载 `PixelMask-unsigned-ipa` 产物并解压得到 `PixelMask-unsigned.ipa`
3. 用 TrollStore 打开安装（无需签名）

## 本地构建

需要 macOS + Xcode 16+：

```bash
open PixelMask.xcodeproj
```

选择 `PixelMask` scheme，⌘R 运行。

## 项目结构

```text
PixelMask/
  App/          # 入口与编辑器状态 (PixelMaskApp, EditorState)
  Models/       # 区域与样式模型 (RedactionRegion)
  Services/     # 检测引擎与敏感信息分类 (DetectionEngine, SensitiveTextClassifier)
  Redaction/    # 打码渲染与坐标换算 (ImageRedactor, CoordinateMapper)
  Views/        # SwiftUI 界面 (Home, Editor)
.github/workflows/build.yml  # CI：产出未签名 IPA
```
