import XCTest
@testable import LampControl

final class ServiceSupportTests: XCTestCase {
    func testSessionTimeoutsAreShorterThanTheSixtySecondDefault() {
        XCTAssertEqual(ServiceSession.lan.configuration.timeoutIntervalForRequest, 5)
        XCTAssertEqual(ServiceSession.cloud.configuration.timeoutIntervalForRequest, 15)
        XCTAssertLessThan(ServiceSession.lan.configuration.timeoutIntervalForResource, 60)
    }

    func testFirstWinsDictionaryDoesNotTrapOnDuplicates() {
        let table = Dictionary(firstWins: [("a", 1), ("b", 2), ("a", 3)])
        XCTAssertEqual(table, ["a": 1, "b": 2])
    }

    func testUniquedKeepsFirstOccurrenceAndOrder() {
        XCTAssertEqual([3, 1, 3, 2, 1].uniqued(by: { $0 }), [3, 1, 2])
    }

    private func lamp(_ id: String, power: Bool = false) -> LampDevice {
        LampDevice(
            id: "t:\(id)", providerID: .wiz, nativeID: id, name: id, online: true, power: power,
            brightness: 10, temperature: nil, color: nil, workMode: nil,
            capabilities: LightCapabilities(switchCode: nil, brightness: nil, temperature: nil, colorCode: nil, colorValueScale: nil, workModeCode: nil)
        )
    }

    func testLampCacheReplaceToleratesDuplicateNativeIDs() {
        let cache = LampCache()
        cache.replace(with: [lamp("x", power: true), lamp("x", power: false)])
        XCTAssertEqual(cache["x"]?.power, true)
    }

    func testLampCacheUpdateReturnsNilForUnknownLamp() {
        let cache = LampCache()
        XCTAssertNil(cache.update("nope") { $0.power = true })
        cache.replace(with: [lamp("a")])
        XCTAssertEqual(cache.update("a") { $0.power = true }?.power, true)
        XCTAssertEqual(cache["a"]?.power, true)
    }

    func testLampCacheSurvivesConcurrentMutation() {
        let cache = LampCache()
        cache.replace(with: (0..<20).map { lamp("\($0)") })
        DispatchQueue.concurrentPerform(iterations: 2000) { i in
            if i % 50 == 0 { cache.replace(with: (0..<20).map { lamp("\($0)") }) }
            _ = cache.update("\(i % 20)") { $0.brightness = i }
        }
        XCTAssertNotNil(cache["0"])
    }
}
