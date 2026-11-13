import XCTest
@testable import LumoBar

final class CircadianSettingsTests: XCTestCase {
    private func kf(_ h: Int, _ m: Int = 0, _ b: Int, _ t: Int) -> CircadianKeyframe {
        CircadianKeyframe(hour: h, minute: m, brightness: b, temperature: t)
    }

    private func minutes(_ h: Int, _ m: Int = 0) -> Int { h * 60 + m }

    func testDefaults() {
        let s = CircadianSettings.default
        XCTAssertFalse(s.isEnabled)
        XCTAssertTrue(s.applyBrightness)
        XCTAssertTrue(s.applyTemperature)
        XCTAssertEqual(s.keyframes.count, 6)
        XCTAssertEqual(s.keyframes.map(\.minuteOfDay), s.keyframes.map(\.minuteOfDay).sorted())
    }

    func testMinuteOfDay() {
        XCTAssertEqual(kf(7, 30, 1, 1).minuteOfDay, 450)
    }

    func testExactKeyframeTimesReturnKeyframeValues() {
        let s = CircadianSettings.default
        for frame in s.keyframes {
            let v = s.values(at: frame.minuteOfDay)
            XCTAssertEqual(v.brightness, frame.brightness, "brightness at \(frame.hour):\(frame.minute)")
            XCTAssertEqual(v.temperature, frame.temperature, "temperature at \(frame.hour):\(frame.minute)")
        }
    }

    func testMidpointBetweenTwoKeyframes() {
        // 06:00 (50 %, 4000 K) -> 09:00 (90 %, 5000 K): 07:30 is halfway.
        let v = CircadianSettings.default.values(at: minutes(7, 30))
        XCTAssertEqual(v.brightness, 70)
        XCTAssertEqual(v.temperature, 4500)
    }

    func testQuarterPointInterpolates() {
        let s = CircadianSettings(keyframes: [kf(8, 0, 0, 2000), kf(12, 0, 100, 6000)])
        let v = s.values(at: minutes(9))
        XCTAssertEqual(v.brightness, 25)
        XCTAssertEqual(v.temperature, 3000)
    }

    func testDescendingSegmentInterpolates() {
        // 12:00 (100, 5500) -> 17:00 (80, 4000): 14:30 is halfway.
        let v = CircadianSettings.default.values(at: minutes(14, 30))
        XCTAssertEqual(v.brightness, 90)
        XCTAssertEqual(v.temperature, 4750)
    }

    func testWrapAroundAfterLastKeyframe() {
        // 22:00 (25, 2400) -> 06:00 next day (50, 4000), 8 h span. 02:00 is the midpoint.
        let v = CircadianSettings.default.values(at: minutes(2))
        XCTAssertEqual(v.brightness, 38)       // 37.5 rounds half away from zero
        XCTAssertEqual(v.temperature, 3200)
    }

    func testWrapAroundBeforeMidnightAndAtMidnight() {
        let s = CircadianSettings.default
        let evening = s.values(at: minutes(23))   // 1/8 into the span
        XCTAssertEqual(evening.brightness, 28)    // 25 + 25/8 = 28.125
        XCTAssertEqual(evening.temperature, 2600)

        let midnight = s.values(at: 0)            // 2/8 into the span
        XCTAssertEqual(midnight.brightness, 31)   // 31.25
        XCTAssertEqual(midnight.temperature, 2800)
    }

    func testEndOfDayContinuity() {
        // 23:59 and 00:00 should be nearly identical (continuous across midnight).
        let s = CircadianSettings.default
        let a = s.values(at: minutes(23, 59)), b = s.values(at: 0)
        XCTAssertLessThanOrEqual(abs(a.brightness - b.brightness), 1)
        XCTAssertLessThanOrEqual(abs(a.temperature - b.temperature), 5)
    }

    func testUnsortedKeyframesAreSortedFirst() {
        let sorted = CircadianSettings(keyframes: CircadianSettings.defaultKeyframes)
        let shuffled = CircadianSettings(keyframes: CircadianSettings.defaultKeyframes.reversed())
        for minute in stride(from: 0, to: 24 * 60, by: 37) {
            let a = sorted.values(at: minute), b = shuffled.values(at: minute)
            XCTAssertEqual(a.brightness, b.brightness, "minute \(minute)")
            XCTAssertEqual(a.temperature, b.temperature, "minute \(minute)")
        }
    }

    func testSingleKeyframeIsConstant() {
        let s = CircadianSettings(keyframes: [kf(10, 0, 42, 3300)])
        for minute in [0, 600, 1200, 1439] {
            let v = s.values(at: minute)
            XCTAssertEqual(v.brightness, 42)
            XCTAssertEqual(v.temperature, 3300)
        }
    }

    func testNoKeyframesFallsBackToDefaultValues() {
        let v = CircadianSettings(keyframes: []).values(at: 600)
        XCTAssertEqual(v.brightness, 80)
        XCTAssertEqual(v.temperature, 4000)
    }

    func testTwoKeyframesWrap() {
        let s = CircadianSettings(keyframes: [kf(6, 0, 100, 6000), kf(18, 0, 0, 2000)])
        XCTAssertEqual(s.values(at: minutes(12)).brightness, 50)
        // Midnight is the midpoint of the 18:00 -> 06:00 span.
        let night = s.values(at: 0)
        XCTAssertEqual(night.brightness, 50)
        XCTAssertEqual(night.temperature, 4000)
    }

    func testValuesStayWithinKeyframeRange() {
        let s = CircadianSettings.default
        let minB = s.keyframes.map(\.brightness).min()!, maxB = s.keyframes.map(\.brightness).max()!
        let minT = s.keyframes.map(\.temperature).min()!, maxT = s.keyframes.map(\.temperature).max()!
        for minute in 0..<(24 * 60) {
            let v = s.values(at: minute)
            XCTAssertTrue((minB...maxB).contains(v.brightness), "brightness \(v.brightness) at \(minute)")
            XCTAssertTrue((minT...maxT).contains(v.temperature), "temperature \(v.temperature) at \(minute)")
        }
    }

    func testHasSameContentIgnoresEnableSwitchOnly() {
        let saved = CircadianSettings.default
        var draft = saved
        draft.isEnabled = true
        XCTAssertTrue(draft.hasSameContent(as: saved))
        draft.keyframes[0].brightness += 5
        XCTAssertFalse(draft.hasSameContent(as: saved))
        draft = saved
        draft.applyTemperature = false
        XCTAssertFalse(draft.hasSameContent(as: saved))
        draft = saved
        draft.keyframes.removeLast()
        XCTAssertFalse(draft.hasSameContent(as: saved))
    }

    func testCodableRoundTrip() throws {
        var s = CircadianSettings.default
        s.isEnabled = true
        s.applyTemperature = false
        let decoded = try JSONDecoder().decode(CircadianSettings.self, from: JSONEncoder().encode(s))
        XCTAssertTrue(decoded.isEnabled)
        XCTAssertFalse(decoded.applyTemperature)
        XCTAssertEqual(decoded.keyframes, s.keyframes)
    }
}
