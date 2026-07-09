import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var state: EditorState
    @Environment(\.dismiss) private var dismiss

    @State private var kindsChanged = false

    /// 可开关的检测类别；姓名/地名合并为一个开关
    private static let toggleItems: [(title: String, kinds: [DetectionKind])] = [
        ("电话/手机号", [.phone]),
        ("邮箱", [.email]),
        ("证件号", [.idNumber]),
        ("长数字", [.longNumber]),
        ("IP 地址", [.ipAddress]),
        ("车牌", [.carPlate]),
        ("姓名/地名/机构（实验）", [.personName, .placeName]),
        ("人脸", [.face]),
        ("二维码", [.qrCode]),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Self.toggleItems, id: \.title) { item in
                        Toggle(item.title, isOn: binding(for: item.kinds))
                    }
                } header: {
                    Text("自动检测类别")
                } footer: {
                    Text("关闭的类别不参与自动识别，修改后会重新识别当前图片。")
                }

                Section {
                    Toggle("添加水印", isOn: $state.watermarkEnabled)
                    if state.watermarkEnabled {
                        TextField("水印文字", text: $state.watermarkText)
                    }
                } header: {
                    Text("水印")
                } footer: {
                    Text("半透明文字水印会斜向平铺在整张图上，防止图片被挪作他用。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onDisappear {
            if kindsChanged {
                state.detect()
            }
        }
    }

    private func binding(for kinds: [DetectionKind]) -> Binding<Bool> {
        Binding(
            get: { !kinds.allSatisfy { state.disabledKinds.contains($0) } },
            set: { isOn in
                if isOn {
                    state.disabledKinds.subtract(kinds)
                } else {
                    state.disabledKinds.formUnion(kinds)
                }
                kindsChanged = true
            }
        )
    }
}
