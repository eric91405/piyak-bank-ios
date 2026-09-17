import SwiftUI
import SwiftData
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.scenePhase) private var phase
    @Query private var transactions: [PointTransaction]
    @Query(sort: \WorkSession.startedAt) private var records: [WorkSession]
    @State private var showWage = false
    @State private var confirmReset = false
    @State private var showExport = false
    @State private var document = CSVDocument(text: "")
    @State private var exportName = "PiyakBank-records"
    @State private var notificationStatus = "확인 중"
    private var total: Int { transactions.filter { $0.kind == .accrual }.reduce(0) { $0 + $1.amount } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 18) {
                        Image("AppMascot").resizable().scaledToFit().frame(width: 74, height: 74).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("나와 삐약이").font(.title3.bold())
                            Text("Lv. \(max(1, total / RewardPolicy.pointsPerLevel + 1)) · 완료한 근무 \(records.filter { !$0.isActive }.count)회")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Section("근무") {
                    Button { showWage = true } label: {
                        LabeledContent("기본 시급", value: session.preferredWage.won)
                    }.disabled(session.current != nil)
                    Text("진행 중인 근무의 시급은 바뀌지 않아요. 종료 후 기록에서 수정할 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("꾸미기 보상") {
                    LabeledContent("타이머 근무", value: "10분에 100P")
                    LabeledContent("하루 적립 한도", value: RewardPolicy.pointsPerDay.points)
                    LabeledContent("하루 기준", value: "한국 시간 00시")
                    Text("시급과 무관하며 휴식은 제외해요. 기록을 직접 추가·수정해도 보상이 늘지 않고, 이미 받은 포인트와 레벨은 기록을 수정·삭제해도 유지돼요.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("한 타이머의 보상은 누적 유급 근무 24시간까지만 계산해요. 그 뒤에도 예상 수익은 계속 기록되며, 보상을 다시 모으려면 근무를 마치고 새로 시작해 주세요. 새로 시작해도 하루 적립 한도는 유지돼요.")
                        .font(.caption).foregroundStyle(.secondary)
                    if transactions.contains(where: { $0.kind == .migration }) {
                        Text("이전 포인트는 새 아이템 가격에 맞춰 20분의 1로 전환했어요. 전환 포인트는 최대 4,800P이며 레벨에는 반영되지 않아요. 근무 기록과 보유 아이템은 유지돼요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("근무 중 알림", isOn: Binding(get: { session.notificationsEnabled }, set: { enabled in
                        Task {
                            if enabled {
                                let granted = await NotificationScheduler().requestAuth()
                                session.notificationsEnabled = granted
                            } else { session.notificationsEnabled = false }
                            await refreshPermission()
                        }
                    }))
                    Picker("알림 간격", selection: $session.interval) {
                        ForEach(ReminderInterval.allCases, id: \.self) { Text("\($0.rawValue)분").tag($0) }
                    }.disabled(!session.notificationsEnabled)
                    LabeledContent("시스템 권한", value: notificationStatus)
                    Link("시스템 알림 설정 열기", destination: URL(string: UIApplication.openSettingsURLString)!)
                } header: { Text("알림") } footer: {
                    Text("근무 중 최대 24시간 앞까지 예약해요. 집중 모드와 시스템 설정에 따라 늦게 도착할 수 있어요.")
                }
                Section("내 데이터") {
                    Button("근무 기록 CSV 내보내기", systemImage: "square.and.arrow.up") {
                        session.perform {
                            exportName = "PiyakBank-work-records"
                            document = CSVDocument(text: try DataExport.records(records))
                            showExport = true
                        }
                    }
                    Button("포인트 원장 CSV 내보내기", systemImage: "list.bullet.rectangle") {
                        exportName = "PiyakBank-point-ledger"
                        document = CSVDocument(text: DataExport.ledger(transactions))
                        showExport = true
                    }
                    Button("모든 기록 초기화", systemImage: "trash", role: .destructive) { confirmReset = true }
                }
                Section("도움말과 개인정보") {
                    NavigationLink("삐약뱅크 이용 안내") { HelpView() }
                    NavigationLink("개인정보 처리방침") { PrivacyView() }
                    Link("지원 문의: \(AppConfig.supportEmail)", destination: URL(string: "mailto:\(AppConfig.supportEmail)?subject=PiyakBank%20Support")!)
                    LabeledContent("운영자", value: AppConfig.operatorName)
                    LabeledContent("버전", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .navigationTitle("나와 삐약이").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(PB.C.bg)
            .task { await refreshPermission() }
            .onChange(of: phase) { _, value in if value == .active { Task { await refreshPermission() } } }
            .sheet(isPresented: $showWage) {
                NavigationStack {
                    WagePreferenceView(wage: session.preferredWage) { value in
                        session.preferredWage = value; showWage = false
                    }
                }.presentationDetents([.medium, .large])
            }
            .confirmationDialog("모든 근무와 포인트를 지울까요?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("모든 데이터 삭제", role: .destructive) { session.perform { try session.resetAll() } }
            } message: {
                Text("진행 중인 근무, 기록, 포인트, 구매한 아이템을 삭제하고 기본 방으로 돌아가요. 되돌릴 수 없으니 먼저 CSV로 내보내 주세요.")
            }
            .fileExporter(isPresented: $showExport, document: document, contentType: .commaSeparatedText, defaultFilename: exportName) { result in
                if case .failure(let error) = result { session.errorMessage = "내보내지 못했어요. \(error.localizedDescription)" }
            }
        }
    }
    private func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: notificationStatus = "허용됨"
        case .denied: notificationStatus = "꺼져 있음"
        default: notificationStatus = "아직 요청하지 않음"
        }
    }
}

