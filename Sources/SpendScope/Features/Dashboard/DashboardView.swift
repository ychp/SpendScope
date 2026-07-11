import Charts
import SwiftUI

struct DashboardView: View {
    let snapshot: DashboardSnapshot
    @State private var selectedRange = TrendRange.defaultRange

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            dashboardHeader
            overviewCard.frame(height: 260)
            trendCard.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 920, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SpendScope").font(.title.bold())
            Text("Codex · \(snapshot.planName)  ·  \(snapshot.updatedText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewCard: some View {
        HStack(spacing: 14) {
            currentQuotaSection.frame(width: 340)
            Divider()
            periodMetricsSection
        }
        .dashboardCard(padding: 12)
    }

    private var currentQuotaSection: some View {
        VStack(spacing: 8) {
            ZStack {
                quotaRing(
                    snapshot.quotas[0],
                    diameter: 174,
                    lineWidth: 11,
                    color: SpendScopeTheme.accent
                )
                quotaRing(
                    snapshot.quotas[1],
                    diameter: 124,
                    lineWidth: 9,
                    color: SpendScopeTheme.accentBlue
                )
                VStack(spacing: 5) {
                    quotaCenterLabel(snapshot.quotas[0])
                    quotaCenterLabel(snapshot.quotas[1])
                }
            }
            .frame(width: 178, height: 178)

            VStack(alignment: .leading, spacing: 3) {
                quotaResetRow(snapshot.quotas[0], color: SpendScopeTheme.accent)
                quotaResetRow(snapshot.quotas[1], color: SpendScopeTheme.accentBlue)
            }
            .frame(width: 178, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func quotaCenterLabel(_ quota: QuotaSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(quota.compactTitle)
                .font(.system(size: 13, weight: .semibold))
            Text("\(quota.remainingPercent)%")
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quota.remainingLabel)
    }

    private func quotaRing(
        _ quota: QuotaSnapshot,
        diameter: CGFloat,
        lineWidth: CGFloat,
        color: Color
    ) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: quota.remaining)
                .stroke(
                    color.gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private func quotaResetRow(_ quota: QuotaSnapshot, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(quota.compactTitle)
                .font(.caption.bold())
                .frame(width: 20, alignment: .leading)
            Text(quota.resetText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var periodGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
    }

    private var periodMetricsSection: some View {
        LazyVGrid(columns: periodGridColumns, spacing: 8) {
            ForEach(snapshot.periods) { period in
                periodTile(period)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var periodMetricGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private func periodTile(_ period: PeriodUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(period.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(TokenFormatter.compact(period.total))
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
            }

            LazyVGrid(columns: periodMetricGridColumns, alignment: .leading, spacing: 3) {
                periodMetric(
                    "输入",
                    value: period.uncachedInput,
                    share: period.share(of: period.uncachedInput),
                    color: SpendScopeTheme.accent
                )
                periodMetric(
                    "缓存",
                    value: period.cachedInput,
                    share: period.share(of: period.cachedInput),
                    color: SpendScopeTheme.accentBlue
                )
                periodMetric(
                    "输出",
                    value: period.visibleOutput,
                    share: period.share(of: period.visibleOutput),
                    color: SpendScopeTheme.output
                )
                periodMetric(
                    "推理",
                    value: period.reasoning,
                    share: period.share(of: period.reasoning),
                    color: SpendScopeTheme.reasoning
                )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06))
        }
    }

    private func periodMetric(
        _ title: String,
        value: Int,
        share: Double,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(TokenFormatter.compact(value))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                Text(TokenFormatter.percentage(share))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * share)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title) \(TokenFormatter.compact(value))，占当前周期 \(TokenFormatter.percentage(share))"
        )
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Token 趋势").font(.headline)
                Spacer()
                Picker("时间范围", selection: $selectedRange) {
                    ForEach(TrendRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            Chart(selectedRange.select(from: snapshot.dailyUsage)) { item in
                AreaMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(SpendScopeTheme.accent.opacity(0.12))

                LineMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(SpendScopeTheme.accent)
                .lineStyle(StrokeStyle(lineWidth: 3))

                PointMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(SpendScopeTheme.accent)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(TokenFormatter.compact(tokens))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dashboardCard(padding: 12)
    }
}
