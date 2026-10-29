import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct IOSContentView: View {
    @EnvironmentObject private var store: IOSStore
    @State private var showFolderPicker = false
    @State private var showFilePicker = false

    var body: some View {
        ZStack {
            Color(hex: 0x070708).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if let snapshot = store.snapshot {
                        WidgetPreviewCard(snapshot: snapshot, width: 344, height: 354)
                            .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
                    } else {
                        emptyCard
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .refreshable { store.reload() }
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.chooseFolder(url)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.chooseFile(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            store.reload()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("HEADROOM")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(Palette.muted)
            Spacer()
            Button {
                store.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .tint(Palette.muted)
            Button {
                showFolderPicker = true
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .semibold))
            }
            .tint(Palette.muted)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "icloud")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.muted)
            Text("Waiting for sync")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.text)
            Text("Run Headroom on your Mac, then choose the AIUsageWidget folder in iCloud Drive.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    showFolderPicker = true
                } label: {
                    Text("Choose folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color(hex: 0x00E676)))
                }
                .buttonStyle(.plain)

                Button {
                    showFilePicker = true
                } label: {
                    Text("Pick widget.json")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.7)
        )
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.warning.opacity(0.85))
                    .multilineTextAlignment(.center)
            } else {
                Text("Synced \(Format.relative(store.snapshot?.savedAt))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Palette.faint)
            }
            Text("iCloud Drive › AIUsageWidget\(store.folderName.map { " · \($0)" } ?? "")")
                .font(.system(size: 8.5))
                .foregroundStyle(Palette.faint.opacity(0.7))
                .multilineTextAlignment(.center)
            Button {
                NotificationScheduler.shared.scheduleTest()
            } label: {
                Text("发送测试通知")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.faint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            if !store.debugText.isEmpty {
                Text(store.debugText)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(Palette.faint.opacity(0.65))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }
}
