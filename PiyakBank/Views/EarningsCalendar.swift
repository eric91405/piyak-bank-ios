import SwiftUI
import SwiftData

/// 월 달력 + 일별 적립 표시
struct EarningsCalendar: View {
    @Query private var txs: [PointTransaction]
    @Binding var selectedDate: Date
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: .now)

    private let cal = Calendar.current
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(spacing: 14) {
            monthHeader
            weekdayRow
            dayGrid
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: PB.R.xl))
        .shadow(color: PB.C.textBrown.opacity(0.06), radius: 12, y: 4)
    }

    // MARK: 월 헤더 + 이동

    private var monthHeader: some View {
        HStack {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(PB.C.textBrown.opacity(0.5))
            }
            Spacer()
            Text(displayedMonth, format: .dateTime.year().month()
                .locale(Locale(identifier: "ko_KR")))
                .font(PB.F.body(16)).bold()
                .foregroundStyle(PB.C.textBrown)
            Spacer()
            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(PB.C.textBrown.opacity(0.5))
            }
        }
    }

    private func moveMonth(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: displayedMonth) {
            withAnimation(.spring(duration: 0.3)) { displayedMonth = m }
        }
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(weekdays, id: \.self) { d in
                Text(d).font(PB.F.body(11))
                    .foregroundStyle(PB.C.textBrown.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 날짜 그리드

    private var dayGrid: some View {
        let days = makeDays()
        return LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 7), spacing: 6) {
            ForEach(days.indices, id: \.self) { i in
                if let day = days[i] {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let earned = dailyEarned[cal.startOfDay(for: day)] ?? 0
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
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(PB.C.coral)
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

    /// 일별 적립 합 (표시 월 한정, 한 번에 계산)
    private var dailyEarned: [Date: Int] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth)),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return [:] }
        var m: [Date: Int] = [:]
        for tx in txs where tx.kind == .accrual && tx.date >= monthStart && tx.date < monthEnd {
            let key = cal.startOfDay(for: tx.date)
            m[key, default: 0] += tx.amount
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
