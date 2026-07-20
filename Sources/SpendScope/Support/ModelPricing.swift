import Foundation

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
        let inputCost = tokenCost(uncachedInputTokens, rate: inputPerMillionUSD)
        let cachedInputCost = tokenCost(cachedInputTokens, rate: cachedInputPerMillionUSD)
        let visibleOutputCost = tokenCost(visibleOutputTokens, rate: outputPerMillionUSD)
        let reasoningCost = tokenCost(reasoningTokens, rate: outputPerMillionUSD)
        return inputCost + cachedInputCost + visibleOutputCost + reasoningCost
    }

    func tokenCost(_ tokens: Int, rate: Double) -> Double {
        tokenCost(Int64(tokens), rate: rate)
    }

    private func tokenCost(_ tokens: Int64, rate: Double) -> Double {
        Double(max(tokens, 0)) / 1_000_000 * rate
    }
}

enum ModelPricingCatalog {
    static func rule(for modelID: String) -> ModelPricingRule? {
        switch modelID.lowercased() {
        case "gpt-5.6", "gpt-5.6-sol":
            ModelPricingRule(
                modelID: "gpt-5.6-sol",
                inputPerMillionUSD: 5,
                cachedInputPerMillionUSD: 0.5,
                outputPerMillionUSD: 30,
                longContextThresholdTokens: 272_000,
                longContextInputMultiplier: 2,
                longContextOutputMultiplier: 1.5,
                cacheWriteMultiplier: 1.25
            )
        case "gpt-5.6-terra":
            ModelPricingRule(
                modelID: "gpt-5.6-terra",
                inputPerMillionUSD: 2.5,
                cachedInputPerMillionUSD: 0.25,
                outputPerMillionUSD: 15,
                longContextThresholdTokens: 272_000,
                longContextInputMultiplier: 2,
                longContextOutputMultiplier: 1.5,
                cacheWriteMultiplier: 1.25
            )
        case "gpt-5.5":
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
        default:
            nil
        }
    }
}

enum ModelCostFormatter {
    static func usd(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        if value >= 1 { return String(format: "$%.2f", value) }
        if value >= 0.01 { return String(format: "$%.3f", value) }
        return String(format: "$%.4f", value)
    }

    static func rate(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
