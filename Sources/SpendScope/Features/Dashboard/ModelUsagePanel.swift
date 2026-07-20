import SwiftUI

struct ModelUsagePanel: View {
    let ranking: ModelUsageRanking

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder)
                .frame(height: 1)

            if ranking.entries.isEmpty {
                ContentUnavailableView(
                    "暂无模型用量",
                    systemImage: "cpu",
                    description: Text("使用 Codex 后会按模型统计 Token 和 API 等值费用。")
                )
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(ranking.entries.enumerated()), id: \.element.id) { index, entry in
                            modelRow(entry, rank: index + 1)
                            if index < ranking.entries.count - 1 {
                                Rectangle()
                                    .fill(SpendScopeTheme.dashboardBorder.opacity(0.72))
                                    .frame(height: 1)
                                    .padding(.leading, 42)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            SpendScopeTheme.dashboardSurfaceStrong.opacity(0.74),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SpendScopeTheme.dashboardAccent)
            Text("模型用量排行")
                .font(.system(size: 13, weight: .semibold))

            if ranking.unpricedModelCount > 0 {
                Text("\(ranking.unpricedModelCount) 个模型暂无定价")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            }

            Spacer()

            Text("总用量")
                .frame(width: 84, alignment: .trailing)
            Text("预估费用总额")
                .frame(width: 96, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
        .frame(height: 30)
        .padding(.horizontal, 12)
    }

    private func modelRow(_ entry: ModelUsageEntry, rank: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    rank <= 3 ? SpendScopeTheme.dashboardAccent : SpendScopeTheme.dashboardMutedText
                )
                .frame(width: 22, height: 22)
                .background(
                    SpendScopeTheme.dashboardControlBackground,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            HStack(spacing: 5) {
                Text(entry.model)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                ModelPricingInfoButton(modelID: entry.model)
            }
            .frame(width: 205, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(SpendScopeTheme.dashboardControlBackground)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    SpendScopeTheme.dashboardAccent,
                                    SpendScopeTheme.dashboardAccentSecondary
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(5, geometry.size.width * entry.share))
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
            }
            .frame(minWidth: 100, maxWidth: .infinity, minHeight: 22)

            ModelTokenValue(entry: entry)
                .frame(width: 84, alignment: .trailing)

            ModelCostValue(entry: entry)
                .frame(width: 96, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel(for: entry, rank: rank))
    }

    private func accessibilityLabel(for entry: ModelUsageEntry, rank: Int) -> String {
        let cost = entry.estimatedCostUSD.map(ModelCostFormatter.usd) ?? "暂无官方定价"
        return "第 \(rank) 名，\(entry.model)，\(entry.totalTokens) Token，API 预估 \(cost)"
    }
}

private struct ModelTokenValue: View {
    let entry: ModelUsageEntry
    @State private var isHovered = false

    var body: some View {
        Text(TokenFormatter.compact(entry.totalTokens))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.9))
            .monospacedDigit()
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .popover(
                isPresented: $isHovered,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                ModelTokenDetailCard(entry: entry)
                    .padding(4)
            }
            .help("悬浮查看 Token 明细")
    }
}

private struct ModelCostValue: View {
    let entry: ModelUsageEntry
    @State private var isHovered = false

    var body: some View {
        Text(entry.estimatedCostUSD.map(ModelCostFormatter.usd) ?? "—")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(
                entry.estimatedCostUSD == nil
                    ? SpendScopeTheme.dashboardMutedText
                    : SpendScopeTheme.dashboardAccent
            )
            .monospacedDigit()
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .popover(
                isPresented: $isHovered,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                ModelCostDetailCard(entry: entry)
                    .padding(4)
            }
            .help("悬浮查看费用明细")
    }
}

private struct ModelPricingInfoButton: View {
    let modelID: String
    @State private var isHovered = false
    @State private var isPinned = false

    var body: some View {
        Button {
            isPinned.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardAccent)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(
            isPresented: presentationBinding,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            ModelPricingRuleCard(modelID: modelID)
                .padding(4)
        }
        .help("查看 \(modelID) API 费用规则")
        .accessibilityLabel("\(modelID) API 费用规则")
    }

    private var presentationBinding: Binding<Bool> {
        Binding(
            get: { isHovered || isPinned },
            set: { presented in
                if !presented {
                    isHovered = false
                    isPinned = false
                }
            }
        )
    }
}

