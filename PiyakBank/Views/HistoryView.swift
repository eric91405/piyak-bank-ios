import SwiftUI
import SwiftData

struct HistoryView: View {
    @EnvironmentObject private var session: SessionController
    @Query(sort: \WorkSession.startedAt, order: .reverse) private var records: [WorkSession]
    @State private var selectedDate = Date()
    @State private var editor: WorkRecordPresentation?
    @State private var deleting: EconomyStore.RecordRevision?
    private let calendar = Calendar.current

    private var dayRecords: [WorkSession] {
        let start = calendar.startOfDay(for: selectedDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return records.filter { $0.startedAt < end && ($0.endedAt ?? .now) > start }
    }
    /// Walking every record on each render makes the list stutter once a few
    /// hundred sessions exist. Only records overlapping the month can contribute.
    private var monthTotal: Int {
        guard let month = calendar.dateInterval(of: .month, for: selectedDate) else { return 0 }
        let now = Date()
        return records.reduce(0) { result, record in
            guard record.startedAt < month.end, (record.endedAt ?? now) > month.start else { return result }
            return result + EarningsCalculator.daily(record.segments, until: now)
                .filter { $0.day >= month.start && $0.day < month.end }
                .reduce(0) { $0 + $1.amount }
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(selectedDate, format: .dateTime.year().month().locale(Locale(identifier: "ko_KR")))
                            .font(.subheadline.bold()).foregroundStyle(PB.C.secondary)
                        Text(monthTotal.won).font(.system(.largeTitle, design: .rounded, weight: .heavy))
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text("이번에 선택한 달의 예상 수익 · 진행 중인 근무 포함")
                            .font(.caption).foregroundStyle(PB.C.secondary)
                    }.gameCard()
                    EarningsCalendar(selectedDate: $selectedDate)
                    HStack {
                        Text(selectedDate, format: .dateTime.month().day().weekday().locale(Locale(identifier: "ko_KR")))
                            .font(.headline)
                        Spacer()
                        Text("\(dayRecords.count)개의 근무").font(.caption).foregroundStyle(PB.C.secondary)
                    }
                    if dayRecords.isEmpty {
                        ContentUnavailableView("아직 조용한 하루예요", systemImage: "calendar.badge.plus",
                                               description: Text("놓친 근무가 있다면 오른쪽 위 +로 추가해 주세요."))
                    }
                    ForEach(dayRecords) { record in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(record.isActive ? "진행 중인 근무" : "마친 근무", systemImage: record.isActive ? "clock.fill" : "checkmark.seal.fill")
                                    .font(.subheadline.bold()).foregroundStyle(PB.C.accent)
                                Spacer()
                                if !record.isActive {
                                    Menu {
                                        Button("기록 수정", systemImage: "pencil") {
                                            session.perform {
                                                editor = WorkRecordPresentation(revision: try session.economy.revision(for: record))
                                            }
                                        }
                                        Button("기록 삭제", systemImage: "trash", role: .destructive) {
                                            session.perform { deleting = try session.economy.revision(for: record) }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis").padding(12).contentShape(Rectangle())
                                    }.accessibilityLabel("근무 기록 수정 또는 삭제")
                                }
                            }
                            Text(EarningsCalculator.earned(on: selectedDate, segments: record.segments).won)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text("선택한 날짜에 해당하는 예상 수익").font(.caption).foregroundStyle(PB.C.secondary)
                            Text("\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) → \(record.endedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "지금")")
                                .font(.caption).foregroundStyle(PB.C.secondary)
                            let seconds = Int(EarningsCalculator.workingSeconds(record.segments))
                            Text("유급 근무 \(seconds / 3600)시간 \(seconds % 3600 / 60)분 · 휴식 제외")
                                .font(.caption).foregroundStyle(PB.C.secondary)
                        }.gameCard()
                    }
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.background(PB.C.bg.ignoresSafeArea()).foregroundStyle(PB.C.textBrown)
                .navigationTitle("차곡차곡 기록").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("근무 추가", systemImage: "plus") { editor = WorkRecordPresentation(revision: nil) }
                    }
                }
                .sheet(item: $editor) { presentation in
                    WorkRecordEditor(revision: presentation.revision, wage: session.preferredWage)
                        .id(presentation.id)
                        .environmentObject(session)
                }
                .confirmationDialog("이 기록을 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("근무 기록 삭제", role: .destructive) {
                        if let record = deleting {
                            session.perform { try session.economy.deleteRecord(revision: record) }
                            session.refreshSnapshot()
                        }
                        deleting = nil
                    }
                } message: { Text("이 근무의 시간과 예상 수익을 삭제해요. 이미 받은 포인트와 레벨은 유지되며, 기록을 다시 추가해도 포인트는 늘지 않아요. 삭제는 되돌릴 수 없어요.") }
        }
    }
}

