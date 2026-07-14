import XCTest
@testable import SpendScope

final class UsageAccumulatorTests: XCTestCase {
    func testConvertsCumulativeCountersIntoFourNonOverlappingCategories() {
        let previous = TokenCounters(input: 10_000, cachedInput: 6_000, output: 800, reasoning: 300)
        let current = TokenCounters(input: 16_000, cachedInput: 9_500, output: 1_400, reasoning: 500)

        XCTAssertEqual(
            UsageAccumulator.delta(previous: previous, current: current),
            TokenUsageDelta(uncachedInput: 2_500, cachedInput: 3_500, visibleOutput: 400, reasoning: 200)
        )
    }

    func testCounterRollbackStartsANewSegment() {
        let previous = TokenCounters(input: 50_000, cachedInput: 30_000, output: 4_000, reasoning: 1_000)
        let current = TokenCounters(input: 5_000, cachedInput: 2_000, output: 400, reasoning: 100)

        XCTAssertEqual(
            UsageAccumulator.delta(previous: previous, current: current),
            TokenUsageDelta(uncachedInput: 3_000, cachedInput: 2_000, visibleOutput: 300, reasoning: 100)
        )
    }

    func testAnyComponentRollbackStartsANewSegmentAndDerivedValuesFloorAtZero() {
        let previous = TokenCounters(input: 100, cachedInput: 80, output: 50, reasoning: 20)
        let current = TokenCounters(input: 110, cachedInput: 90, output: 40, reasoning: 50)

        XCTAssertEqual(
            UsageAccumulator.delta(previous: previous, current: current),
            TokenUsageDelta(uncachedInput: 20, cachedInput: 90, visibleOutput: 0, reasoning: 50)
        )
    }

    func testReturnsNilOnlyWhenAllFourDerivedCategoriesAreZero() {
        let counters = TokenCounters(input: 100, cachedInput: 80, output: 50, reasoning: 20)

        XCTAssertNil(UsageAccumulator.delta(previous: counters, current: counters))
        XCTAssertEqual(
            UsageAccumulator.delta(
                previous: .init(input: 0, cachedInput: 0, output: 0, reasoning: 0),
                current: .init(input: 1, cachedInput: 1, output: 1, reasoning: 1)
            ),
            TokenUsageDelta(uncachedInput: 0, cachedInput: 1, visibleOutput: 0, reasoning: 1)
        )
    }

    func testNormalizesPlansAndQuotaOrder() {
        XCTAssertEqual(
            PlanResolver.resolve(rawValue: "prolite"),
            PlanResolution(kind: .proLite, rawValue: "prolite", isInferred: false)
        )
        XCTAssertEqual(
            PlanResolver.resolve(rawValue: "future-plan"),
            PlanResolution(kind: .free, rawValue: "future-plan", isInferred: true)
        )

        let raw = [
            RawQuotaWindow(windowMinutes: 10_080, usedPercent: 16, resetsAtSeconds: 200),
            RawQuotaWindow(windowMinutes: 300, usedPercent: 15, resetsAtSeconds: 100)
        ]
        XCTAssertEqual(
            QuotaNormalizer.normalize(
                raw,
                plan: PlanResolver.resolve(rawValue: "plus"),
                observedAtMilliseconds: 1
            ).map(\.kind),
            [.weekly, .fiveHour]
        )
    }

    func testPlanResolutionIsCaseInsensitiveAndPreservesRawValue() {
        XCTAssertEqual(
            PlanResolver.resolve(rawValue: "PLUS"),
            PlanResolution(kind: .plus, rawValue: "PLUS", isInferred: false)
        )
        XCTAssertEqual(
            PlanResolver.resolve(rawValue: nil),
            PlanResolution(kind: .free, rawValue: nil, isInferred: true)
        )
    }

    func testQuotaNormalizationFiltersUnknownWindowsClampsRemainingAndConvertsResetTime() {
        let plan = PlanResolver.resolve(rawValue: "free")
        let observations = QuotaNormalizer.normalize(
            [
                .init(windowMinutes: 300, usedPercent: -25, resetsAtSeconds: 100),
                .init(windowMinutes: 60, usedPercent: 10, resetsAtSeconds: 200),
                .init(windowMinutes: 10_080, usedPercent: 125, resetsAtSeconds: nil)
            ],
            plan: plan,
            observedAtMilliseconds: 42
        )

        XCTAssertEqual(
            observations,
            [
                QuotaObservation(
                    kind: .fiveHour,
                    observedAtMilliseconds: 42,
                    windowMinutes: 300,
                    remaining: 1,
                    resetsAtMilliseconds: 100_000,
                    plan: plan
                ),
                QuotaObservation(
                    kind: .weekly,
                    observedAtMilliseconds: 42,
                    windowMinutes: 10_080,
                    remaining: 0,
                    resetsAtMilliseconds: nil,
                    plan: plan
                )
            ]
        )
    }
}
