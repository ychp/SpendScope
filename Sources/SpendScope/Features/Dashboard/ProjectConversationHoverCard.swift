import SwiftUI

struct ProjectConversationHoverCard: View {
    let conversation: ProjectConversationUsage

    var body: some View {
        let totals = tokenTotals
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                    .frame(width: 30, height: 30)
                    .background(
                        SpendScopeTheme.dashboardAccent.opacity(0.10),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("任务调用详情")
                        .font(.system(size: 13, weight: .semibold))
                    Text(
                        ProjectUsageDateFormatter.relative(
                            conversation.lastMessageAtMilliseconds
                        )
                    )
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                    .monospacedDigit()
                }

                Spacer()

                Text("\(TokenFormatter.compact(conversation.tokens)) Token")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                    .monospacedDigit()
                    .padding(.horizontal, 9)
                    .frame(height: 23)
                    .background(
                        SpendScopeTheme.dashboardAccent.opacity(0.09),
                        in: Capsule()
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.displayTitle ?? conversation.shortThreadID)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("任务标识 \(conversation.shortThreadID)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("模型调用", systemImage: "cpu")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                Spacer(minLength: 8)
                Text(modelText)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.90))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                SpendScopeTheme.dashboardAccent.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

            HStack(spacing: 8) {
                summary(
                    title: "回复",
                    count: conversation.replies.count,
                    icon: "bubble.left.fill",
                    tint: SpendScopeTheme.accent
                )
                summary(
                    title: "Skills",
                    count: skillCallCount,
                    icon: "sparkles",
                    tint: SpendScopeTheme.dashboardInput
                )
                summary(
                    title: "Tools",
                    count: toolCallCount,
                    icon: "wrench.and.screwdriver.fill",
                    tint: SpendScopeTheme.dashboardAccentSecondary
                )
            }

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    activitySection(
                        title: "Skills 调用",
                        icon: "sparkles",
                        tint: SpendScopeTheme.dashboardInput,
                        calls: conversation.skillCalls
                    )
                    activitySection(
                        title: "Tools 调用",
                        icon: "wrench.and.screwdriver.fill",
                        tint: SpendScopeTheme.dashboardAccentSecondary,
                        calls: conversation.toolCalls
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 110, maxHeight: 380)
            .scrollIndicators(.visible)

            Divider()

            Text(
                "Token  输入 \(TokenFormatter.compact(totals.uncachedInput))"
                    + " · 缓存 \(TokenFormatter.compact(totals.cachedInput))"
                    + " · 输出 \(TokenFormatter.compact(totals.visibleOutput))"
                    + " · 推理 \(TokenFormatter.compact(totals.reasoning))"
                    + unattributedTokenText
            )
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            .monospacedDigit()
        }
        .padding(16)
        .frame(width: 410)
        .background(
            SpendScopeTheme.dashboardSurfaceOpaque,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder, lineWidth: 1)
        }
        .foregroundStyle(SpendScopeTheme.dashboardPrimaryText)
    }

    private var modelText: String {
        ProjectReplyPresentation.modelText(
            conversation.modelCalls
                .map { "\($0.name) ×\($0.count)" }
                .joined(separator: " · ")
        )
    }

    private var skillCallCount: Int {
        conversation.skillCalls.reduce(0) { $0 + $1.count }
    }

    private var toolCallCount: Int {
        conversation.toolCalls.reduce(0) { $0 + $1.count }
    }

    private var tokenTotals: (
        uncachedInput: Int,
        cachedInput: Int,
        visibleOutput: Int,
        reasoning: Int
    ) {
        conversation.replies.reduce(into: (0, 0, 0, 0)) { totals, reply in
            totals.0 += reply.uncachedInputTokens
            totals.1 += reply.cachedInputTokens
            totals.2 += reply.visibleOutputTokens
            totals.3 += reply.reasoningTokens
        }
    }

    private var unattributedTokenText: String {
        guard conversation.unattributedTokens > 0 else { return "" }
        return " · 未归属 \(TokenFormatter.compact(conversation.unattributedTokens))"
    }

    private func summary(
        title: String,
        count: Int,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            Spacer(minLength: 0)
            Text("\(count) 次")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(
            tint.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func activitySection(
        title: String,
        icon: String,
        tint: Color,
        calls: [ProjectReplyActivityCall]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)

            if calls.isEmpty {
                Text("本任务未调用")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            } else {
                ForEach(calls) { call in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(tint.opacity(0.72))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(call.name)
                            .font(.system(size: 10, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text("\(call.count) 次")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                            .monospacedDigit()
                            .padding(.top, 1)
                    }
                    .frame(minHeight: 20)
                }
            }
        }
    }
}
