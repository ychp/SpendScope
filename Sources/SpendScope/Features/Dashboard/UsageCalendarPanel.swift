import Foundation
import SwiftUI

struct UsageCalendarCell: Identifiable {
    let id: String
    let date: Date
    let dayNumber: Int
    let isInDisplayedMonth: Bool
    let isFuture: Bool
    let isToday: Bool
    let usage: DailyUsage?
}

struct UsageCalendarModel {
    let calendar: Calendar
    let today: Date
    let earliestMonth: Date
    let latestMonth: Date

    private let usageByID: [String: DailyUsage]

    init(usage: [DailyUsage], calendar: Calendar = .current, today: Date = Date()) {
        var normalizedCalendar = calendar
        normalizedCalendar.firstWeekday = 2
        self.calendar = normalizedCalendar
        self.today = normalizedCalendar.startOfDay(for: today)

        var indexedUsage: [String: DailyUsage] = [:]
        for item in usage {
            indexedUsage[item.id] = item
        }
        usageByID = indexedUsage

        let currentMonth = Self.monthStart(for: today, calendar: normalizedCalendar)
        latestMonth = currentMonth
        let earliestUsageDate = usage
            .filter { $0.total > 0 }
            .compactMap { Self.date(forID: $0.id, calendar: normalizedCalendar) }
            .min()
        let candidate = earliestUsageDate.map {
            Self.monthStart(for: $0, calendar: normalizedCalendar)
        } ?? currentMonth
        earliestMonth = min(candidate, currentMonth)
    }

    func cells(for month: Date) -> [UsageCalendarCell] {
        let displayedMonth = clampedMonth(month)
        let weekday = calendar.component(.weekday, from: displayedMonth)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(
            byAdding: .day,
            value: -leadingDays,
            to: displayedMonth
        ) else {
            return []
        }

        let displayedComponents = calendar.dateComponents([.year, .month], from: displayedMonth)
        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            let day = calendar.startOfDay(for: date)
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            guard let dayNumber = components.day else { return nil }
            let id = Self.dayID(for: day, calendar: calendar)
            return UsageCalendarCell(
                id: id,
                date: day,
                dayNumber: dayNumber,
                isInDisplayedMonth: components.year == displayedComponents.year
                    && components.month == displayedComponents.month,
                isFuture: calendar.compare(day, to: today, toGranularity: .day) == .orderedDescending,
                isToday: calendar.isDate(day, inSameDayAs: today),
                usage: usageByID[id]
            )
        }
    }

    func clampedMonth(_ month: Date) -> Date {
        let start = Self.monthStart(for: month, calendar: calendar)
        return min(max(start, earliestMonth), latestMonth)
    }

    func movingMonth(_ month: Date, by offset: Int) -> Date {
        guard let candidate = calendar.date(
            byAdding: .month,
            value: offset,
            to: Self.monthStart(for: month, calendar: calendar)
        ) else {
            return clampedMonth(month)
        }
        return clampedMonth(candidate)
    }

    func canMoveMonth(_ month: Date, by offset: Int) -> Bool {
        let current = Self.monthStart(for: month, calendar: calendar)
        guard let candidate = calendar.date(byAdding: .month, value: offset, to: current) else {
            return false
        }
        return candidate >= earliestMonth && candidate <= latestMonth
    }

    static func intensity(total: Int, maximum: Int) -> Int {
        guard total > 0, maximum > 0 else { return 0 }
        let normalized = log1p(Double(total)) / log1p(Double(maximum))
        switch normalized {
        case ..<0.25: return 1
        case ..<0.50: return 2
        case ..<0.75: return 3
        default: return 4
        }
    }

    static func date(forID id: String, calendar: Calendar) -> Date? {
        let parts = id.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        var startComponents = DateComponents()
        startComponents.calendar = calendar
        startComponents.timeZone = calendar.timeZone
        startComponents.year = components.year
        startComponents.month = components.month
        startComponents.day = 1
        startComponents.hour = 12
        let midday = calendar.date(from: startComponents) ?? date
        return calendar.startOfDay(for: midday)
    }

    private static func dayID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

struct UsageCalendarPanel: View {
    private static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    let usage: [DailyUsage]
    let calendar: Calendar
    let today: Date

    @State private var displayedMonth: Date
    @State private var hoveredUsageID: DailyUsage.ID?

    init(usage: [DailyUsage], calendar: Calendar = .current, today: Date = Date()) {
        let model = UsageCalendarModel(usage: usage, calendar: calendar, today: today)
        self.usage = usage
        self.calendar = calendar
        self.today = today
        _displayedMonth = State(initialValue: model.latestMonth)
    }

    private var model: UsageCalendarModel {
        UsageCalendarModel(usage: usage, calendar: calendar, today: today)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    var body: some View {
        let month = model.clampedMonth(displayedMonth)
        let cells = model.cells(for: month)
        let maximum = cells
            .filter { $0.isInDisplayedMonth && !$0.isFuture }
            .compactMap(\.usage?.total)
            .max() ?? 0

        VStack(spacing: 7) {
            calendarHeader(month)
            weekdayHeader

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cells) { cell in
                    dayCell(cell, maximum: maximum)
                }
            }

            heatLegend
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardPanel(padding: 14)
        .onChange(of: usage.first?.id) { _, _ in
            displayedMonth = model.clampedMonth(displayedMonth)
        }
    }