private struct WagePreferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State var text: String
    let save: (Int) -> Void
    init(wage: Int, save: @escaping (Int) -> Void) { _text = State(initialValue: String(wage)); self.save = save }
    var body: some View {
        Form {
            TextField("시급 (원)", text: $text).keyboardType(.numberPad)
            Text("1~1,000,000원 · 다음 근무의 예상 수익에 적용돼요. 꾸미기 포인트에는 영향을 주지 않아요.").font(.footnote).foregroundStyle(.secondary)
            Button("저장") { if let wage = Int(text) { save(wage) } }
                .disabled(!(1...EarningsCalculator.maximumWage).contains(Int(text) ?? 0))
        }.navigationTitle("기본 시급").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

@MainActor
enum DataExport {
    private static func row(_ fields: [String]) -> String {
        fields.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
    }
    static func records(_ records: [WorkSession]) throws -> String {
        let formatter = ISO8601DateFormatter()
        let now = Date()
        var rows = [row(["근무ID", "상태", "구간시작UTC", "구간종료UTC", "시급원", "유급초", "근무전체예상수익원_첫구간에만"])]
        for record in records {
            for (index, segment) in try record.decodedSegments().enumerated() {
                rows.append(row([record.id, record.isActive ? "진행중" : "완료", formatter.string(from: segment.start),
                    formatter.string(from: segment.end ?? now), String(segment.hourlyWage),
                    String(Int(EarningsCalculator.workingSeconds([segment], until: now))), index == 0 ? String(record.accrued(until: now)) : ""]))
            }
        }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
    }
    static func ledger(_ transactions: [PointTransaction]) -> String {
        let formatter = ISO8601DateFormatter()
        var rows = [row(["거래ID", "종류", "기준일시UTC", "포인트", "관련ID", "메모"])]
        rows += transactions.sorted { $0.date < $1.date }.map {
            row([$0.id.uuidString, $0.kindRaw, formatter.string(from: $0.date), String($0.amount), $0.relatedId ?? "", $0.note ?? ""])
        }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
    }
}
