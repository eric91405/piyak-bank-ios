import WidgetKit
import SwiftUI

struct PiyakEntry: TimelineEntry {
    let date: Date
    let snapshot: SessionSnapshot
}

struct PiyakProvider: TimelineProvider {
    func placeholder(in context: Context) -> PiyakEntry { .init(date: .now, snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (PiyakEntry) -> Void) {
        completion(.init(date: .now, snapshot: read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PiyakEntry>) -> Void) {
        let snapshot = read()
        let now = Date()
        // Precomputed five-minute estimates; the system controls actual refresh timing.
        let entries = (0..<72).map { PiyakEntry(date: now.addingTimeInterval(Double($0 * 300)), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
    private func read() -> SessionSnapshot {
        guard let data = AppConfig.shared?.data(forKey: AppConfig.kSnapshot),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data) else { return .empty }
        return snapshot
    }
}

struct PiyakComplicationView: View {
    let entry: PiyakEntry
    @Environment(\.widgetFamily) var family
    private var amount: Int { entry.snapshot.today(at: entry.date) }
    private var status: String { entry.snapshot.isPaused ? "쉬는 중" : (entry.snapshot.isRunning ? "근무 중" : "대기 중") }
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("삐약 · 오늘 약 \(amount.won)")
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: entry.snapshot.isPaused ? "pause.fill" : "sun.max.fill")
                    Text(amount >= 10_000 ? String(format: "%.1f만", Double(amount) / 10_000) : amount.grouped)
                        .font(.caption2.bold()).minimumScaleFactor(0.6)
                }.accessibilityLabel("오늘 예상 수익 \(amount.won), \(status)")
            default:
                VStack(alignment: .leading, spacing: 5) {
                    Label("삐약뱅크", systemImage: "sun.max.fill").font(.caption.bold())
                    Text("오늘 예상 수익").font(.caption2).foregroundStyle(.secondary)
                    Text(amount.won).font(.system(.title3, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("\(status) · 5분 단위 예상치").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { Color(red: 0.99, green: 0.91, blue: 0.49) }
        .widgetURL(URL(string: "piyakbank://home"))
    }
}

@main
struct PiyakComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConfig.widgetKind, provider: PiyakProvider()) { PiyakComplicationView(entry: $0) }
            .configurationDisplayName("삐약뱅크")
            .description("오늘의 예상 수익과 근무 상태를 확인해요. 금액은 5분 단위 예상치예요.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}
