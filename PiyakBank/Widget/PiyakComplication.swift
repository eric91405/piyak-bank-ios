import WidgetKit
import SwiftUI

// AppGroup 공유 스냅샷을 읽어 표시하는 컴플리케이션/위젯

struct PiyakEntry: TimelineEntry {
    let date: Date
    let accrued: Int
    let isRunning: Bool
}

struct PiyakProvider: TimelineProvider {
    private let defaults = AppConfig.shared

    func placeholder(in context: Context) -> PiyakEntry {
        PiyakEntry(date: .now, accrued: 0, isRunning: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (PiyakEntry) -> Void) {
        completion(readEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PiyakEntry>) -> Void) {
        let entry = readEntry()
        // 적립 중이면 1분 후 갱신, 아니면 멀리
        let next = Calendar.current.date(byAdding: .minute,
                                         value: entry.isRunning ? 1 : 60, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> PiyakEntry {
        guard let data = defaults?.data(forKey: AppConfig.kSnapshot),
              let snap = try? JSONDecoder().decode(SessionSnapshot.self, from: data) else {
            return PiyakEntry(date: .now, accrued: 0, isRunning: false)
        }
        return PiyakEntry(date: .now, accrued: snap.accrued, isRunning: snap.isRunning)
    }
}

struct PiyakComplicationView: View {
    var entry: PiyakEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack { Text("🐤").font(.caption); Text(short(entry.accrued)).font(.caption2.bold()) }
        case .accessoryInline:
            Text("🐤 \(entry.accrued.won)")
        default:
            VStack(alignment: .leading) {
                Text("🐤 삐약뱅크").font(.caption2).foregroundStyle(.secondary)
                Text(entry.accrued.won).font(.headline)
            }.padding(8)
        }
    }
    private func short(_ v: Int) -> String { v >= 10000 ? "\(v/10000)만" : "\(v)" }
}

@main
struct PiyakComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PiyakComplication", provider: PiyakProvider()) {
            PiyakComplicationView(entry: $0)
        }
        .configurationDisplayName("삐약뱅크")
        .description("지금까지 모은 금액")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

// SessionSnapshot은 메인 타깃 SessionController.swift에 정의 — 위젯 타깃 멤버십에도 추가 필요
