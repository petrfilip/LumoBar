import XCTest
@testable import LampControl

final class LicenseValidationPolicyTests: XCTestCase {
    func testURLErrorsAreTransient() {
        for code in [URLError.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed] {
            XCTAssertEqual(LicenseValidationPolicy.outcome(for: .failure(URLError(code))), .keepCached)
        }
    }

    func testBridgedNSURLErrorIsTransient() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(LicenseValidationPolicy.outcome(for: .failure(error)), .keepCached)
    }

    func testServerSideAndGarbageAnswersAreTransient() {
        XCTAssertEqual(LicenseValidationPolicy.outcome(for: .failure(LicenseActivationError.networkError)), .keepCached)
        XCTAssertEqual(LicenseValidationPolicy.outcome(for: .failure(LicenseActivationError.decodingError)), .keepCached)
    }

    func testDefinitiveRejectionDowngrades() {
        XCTAssertEqual(LicenseValidationPolicy.outcome(for: .failure(LicenseActivationError.apiError("not found"))), .downgrade)
        XCTAssertEqual(LicenseValidationPolicy.outcome(for: .failure(LicenseActivationError.licenseExpired)), .downgrade)
        XCTAssertEqual(LicenseValidationPolicy.outcome(for: .failure(LicenseActivationError.invalidLicenseKey)), .downgrade)
    }

    func testUnknownErrorsDowngradeAsBefore() {
        struct Other: Error {}
        XCTAssertEqual(LicenseValidationPolicy.outcome(for: .failure(Other())), .downgrade)
    }

    func testSuccessAdoptsServerVerdict() {
        let state = LicenseState(tier: .free, provider: .lemonSqueezy, licenseKey: "k", instanceID: "i",
                                 instanceName: nil, customerEmail: nil, productName: nil,
                                 activatedAt: nil, validatedAt: nil)
        XCTAssertEqual(LicenseValidationPolicy.outcome(for: .success(state)), .adopt(state))
    }

    func testHTTPStatusClassification() {
        for status in [408, 429, 500, 502, 503, 599] {
            XCTAssertTrue(LicenseValidationPolicy.isTransientHTTPStatus(status), "\(status)")
        }
        for status in [400, 401, 403, 404, 422] {
            XCTAssertFalse(LicenseValidationPolicy.isTransientHTTPStatus(status), "\(status)")
        }
    }

    func testRetryScheduleBacksOffAndEnds() {
        XCTAssertEqual(LicenseValidationPolicy.retryDelay(afterAttempt: 0), 120)
        XCTAssertEqual(LicenseValidationPolicy.retryDelay(afterAttempt: 1), 600)
        XCTAssertEqual(LicenseValidationPolicy.retryDelay(afterAttempt: 2), 3600)
        XCTAssertNil(LicenseValidationPolicy.retryDelay(afterAttempt: 3))
        XCTAssertNil(LicenseValidationPolicy.retryDelay(afterAttempt: -1))
    }

    func testKeylessEarlyAccessStateIsReturnedUnchangedWithoutNetwork() async throws {
        // The user's own license.json: {"provider":"lemonSqueezy","tier":"earlyAccess"}, no key.
        let data = Data(#"{"provider":"lemonSqueezy","tier":"earlyAccess"}"#.utf8)
        let state = try JSONDecoder().decode(LicenseState.self, from: data)
        XCTAssertNil(state.licenseKey)
        let validated = try await LicenseActivationService().validate(state)
        XCTAssertEqual(validated, state)
        XCTAssertEqual(LicenseValidationPolicy.outcome(for: .success(validated)), .adopt(state))
    }
}
