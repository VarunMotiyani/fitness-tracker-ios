import Testing
import Foundation
@testable import Metrics

@Suite struct PlateMathTests {
    @Test func olympicBarbellPlateCalculation() {
        // 60 kg with 20 kg bar = 40 kg load (20 kg per side = 1x20)
        let res1 = PlateMath.calculate(totalWeight: 60, barWeight: 20)
        #expect(res1.perSideWeight == 20)
        #expect(res1.platesPerSide == [20])
        #expect(res1.summary == "Bar 20 kg · 20 kg / side [20]")

        // 85 kg with 20 kg bar = 65 kg load (32.5 kg per side = 25 + 5 + 2.5)
        let res2 = PlateMath.calculate(totalWeight: 85, barWeight: 20)
        #expect(res2.perSideWeight == 32.5)
        #expect(res2.platesPerSide == [25, 5, 2.5])
        #expect(res2.summary == "Bar 20 kg · 32.5 kg / side [25, 5, 2.5]")
    }

    @Test func barOnlyOrBelowBarWeight() {
        let res = PlateMath.calculate(totalWeight: 20, barWeight: 20)
        #expect(res.perSideWeight == 0)
        #expect(res.platesPerSide.isEmpty)
        #expect(res.summary == "Bar 20 kg")

        let resBelow = PlateMath.calculate(totalWeight: 15, barWeight: 20)
        #expect(resBelow.perSideWeight == 0)
        #expect(resBelow.platesPerSide.isEmpty)
    }

    @Test func ezBarAndSmithMachineWeights() {
        // EZ Bar: 10 kg bar, 30 kg total = 10 kg per side (1x10)
        let ezRes = PlateMath.calculate(totalWeight: 30, barWeight: BarType.ezBarbell.defaultWeightKg)
        #expect(ezRes.perSideWeight == 10)
        #expect(ezRes.platesPerSide == [10])

        // Smith Machine: 9 kg bar, 49 kg total = 20 kg per side (1x20)
        let smithRes = PlateMath.calculate(totalWeight: 49, barWeight: BarType.smithMachine.defaultWeightKg)
        #expect(smithRes.perSideWeight == 20)
        #expect(smithRes.platesPerSide == [20])
    }

    @Test func imperialPoundPlates() {
        // 135 lb with 45 lb bar = 90 lb load (45 lb per side = 1x45)
        let res = PlateMath.calculate(
            totalWeight: 135,
            barWeight: BarType.olympicBarbell.defaultWeightLb,
            availablePlates: PlateMath.standardLbPlates,
            unitString: "lb"
        )
        #expect(res.perSideWeight == 45)
        #expect(res.platesPerSide == [45])
        #expect(res.summary == "Bar 45 lb · 45 lb / side [45]")
    }
}
