//
//  AboutSettingsPane.swift
//  Ice
//

import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL

    private var updatesManager: UpdatesManager {
        appState.updatesManager
    }

    private var acknowledgementsURL: URL {
        // swiftlint:disable:next force_unwrapping
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "pdf")!
    }

    private var contributeURL: URL {
        URL(string: "https://github.com/jordanbaird/Ice")!
    }

    private var issuesURL: URL {
        contributeURL.appendingPathComponent("issues")
    }

    private var donateURL: URL {
        URL(string: "https://icemenubar.app/Donate")!
    }

    private var lastUpdateCheckString: String {
        if let date = updatesManager.lastUpdateCheckDate {
            date.formatted(date: .abbreviated, time: .standard)
        } else {
            "从未检查"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            mainForm
            Spacer(minLength: 20)
            bottomBar
        }
        .padding(30)
    }

    @ViewBuilder
    private var mainForm: some View {
        IceForm(padding: EdgeInsets(top: 5, leading: 30, bottom: 30, trailing: 30), spacing: 0) {
            appIconAndCopyrightSection
                .layoutPriority(1)

            Spacer(minLength: 0)
                .frame(maxHeight: 20)

            updatesSection
                .layoutPriority(1)
        }
        .scrollDisabled(true)
        .frame(maxHeight: 500)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 20, style: .circular))
    }

    @ViewBuilder
    private var appIconAndCopyrightSection: some View {
        IceSection(options: .plain) {
            HStack(spacing: 10) {
                if let nsImage = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 225)
                }

                VStack(alignment: .leading) {
                    Text("Ice")
                        .font(.system(size: 72, weight: .medium))
                        .foregroundStyle(.primary)

                    Text("版本 \(Constants.versionString)")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)

                    Text(Constants.copyrightString)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var updatesSection: some View {
        IceSection(options: .hasDividers) {
            automaticallyCheckForUpdates
            automaticallyDownloadUpdates
            if updatesManager.canCheckForUpdates {
                checkForUpdates
            }
        }
        .frame(maxWidth: 600)
    }

    @ViewBuilder
    private var automaticallyCheckForUpdates: some View {
        Toggle(
            "自动检查更新",
            isOn: updatesManager.bindings.automaticallyChecksForUpdates
        )
    }

    @ViewBuilder
    private var automaticallyDownloadUpdates: some View {
        Toggle(
            "自动下载更新",
            isOn: updatesManager.bindings.automaticallyDownloadsUpdates
        )
    }

    @ViewBuilder
    private var checkForUpdates: some View {
        HStack {
            Button("检查更新") {
                updatesManager.checkForUpdates()
            }
            Spacer()
            Text("上次检查：\(lastUpdateCheckString)")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            Button("退出 Ice") {
                NSApp.terminate(nil)
            }
            Spacer()
            Button("致谢") {
                NSWorkspace.shared.open(acknowledgementsURL)
            }
            Button("贡献") {
                openURL(contributeURL)
            }
            Button("报告问题") {
                openURL(issuesURL)
            }
            Button("支持 Ice", systemImage: "heart.circle.fill") {
                openURL(donateURL)
            }
        }
        .padding(8)
        .buttonStyle(BottomBarButtonStyle())
        .background(.quinary, in: Capsule(style: .circular))
        .frame(height: 40)
    }
}

private struct BottomBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private var borderShape: some InsettableShape {
        Capsule(style: .circular)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                borderShape
                    .fill(configuration.isPressed ? .tertiary : .quaternary)
                    .opacity(isHovering ? 1 : 0)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
