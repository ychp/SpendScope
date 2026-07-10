import SwiftUI

struct SettingsView: View {
    @State private var refreshInterval = 60
    @State private var launchAtLogin = false
    @State private var notifyAtTwenty = true
    @State private var notifyAtFive = true

    var body: some View {
        Form {
            Section("数据源") {
                LabeledContent("Codex CLI", value: "待接入")
                LabeledContent("Codex macOS", value: "待接入")
                Text("当前展示原型数据，尚未读取真实 Codex 数据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("刷新") {
                Picker("自动刷新", selection: $refreshInterval) {
                    Text("30 秒").tag(30)
                    Text("60 秒").tag(60)
                    Text("5 分钟").tag(300)
                }
                Toggle("开机启动", isOn: $launchAtLogin)
            }

            Section("额度通知") {
                Toggle("剩余 20% 时通知", isOn: $notifyAtTwenty)
                Toggle("剩余 5% 时通知", isOn: $notifyAtFive)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
    }
}
