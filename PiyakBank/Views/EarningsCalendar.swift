import SwiftUI
import SwiftData

/// 월 달력 + 근무 기록으로 계산한 일별 예상 수익 표시
struct EarningsCalendar: View {
    @Query private var records: [WorkSession]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedDate: Date
    private var displayedMonth: Date { selectedDate }

    private let cal = Calendar.current
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                DatePicker("선택 날짜", selection: $selectedDate, displayedComponents: .date)
                Text("날짜를 선택하면 해당 날짜의 근무 기록을 볼 수 있어요.")
                    .font(.caption).foregroundStyle(PB.C.secondary)
            } else {
                monthHeader
                weekdayRow
                dayGrid
            }
        }
        .padding(16)
        .background(PB.C.surface, in: RoundedRectangle(cornerRadius: PB.R.xl))
        .shadow(color: PB.C.textBrown.opacity(0.06), radius: 12, y: 4)
    }

    // MARK: 월 헤더 + 이동

    private var monthHeader: some View {
        HStack {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(PB.C.secondary).frame(width: 44, height: 44)
            }.accessibilityLabel("이전 달")
            Spacer()
            Text(displayedMonth, format: .dateTime.year().month()
                .locale(Locale(identifier: "ko_KR")))
                .font(PB.F.body(16)).bold()
                .foregroundStyle(PB.C.textBrown)
            Spacer()
            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(PB.C.secondary).frame(width: 44, height: 44)
            }.accessibilityLabel("다음 달")
        }
    }

    private func moveMonth(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: displayedMonth) {
            withAnimation(.spring(duration: 0.3)) { selectedDate = cal.date(from: cal.dateComponents([.year, .month], from: m)) ?? m }
        }
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(weekdays, id: \.self) { d in
                Text(d).font(PB.F.body(11))
                    .foregroundStyle(PB.C.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 날짜 그리드

    private var dayGrid: some View {
        let days = makeDays()
        let earnings = dailyEarned
        return LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 7), spacing: 6) {
            ForEach(days.indices, id: \.self) { i in
                if let day = days[i] {
                    dayCell(day, earned: earnings[cal.startOfDay(for: day)] ?? 0)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private func dayCell(_ day: Date, earned: Int) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selectedDate)
        let isToday = cal.isDateInToday(day)

        return Button {
            withAnimation(.spring(duration: 0.25)) { selectedDate = day }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(PB.F.body(13))
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(PB.C.textBrown)
                if earned > 0 {
                    Text(shortWon(earned))
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(PB.C.accent)
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text(" ").font(.system(size: 8))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                isSelected ? PB.C.brandYellow.opacity(0.45)
                : (isToday ? PB.C.brandYellow.opacity(0.15) : .clear),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), 예상 수익 \(earned.won), 진행 중인 근무 포함")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 표시 월의 날짜 배열 (앞쪽 빈칸은 nil)
    private func makeDays() -> [Date?] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth)),
              let range = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = cal.component(.weekday, from: monthStart)  // 1=일
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for d in range {
            days.append(cal.date(byAdding: .day, value: d - 1, to: monthStart))
        }
        return days
    }

    /// 일별 예상 수익 합. 포인트 원장과 분리하며 진행 중인 근무도 포함한다.
    private var dailyEarned: [Date: Int] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth)),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return [:] }
        var m: [Date: Int] = [:]
        let now = Date()
        for record in records where record.startedAt < monthEnd && (record.endedAt ?? now) > monthStart {
            for earning in EarningsCalculator.daily(record.segments, until: now)
                where earning.day >= monthStart && earning.day < monthEnd {
                m[cal.startOfDay(for: earning.day), default: 0] += earning.amount
            }
        }
        return m
    }

    /// 월 합계 (HistoryView에서 쓰도록 노출)
    var monthTotal: Int {
        dailyEarned.values.reduce(0, +)
    }

    private func shortWon(_ v: Int) -> String {
        if v >= 10_000 { return "\(v / 10_000)만+" }
        if v >= 1_000 { return "\(v / 1_000)천+" }
        return "\(v)"
    }
}
