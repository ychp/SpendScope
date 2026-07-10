import Charts
import SwiftUI

struct DashboardView: View {
    let snapshot: DashboardSnapshot
    @State private var selectedRange = "7 天"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            dashboardHeader
            overviewCard.frame(height: 190)
            HStack(alignment: .top, spacing: 10) {
                trendCard.frame(maxWidth: .infinity, maxHeight: .infinity)
                compositionCard
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(minWidth: 920, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var dashboardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SpendScope").font(.title.bold())
                Text("Codex · \(snapshot.planName)  ·  \(snapshot.updatedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("时间范围", selection: $selectedRange) {
                ForEach(["今日", "7 天", "30 天", "全部"], id: \.self) {
                    Text($0)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
    }

    private var overviewCard: some View {
        HStack(spacing: 14) {
            currentQuotaSection.frame(width: 330)
            Divider()
            periodMetricsSection
        }
        .dashboardCard(padding: 12)
    }

    private var currentQuotaSection: some View {
        HStack(spacing: 14) {
            ZStack {
                quotaRing(
                    snapshot.quotas[0],
                    diameter: 138,
                    lineWidth: 10,
                    color: SpendScopeTheme.accent
                )
                quotaRing(
                    snapshot.quotas[1],
                    diameter: 92,
                    lineWidth: 8,
                    color: SpendScopeTheme.accentBlue
                )
                VStack(spacing: 1) {
                    Text("当前额度").font(.caption2).foregroundStyle(.secondary)
                    Text(snapshot.planName).font(.headline)
                }
            }
            .frame(width: 142, height: 142)

            VStack(alignment: .leading, spacing: 12) {
                quotaLegend(snapshot.quotas[0], color: SpendScopeTheme.accent)
                quotaLegend(snapshot.quotas[1], color: SpendScopeTheme.accentBlue)
            }
        }
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

    private func quotaLegend(_ quota: QuotaSnapshot, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(quota.title).font(.caption.bold())
            }
            Text("\(quota.remainingPercent)% 剩余")
                .font(.callout.bold())
                .monospacedDigit()
            Text(quota.resetText).font(.caption2).foregroundStyle(.secondary)
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
        .frame(maxWidth: .infinity)
    }

    private func periodTile(_ period: PeriodUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(period.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(TokenFormatter.compact(period.total))
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 6) {
                periodMetric("输入", period.uncachedInput, SpendScopeTheme.accent)
                periodMetric("缓存", period.cachedInput, SpendScopeTheme.accentBlue)
                periodMetric("输出", period.visibleOutput, SpendScopeTheme.output)
                periodMetric("推理", period.reasoning, SpendScopeTheme.reasoning)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06))
        }
    }

    private func periodMetric(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Text(TokenFormatter.compact(value))
                .font(.caption2)
                .monospacedDigit()
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token 趋势").font(.headline)
            Chart(snapshot.dailyUsage) { item in
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
            .frame(height: 180)
        }
        .dashboardCard(padding: 12)
    }

    private var compositionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token 构成").font(.headline)
            ForEach(breakdownItems) { item in
                VStack(spacing: 5) {
                    HStack {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                        Text(item.title).font(.caption)
                        Spacer()
                        Text(TokenFormatter.compact(item.value))
                            .font(.caption)
                            .monospacedDigit()
                    }
                    ProgressView(
                        value: Double(item.value),
                        total: Double(snapshot.breakdown.total)
                    )
                    .tint(item.color)
                }
            }
            Spacer(minLength: 0)
        }
        .dashboardCard(padding: 12)
    }

    private var breakdownItems: [BreakdownDisplayItem] {
        [
            BreakdownDisplayItem(
                id: "input",
                title: "未缓存输入",
                value: snapshot.breakdown.input,
                color: SpendScopeTheme.accent
            ),
            BreakdownDisplayItem(
                id: "cached",
                title: "缓存输入",
                value: snapshot.breakdown.cachedInput,
                color: SpendScopeTheme.accentBlue
            ),
            BreakdownDisplayItem(
                id: "output",
                title: "可见输出",
                value: snapshot.breakdown.output,
                color: SpendScopeTheme.output
            ),
            BreakdownDisplayItem(
                id: "reasoning",
                title: "推理输出",
                value: snapshot.breakdown.reasoning,
                color: SpendScopeTheme.reasoning
            )
        ]
    }
}

private struct BreakdownDisplayItem: Identifiable {
    let id: String
    let title: String
    let value: Int
    let color: Color
}