    private func calendarHeader(_ month: Date) -> some View {
        HStack(spacing: 6) {
            Label("用量日历", systemImage: "calendar")
                .font(.system(size: 14, weight: .semibold))

            Spacer(minLength: 4)

            monthButton(systemImage: "chevron.left", offset: -1, month: month)

            Text(monthTitle(month))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.88))
                .monospacedDigit()
                .frame(minWidth: 72)

            monthButton(systemImage: "chevron.right", offset: 1, month: month)
        }
        .frame(height: 26)
    }

    private func monthButton(systemImage: String, offset: Int, month: Date) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredUsageID = nil
                displayedMonth = model.movingMonth(month, by: offset)
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
        .disabled(!model.canMoveMonth(month, by: offset))
        .opacity(model.canMoveMonth(month, by: offset) ? 1 : 0.32)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Self.weekdays, id: \.self) { weekday in
                Text(weekday)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("星期一到星期日")
    }

    @ViewBuilder
    private func dayCell(_ cell: UsageCalendarCell, maximum: Int) -> some View {
        let level = UsageCalendarModel.intensity(total: cell.usage?.total ?? 0, maximum: maximum)
        let base = Text("\(cell.dayNumber)")
            .font(.system(size: 10, weight: cell.isToday ? .semibold : .medium, design: .rounded))
            .foregroundStyle(dayTextColor(for: cell, level: level))
            .monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 27, maxHeight: 27)
            .background(
                dayFillColor(for: cell, level: level),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        cell.isToday
                            ? (level >= 3 ? Color.white.opacity(0.94) : SpendScopeTheme.dashboardAccent)
                            : SpendScopeTheme.dashboardBorder.opacity(0.55),
                        lineWidth: cell.isToday ? 1.5 : 0.7
                    )
            }

        if cell.isInDisplayedMonth,
           !cell.isFuture,
           let item = cell.usage {
            base
                .onHover { active in
                    if active {
                        hoveredUsageID = item.id
                    } else if hoveredUsageID == item.id {
                        hoveredUsageID = nil
                    }
                }
                .popover(
                    isPresented: hoverBinding(for: item.id),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    DailyUsageHoverCard(usage: item, dateText: item.id)
                        .padding(4)
                }
                .accessibilityLabel("\(item.id)，Token \(item.total)")
        } else {
            base
                .accessibilityLabel(cell.isFuture ? "\(cell.dayNumber)日，未来日期" : "\(cell.dayNumber)日")
        }
    }

    private var heatLegend: some View {
        HStack(spacing: 7) {
            Spacer()
            Text("低")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)

            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(heatColor(level: level))
                    .frame(width: 16, height: 10)
            }

            Text("高")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            Spacer()
        }
        .frame(height: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("用量颜色，低到高")
    }

    private func dayFillColor(for cell: UsageCalendarCell, level: Int) -> Color {
        guard cell.isInDisplayedMonth else {
            return SpendScopeTheme.dashboardControlBackground.opacity(0.28)
        }
        guard !cell.isFuture else {
            return SpendScopeTheme.dashboardControlBackground.opacity(0.42)
        }
        guard level > 0 else {
            return SpendScopeTheme.dashboardAccent.opacity(0.055)
        }
        return heatColor(level: level)
    }

    private func dayTextColor(for cell: UsageCalendarCell, level: Int) -> Color {
        if !cell.isInDisplayedMonth || cell.isFuture {
            return SpendScopeTheme.dashboardMutedText.opacity(0.48)
        }
        return level == 4 ? .white : SpendScopeTheme.dashboardPrimaryText.opacity(0.82)
    }

    private func heatColor(level: Int) -> Color {
        let opacity: Double
        switch level {
        case 1: opacity = 0.16
        case 2: opacity = 0.28
        case 3: opacity = 0.46
        default: opacity = 0.82
        }
        return SpendScopeTheme.dashboardAccent.opacity(opacity)
    }

    private func hoverBinding(for id: DailyUsage.ID) -> Binding<Bool> {
        Binding(
            get: { hoveredUsageID == id },
            set: { isPresented in
                if !isPresented, hoveredUsageID == id {
                    hoveredUsageID = nil
                }
            }
        )
    }

    private func monthTitle(_ month: Date) -> String {
        let components = model.calendar.dateComponents([.year, .month], from: month)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }
}

struct DailyUsageHoverCard: View {
    let usage: DailyUsage
    let dateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dateText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)

                Spacer(minLength: 8)

                Text("总 Token")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                Text(TokenFormatter.compact(usage.total))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpendScopeTheme.dashboardPrimaryText)
                    .monospacedDigit()
            }

            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder.opacity(0.8))
                .frame(height: 1)

            HStack(spacing: 10) {
                metric("输入", value: usage.uncachedInput, color: SpendScopeTheme.dashboardInput)
                metric("缓存", value: usage.cachedInput, color: SpendScopeTheme.dashboardCachedInput)
            }

            HStack(spacing: 10) {
                metric("输出", value: usage.output, color: SpendScopeTheme.output)
                metric("推理", value: usage.reasoning, color: SpendScopeTheme.reasoning)
            }
        }
        .frame(width: 174)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            SpendScopeTheme.dashboardSurface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder)
        }
        .shadow(color: SpendScopeTheme.dashboardShadow, radius: 7, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(dateText)，总 Token \(usage.total)，输入 \(usage.uncachedInput)，缓存 \(usage.cachedInput)，输出 \(usage.output)，推理 \(usage.reasoning)"
        )
    }

    private func metric(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            Spacer(minLength: 2)
            Text(TokenFormatter.compact(value))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.86))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }
}