private struct ModelTokenDetailCard: View {
    let entry: ModelUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\(entry.model) · Token 明细")
                .font(.system(size: 12, weight: .semibold))
            detailRow("未缓存输入", value: TokenFormatter.compact(entry.uncachedInputTokens))
            detailRow("缓存输入", value: TokenFormatter.compact(entry.cachedInputTokens))
            detailRow("可见输出", value: TokenFormatter.compact(entry.visibleOutputTokens))
            detailRow("推理输出", value: TokenFormatter.compact(entry.reasoningTokens))
            Divider()
            detailRow("总用量", value: TokenFormatter.compact(entry.totalTokens), emphasized: true)
        }
        .modelDetailCard()
    }
}

private struct ModelCostDetailCard: View {
    let entry: ModelUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\(entry.model) · 预估费用")
                .font(.system(size: 12, weight: .semibold))

            if let rule = ModelPricingCatalog.rule(for: entry.model),
               let total = entry.estimatedCostUSD {
                costRow("未缓存输入", tokens: entry.uncachedInputTokens, rate: rule.inputPerMillionUSD)
                costRow("缓存输入", tokens: entry.cachedInputTokens, rate: rule.cachedInputPerMillionUSD)
                costRow("可见输出", tokens: entry.visibleOutputTokens, rate: rule.outputPerMillionUSD)
                costRow("推理输出", tokens: entry.reasoningTokens, rate: rule.outputPerMillionUSD)
                Divider()
                detailRow("API 等值总额", value: ModelCostFormatter.usd(total), emphasized: true)
                Text("按标准 API 单价估算，不代表 Codex 实际账单；未计长上下文、缓存写入和工具调用附加费。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("暂无公开的独立 API 单价", systemImage: "exclamationmark.circle")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                Text("该模型的 Token 不计入费用预估。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            }
        }
        .modelDetailCard()
    }

    private func costRow(_ title: String, tokens: Int, rate: Double) -> some View {
        detailRow(
            title,
            value: "\(TokenFormatter.compact(tokens)) × \(ModelCostFormatter.rate(rate)) = "
                + ModelCostFormatter.usd(Double(tokens) / 1_000_000 * rate)
        )
    }
}

private struct ModelPricingRuleCard: View {
    let modelID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\(modelID) · API 费用规则")
                .font(.system(size: 12, weight: .semibold))

            if let rule = ModelPricingCatalog.rule(for: modelID) {
                Text("标准价格 · 每 100 万 Token")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                detailRow("输入", value: ModelCostFormatter.rate(rule.inputPerMillionUSD))
                detailRow("缓存输入", value: ModelCostFormatter.rate(rule.cachedInputPerMillionUSD))
                detailRow("输出 / 推理", value: ModelCostFormatter.rate(rule.outputPerMillionUSD))

                if let threshold = rule.longContextThresholdTokens,
                   let inputMultiplier = rule.longContextInputMultiplier,
                   let outputMultiplier = rule.longContextOutputMultiplier {
                    Divider()
                    Text(
                        "单次输入超过 \(TokenFormatter.compact(threshold)) 时，整次请求输入按 "
                            + "\(inputMultiplier.formatted())×、输出按 \(outputMultiplier.formatted())× 计价。"
                    )
                    .font(.system(size: 9.5))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let cacheWriteMultiplier = rule.cacheWriteMultiplier {
                    Text("缓存写入按普通输入价的 \(cacheWriteMultiplier.formatted())× 计价。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                }
            } else {
                Label("暂无公开的独立 API 单价", systemImage: "exclamationmark.circle")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                Text(unknownPricingDescription)
                    .font(.system(size: 9.5))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Link(
                "查看 OpenAI 官方价格",
                destination: URL(string: "https://openai.com/api/pricing/")!
            )
            .font(.system(size: 9.5, weight: .medium))
        }
        .modelDetailCard()
    }

    private var unknownPricingDescription: String {
        if modelID.lowercased() == "codex-auto-review" {
            return "这是 Codex 自动审批审查使用的内部路由名称，官方未公布可独立套用的模型单价。"
        }
        return "当前价格目录尚未收录该模型，费用估算中会保留为未定价。"
    }
}

private func detailRow(_ title: String, value: String, emphasized: Bool = false) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(title)
            .foregroundStyle(
                emphasized
                    ? SpendScopeTheme.dashboardPrimaryText
                    : SpendScopeTheme.dashboardMutedText
            )
        Spacer(minLength: 12)
        Text(value)
            .fontWeight(emphasized ? .semibold : .medium)
            .foregroundStyle(
                emphasized
                    ? SpendScopeTheme.dashboardAccent
                    : SpendScopeTheme.dashboardPrimaryText
            )
            .monospacedDigit()
    }
    .font(.system(size: 10.5))
}

private extension View {
    func modelDetailCard() -> some View {
        padding(12)
            .frame(width: 310, alignment: .leading)
            .background(SpendScopeVisualEffect(style: .popover))
    }
}
