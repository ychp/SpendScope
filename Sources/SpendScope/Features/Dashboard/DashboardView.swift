import Charts
import SwiftUI

struct DashboardView: View {
    let snapshot: DashboardSnapshot
    @State private var selectedRange = "7 天"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dashboardHeader
                summaryCards

                HStack(alignment: .top, spacing: 14) {
                    quotaCard.frame(maxWidth: .infinity)
                    modelCard.frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: 14) {
                    trendCard.frame(maxWidth: .infinity)
                    compositionCard.frame(width: 360)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 1040, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var dashboardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SpendScope").font(.largeTitle.bold())
                Text("Codex · \(snapshot.planName)  ·  \(snapshot.updatedText)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("时间范围", selection: $selectedRange) {
                ForEach(["今日", "7 天", "30 天", "全部"], id: \.self) {
                    Text($0)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 14) {
            metricCard("今日", snapshot.todayTokens, "waveform.path.ecg")
            metricCard("近 7 天", snapshot.sevenDayTokens, "calendar")
            metricCard("累计", snapshot.totalTokens, "square.stack.3d.up.fill")
        }
    }

    private func metricCard(_ title: String, _ value: Int, _ icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(SpendScopeTheme.accent)
                .font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).foregroundStyle(.secondary)
                Text(TokenFormatter.compact(value))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .dashboardCard()
    }

    private var quotaCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("额度状态").font(.headline)
            HStack(spacing: 36) {
                ForEach(snapshot.quotas) { quota in
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 9)
                            Circle()
                                .trim(from: 0, to: quota.remaining)
                                .stroke(
                                    SpendScopeTheme.accent.gradient,
                                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                            VStack {
                                Text(quota.title).font(.caption)
                                Text("\(quota.remainingPercent)%").font(.title.bold())
                                Text("剩余").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 118, height: 118)
                        Text(quota.resetText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .dashboardCard()
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("模型分布").font(.headline)
            ForEach(snapshot.models) { model in
                VStack(spacing: 8) {
                    HStack {
                        Text(model.name)
                        Spacer()
                        Text("\(Int(model.share * 100))%").monospacedDigit()
                    }
                    ProgressView(value: model.share).tint(SpendScopeTheme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .dashboardCard()
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            .frame(height: 260)
        }
        .dashboardCard()
    }

    private var compositionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Token 构成").font(.headline)
            ForEach(breakdownItems) { item in
                VStack(spacing: 7) {
                    HStack {
                        Circle().fill(item.color).frame(width: 9, height: 9)
                        Text(item.title)
                        Spacer()
                        Text(TokenFormatter.compact(item.value)).monospacedDigit()
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
        .dashboardCard()
    }

    private var breakdownItems: [BreakdownDisplayItem] {
        [
            BreakdownDisplayItem(id: "input", title: "输入", value: snapshot.breakdown.input, color: SpendScopeTheme.accent),
            BreakdownDisplayItem(id: "cached", title: "缓存输入", value: snapshot.breakdown.cachedInput, color: SpendScopeTheme.accentBlue),
            BreakdownDisplayItem(id: "output", title: "输出", value: snapshot.breakdown.output, color: SpendScopeTheme.output),
            BreakdownDisplayItem(id: "reasoning", title: "推理", value: snapshot.breakdown.reasoning, color: SpendScopeTheme.reasoning)
        ]
    }
}

private struct BreakdownDisplayItem: Identifiable {
    let id: String
    let title: String
    let value: Int
    let color: Color
}
