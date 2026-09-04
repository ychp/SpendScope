import Foundation

struct ModelCostBreakdown: Equatable, Sendable {
    var uncachedInputUSD = 0.0
    var cachedInputUSD = 0.0
    var visibleOutputUSD = 0.0
    var reasoningUSD = 0.0

    var totalUSD: Double {
        uncachedInputUSD + cachedInputUSD + visibleOutputUSD + reasoningUSD
    }

    mutating func add(_ other: ModelCostBreakdown) {
        uncachedInputUSD += other.uncachedInputUSD
        cachedInputUSD += other.cachedInputUSD
        visibleOutputUSD += other.visibleOutputUSD
        reasoningUSD += other.reasoningUSD
    }
}

struct ModelPricingRule: Equatable, Sendable {
    let modelID: String
    let inputPerMillionUSD: Double
    let cachedInputPerMillionUSD: Double
    let outputPerMillionUSD: Double
    let longContextThresholdTokens: Int?
    let longContextInputMultiplier: Double?
    let longContextOutputMultiplier: Double?
    let cacheWriteMultiplier: Double?

    func estimate(
        uncachedInputTokens: Int64,
        cachedInputTokens: Int64,
        visibleOutputTokens: Int64,
        reasoningTokens: Int64
    ) -> Double {
        estimateBreakdown(
            uncachedInputTokens: uncachedInputTokens,
            cachedInputTokens: cachedInputTokens,
            visibleOutputTokens: visibleOutputTokens,
            reasoningTokens: reasoningTokens
        ).totalUSD
    }

    func estimateBreakdown(
        uncachedInputTokens: Int64,
        cachedInputTokens: Int64,
        visibleOutputTokens: Int64,
        reasoningTokens: Int64
    ) -> ModelCostBreakdown {
        ModelCostBreakdown(
            uncachedInputUSD: tokenCost(uncachedInputTokens, rate: inputPerMillionUSD),
            cachedInputUSD: tokenCost(cachedInputTokens, rate: cachedInputPerMillionUSD),
            visibleOutputUSD: tokenCost(visibleOutputTokens, rate: outputPerMillionUSD),
            reasoningUSD: tokenCost(reasoningTokens, rate: outputPerMillionUSD)
        )
    }

    func tokenCost(_ tokens: Int, rate: Double) -> Double {
        tokenCost(Int64(tokens), rate: rate)
    }

    private func tokenCost(_ tokens: Int64, rate: Double) -> Double {
        Double(max(tokens, 0)) / 1_000_000 * rate
    }
}

enum ModelPricingCatalog {
    static let publishedRules: [ModelPricingRule] = [
        ModelPricingRule(
            modelID: "gpt-5.6-sol",
            inputPerMillionUSD: 5,
            cachedInputPerMillionUSD: 0.5,
            outputPerMillionUSD: 30,
            longContextThresholdTokens: 272_000,
            longContextInputMultiplier: 2,
            longContextOutputMultiplier: 1.5,
            cacheWriteMultiplier: 1.25
        ),
        ModelPricingRule(
            modelID: "gpt-5.6-terra",
            inputPerMillionUSD: 2.5,
            cachedInputPerMillionUSD: 0.25,
            outputPerMillionUSD: 15,
            longContextThresholdTokens: 272_000,
            longContextInputMultiplier: 2,
            longContextOutputMultiplier: 1.5,
            cacheWriteMultiplier: 1.25
        ),
        ModelPricingRule(
            modelID: "gpt-5.5",
            inputPerMillionUSD: 5,
            cachedInputPerMillionUSD: 0.5,
            outputPerMillionUSD: 30,
            longContextThresholdTokens: 272_000,
            longContextInputMultiplier: 2,
            longContextOutputMultiplier: 1.5,
            cacheWriteMultiplier: nil
        )
    ]

    static func rule(for modelID: String) -> ModelPricingRule? {
        explicitRule(for: modelID)
            ?? publishedRules.first { $0.modelID == "gpt-5.5" }
    }

    static func usesReferencePricing(for modelID: String) -> Bool {
        explicitRule(for: modelID) == nil
    }

    private static func explicitRule(for modelID: String) -> ModelPricingRule? {
        let lowercasedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedID = lowercasedID == "gpt-5.6"
            ? "gpt-5.6-sol"
            : lowercasedID
        return publishedRules.first { $0.modelID == normalizedID }
    }
}

enum ModelCostFormatter {
    static func usd(_ value: Double, approximate: Bool = false) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        let formatted: String
        if value >= 1 {
            formatted = String(format: "$%.2f", value)
        } else if value >= 0.01 {
            formatted = String(format: "$%.3f", value)
        } else {
            formatted = String(format: "$%.4f", value)
        }
        return approximate ? "≈" + formatted : formatted
    }

    static func rate(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
