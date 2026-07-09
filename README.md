# PixelMask

图片隐私自动打码 iOS App。选择图片后自动识别其中的敏感信息并打码，全程离线，图片不会离开设备。

- 自动检测：电话/手机号、邮箱、身份证号、长数字、IP 地址、车牌、人脸、二维码、姓名/地名/机构（实验性，NLTagger）
- 实时预览：选中区域立即打码，切换样式即时生效
- 轻点图中文字整行打码；轻点已打码区域取消
- 拖动框选任意矩形区域打码
- 打码样式：色块（可选颜色）、像素化、毛玻璃、马克笔、隐藏文字（取背景色填充）
- 导出时自动移除 EXIF/GPS 等元数据

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