/// The presentation and its payload change together. Separate Boolean/record
/// state can open a new-record editor before SwiftUI observes the selected record.
private struct WorkRecordPresentation: Identifiable {
    let id = UUID()
    let revision: EconomyStore.RecordRevision?
}

private struct SegmentDraft: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date
    var wage: String
}

struct WorkRecordEditor: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    let revision: EconomyStore.RecordRevision?
    @State private var drafts: [SegmentDraft]
    @State private var error: String?
    @State private var confirmSave = false
    init(revision: EconomyStore.RecordRevision?, wage: Int) {
        self.revision = revision
        let now = Date()
        _drafts = State(initialValue: revision?.segments.map {
            SegmentDraft(start: $0.start, end: $0.end ?? now, wage: String($0.hourlyWage))
        } ?? [SegmentDraft(start: now.addingTimeInterval(-3600), end: now, wage: String(wage))])
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("근무와 휴식을 시간 구간으로 나눠 입력해요. 휴식 구간의 시급은 0원이에요. 날짜가 바뀌어도 자동으로 나눠 계산해요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("직접 추가하거나 수정한 기록은 예상 수익에만 반영돼요. 추가 포인트는 없으며, 타이머로 이미 받은 포인트와 레벨은 유지돼요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach($drafts) { $draft in
                    Section(draft.wage == "0" ? "휴식 구간" : "근무 구간") {
                        DatePicker("시작", selection: $draft.start, in: ...Date())
                        DatePicker("종료", selection: $draft.end, in: ...Date())
                        HStack {
                            Text("시급")
                            TextField("0~1,000,000", text: $draft.wage).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                .accessibilityLabel("이 구간의 시급")
                            Text("원").foregroundStyle(.secondary)
                        }
                        if drafts.count > 1 {
                            Button("이 구간 삭제", role: .destructive) { drafts.removeAll { $0.id == draft.id } }
                        }
                    }
                }
                Section {
                    Button("구간 추가", systemImage: "plus") {
                        let end = drafts.last?.end ?? .now
                        drafts.append(SegmentDraft(start: end, end: max(end, Date()), wage: "0"))
                    }
                } footer: {
                    Text("구간은 겹칠 수 없고 한 기록은 최대 7일이에요. 수동 기록은 꾸미기 포인트를 적립하지 않아요.")
                }
            }
            .navigationTitle(revision == nil ? "놓친 근무 추가" : "근무 기록 수정").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("저장") { confirmSave = true }.bold() }
            }
            .confirmationDialog("근무 기록을 저장할까요?", isPresented: $confirmSave, titleVisibility: .visible) {
                Button("기록 저장") { save() }
            } message: { Text("근무 시간과 예상 수익에 반영돼요. 적립 포인트와 레벨은 바뀌지 않아요.") }
            .alert("기록을 저장하지 못했어요", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("확인") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        do {
            let segments = try drafts.map { draft -> WageSegment in
                guard let wage = Int(draft.wage) else { throw EconomyStore.StoreError.invalidRecord }
                return WageSegment(start: draft.start, end: draft.end, hourlyWage: wage)
            }
            if let revision {
                try session.economy.replaceRecord(revision: revision, segments: segments)
            } else {
                try session.economy.replaceRecord(nil, segments: segments)
            }
            session.refreshSnapshot()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
