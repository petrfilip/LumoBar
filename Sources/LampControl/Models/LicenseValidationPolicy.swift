import Foundation

/// What to do with the cached license after the launch-time re-validation.
enum LicenseValidationOutcome: Equatable {
    /// The server answered: use (and persist) its verdict.
    case adopt(LicenseState)
    /// The server definitively rejected the request: fall back to early access
    /// and persist, as before.
    case downgrade
    /// No definitive answer (offline, timeout, 5xx, garbage): leave the cached
    /// state and the stored key untouched, say nothing, retry later.
    case keepCached
}

enum LicenseValidationPolicy {
    /// True when the failure says nothing about the license itself.
    static func isTransient(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain { return true }
        if let activation = error as? LicenseActivationError {
            switch activation {
            case .networkError, .decodingError:
                return true
            case .invalidLicenseKey, .invalidEmail, .apiError, .alreadyActivated, .licenseExpired:
                return false
            }
        }
        return false
    }

    static func outcome(for result: Result<LicenseState, Error>) -> LicenseValidationOutcome {
        switch result {
        case .success(let state):
            return .adopt(state)
        case .failure(let error):
            return isTransient(error) ? .keepCached : .downgrade
        }
    }

    /// Seconds to wait before retry number `attempt` (0-based) after a
    /// transient failure; `nil` once the retries are used up (the next wake
    /// from sleep or the next launch tries again).
    static func retryDelay(afterAttempt attempt: Int) -> TimeInterval? {
        let delays: [TimeInterval] = [2 * 60, 10 * 60, 60 * 60]
        return attempt >= 0 && attempt < delays.count ? delays[attempt] : nil
    }

    /// HTTP statuses that mean "try again later", not "this license is bad".
    static func isTransientHTTPStatus(_ status: Int) -> Bool {
        status == 408 || status == 429 || (500...599).contains(status)
    }
}
