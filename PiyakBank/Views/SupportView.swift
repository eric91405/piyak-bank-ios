import SwiftUI

struct SupportView: View {
    @Environment(\.openURL) private var openURL
    @State private var copiedEmail = false
    @State private var showMailUnavailable = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    var body: some View {
        Form {
            Section {
                Button("이메일로 문의하기", systemImage: "envelope") {
                    let url = URL(string: "mailto:\(AppConfig.supportEmail)?subject=PiyakBank%20Support")!
                    openURL(url) { accepted in showMailUnavailable = !accepted }
                }
                Button(copiedEmail ? "이메일 주소를 복사했어요" : "이메일 주소 복사", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = AppConfig.supportEmail
                    copiedEmail = true
                }
                Text(AppConfig.supportEmail)
                    .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                Link("지원 페이지", destination: AppConfig.supportURL)
            } header: { Text("도움이 필요하신가요?") } footer: {
                Text("문의할 때 앱 버전과 불편했던 상황을 알려주시면 도움이 돼요. 시급이나 근무 기록을 첨부하지 않아도 돼요.")
            }
            Section("앱 정보") {
                LabeledContent("앱", value: "삐약뱅크")
                LabeledContent("버전", value: version)
                LabeledContent("운영자", value: AppConfig.operatorName)
            }
        }
        .navigationTitle("문의하기").navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden).background(PB.C.bg)
        .alert("메일 앱을 열 수 없어요", isPresented: $showMailUnavailable) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("‘이메일 주소 복사’를 눌러 사용 중인 메일 앱이나 웹메일에서 문의해 주세요.")
        }
    }
}
