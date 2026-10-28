import SwiftUI
import AppKit
import Security

enum SigningStatus {
    /// nil team identifier means ad-hoc / self-signed: WidgetKit will refuse it on macOS 26.
    static var hasAppleTeam: Bool {
        var code: SecStaticCode?
        let url = Bundle.main.bundleURL as CFURL
        guard SecStaticCodeCreateWithPath(url, [], &code) == errSecSuccess, let code else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any]
        else { return false }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String != nil
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var keyDraft = ""
    @State private var savedFlash = false
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            openCodeSection
            sourcesSection
            providersSection
            footer
        }
        .padding(22)
        .frame(width: 430, height: 498)
        .background(Color(hex: 0x0B0B0D))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.8)
        )
        .environment(\.colorScheme, .dark)
        .onAppear { keyDraft = LocalConfig.value("opencodeKey") ?? "" }
        .onExitCommand { onClose() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("HEADROOM")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Palette.muted)
                Text("桌面挂件设置")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var openCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("OPENCODE GO")
            HStack(spacing: 6) {
                SecureField("API key (sk-…)", text: $keyDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.07), lineWidth: 0.7))
                Button {
                    store.saveOpenCodeKey(keyDraft)
                    savedFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { savedFlash = false }
                } label: {
                    Text(savedFlash ? "SAVED" : "SAVE")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color(hex: 0x00E676).opacity(0.9)))
                }
                .buttonStyle(.plain)
            }
            Text(store.openCodeKeySource.map { "当前来源：\($0)" } ?? "未配置。可在 opencode.ai/console 复制 API Key。")
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.faint)
        }
        .padding(13)
        .background(sectionBackground)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("DATA SOURCES")
            sourceRow(
                title: "Claude app",
                detail: "Cookies · Claude Safe Storage",
                ready: LocalCredentials.claudeAppReady()
            )
            sourceRow(
                title: "Codex / ChatGPT",
                detail: "~/.codex/auth.json",
                ready: LocalCredentials.codexReady()
            )
            sourceRow(
                title: "Cursor",
                detail: "state.vscdb · cursorAuth",
                ready: LocalCredentials.cursorReady()
            )
            sourceRow(
                title: "OpenCode Go",
                detail: store.openCodeKeySource ?? "API key 未配置",
                ready: store.openCodeKeySource != nil
            )
        }
        .padding(13)
        .background(sectionBackground)
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("SHOWN IN WIDGET")
            ForEach(ProviderKind.allCases) { kind in
                HStack(spacing: 8) {
                    ProviderGlyph(kind: kind, size: 18)
                    Text(kind.settingsName)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.text.opacity(0.9))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.enabledKinds.contains(kind) },
                        set: { store.setEnabled(kind, $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(kind.accent)
                    .controlSize(.mini)
                }
            }
        }
        .padding(13)
        .background(sectionBackground)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                store.refresh()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)

            Spacer()

            Text(SigningStatus.hasAppleTeam
                 ? "添加小组件：右键桌面 › 编辑小组件"
                 : "组件需 Apple 签名（当前 ad-hoc）")
                .font(.system(size: 9))
                .foregroundStyle(SigningStatus.hasAppleTeam ? Palette.faint : Palette.warning.opacity(0.8))
                .help(SigningStatus.hasAppleTeam
                      ? "右键桌面 → 编辑小组件"
                      : "macOS 26 的 amfid 会拒绝 ad-hoc 签名的扩展。安装 Xcode、登录 Apple ID 后重新运行 ./build.sh。")

            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.muted)
        }
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.7)
            )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Palette.faint)
    }

    private func sourceRow(title: String, detail: String, ready: Bool) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(ready ? Color(hex: 0x00E676) : Color.white.opacity(0.18))
                .frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.text.opacity(0.85))
            Text(detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(ready ? "READY" : "MISSING")
                .font(.system(size: 7.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(ready ? Palette.faint : Palette.warning.opacity(0.8))
        }
    }
}
