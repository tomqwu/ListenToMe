import ListenToMeCore
import SwiftUI

/// The bundled `ThirdPartyNotices.txt` (the same file the macOS app ships), split per package (issue #202).
enum MobileAcknowledgements {
    static func bundledNotices(bundle: Bundle = .main) -> [ThirdPartyNotice] {
        guard let url = bundle.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return ThirdPartyNotices.parse(text)
    }
}

/// Settings → About: the version, and the Acknowledgements screen with every third-party license.
struct MobileAboutSection: View {
    var body: some View {
        Section("About") {
            LabeledContent("Version", value: MobileReleaseNotes.identity)
            Text("iPhone & iPad · iOS 26 or later")
            NavigationLink("Acknowledgements") { MobileAcknowledgementsView() }
                .accessibilityIdentifier("acknowledgements")
        }
    }
}

/// Settings → About → Acknowledgements: every open-source package built into the app, each opening
/// its full license text.
struct MobileAcknowledgementsView: View {
    private let notices = MobileAcknowledgements.bundledNotices()

    var body: some View {
        List {
            Section {
                Text("ListenToMe is built with these open-source packages. Each one's license is reproduced in full.")
                    .font(.subheadline)
            }
            Section("Packages") {
                if notices.isEmpty {
                    Text("Notices are unavailable in this build.").foregroundStyle(.secondary)
                }
                ForEach(notices) { notice in
                    NavigationLink {
                        MobileNoticeTextView(notice: notice)
                    } label: {
                        LabeledContent(notice.displayName, value: notice.version)
                    }.accessibilityIdentifier("notice-\(notice.identity)")
                }
            }
        }
        .accessibilityIdentifier("acknowledgementsList")
        .scrollContentBackground(.hidden).background(MobileStyle.canvas)
        .navigationTitle("Acknowledgements").navigationBarTitleDisplayMode(.inline)
    }
}

private struct MobileNoticeTextView: View {
    let notice: ThirdPartyNotice

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(notice.displayName) \(notice.version)").font(.headline)
                Text(notice.url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text(notice.text).font(.caption.monospaced()).textSelection(.enabled)
                    .accessibilityIdentifier("noticeText")
            }.padding()
        }
        .background(MobileStyle.canvas)
        .navigationTitle(notice.displayName).navigationBarTitleDisplayMode(.inline)
    }
}
