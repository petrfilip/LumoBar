import CryptoKit
import Foundation

/// An `success:false` reply from the Tuya cloud. Keeps the numeric `code` so callers can tell
/// "this device does not support that command" apart from auth or transport problems.
struct TuyaAPIError: LocalizedError {
    let message: String
    let code: Int?
    /// Set when the failing request was a device command (codes of the commands sent).
    var commandCodes: String?

    var errorDescription: String? {
        let details = code.map { " (code \($0))" } ?? ""
        let text = message + details
        guard let commandCodes else { return text }
        return String(format: NSLocalizedString("error.tuya.command.failed", comment: ""), text, commandCodes)
    }

    /// Tuya codes meaning the device rejected the command or its value (2008: "command or
    /// value not support", 1109: "param is illegal").
    static let unsupportedCommandCodes: Set<Int> = [2008, 1109]

    var isUnsupportedCommand: Bool {
        if let code { return Self.unsupportedCommandCodes.contains(code) }
        return message.lowercased().contains("not support")
    }
}

extension Error {
    /// True for a Tuya reply saying the device rejected the command or its value.
    var isTuyaUnsupportedCommand: Bool { (self as? TuyaAPIError)?.isUnsupportedCommand ?? false }
}

/// Talks to the Tuya cloud. An actor: the access token is shared mutable state and several
/// polls/commands can ask for it at once.
actor TuyaClient {
    private let accessId: String
    private let accessSecret: String
    private let endpoint: URL
    private let session: URLSession
    private var accessToken = ""
    private var tokenExpiresAt = Date.distantPast
    /// The token request currently in flight; concurrent callers wait for it instead of each
    /// fetching (and overwriting) a token of their own.
    private var tokenTask: Task<Void, Error>?

    init(accessId: String, accessSecret: String, endpoint: String, session: URLSession = ServiceSession.cloud) throws {
        self.accessId = accessId
        self.accessSecret = accessSecret
        guard let endpointURL = URL(string: endpoint) else {
            throw LampControlError.configuration(NSLocalizedString("error.tuya.endpoint.invalid", comment: ""))
        }
        self.endpoint = endpointURL
        self.session = session
    }

    func get<Result: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Result {
        try await request("GET", path: path, query: query, body: Optional<Data>.none)
    }

    func post<Body: Encodable, Result: Decodable>(_ path: String, body: Body) async throws -> Result {
        let data = try JSONEncoder().encode(body)
        return try await request("POST", path: path, query: [:], body: data)
    }

    private func request<Result: Decodable>(_ method: String, path: String, query: [String: String], body: Data?) async throws -> Result {
        if path != "/v1.0/token" {
            try await ensureToken()
        }

        let urlPath = signedPath(path, query: query)
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let nonce = UUID().uuidString
        let bodyData = body ?? Data()
        let contentHash = sha256Hex(bodyData)
        let stringToSign = "\(method)\n\(contentHash)\n\n\(urlPath)"
        let tokenPart = path == "/v1.0/token" ? "" : accessToken
        let sign = hmacHex("\(accessId)\(tokenPart)\(timestamp)\(nonce)\(stringToSign)")

        guard let url = URL(string: urlPath, relativeTo: endpoint)?.absoluteURL else {
            throw LampControlError.configuration(NSLocalizedString("error.tuya.endpoint.invalid", comment: ""))
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(accessId, forHTTPHeaderField: "client_id")
        request.setValue(tokenPart, forHTTPHeaderField: "access_token")
        request.setValue(sign, forHTTPHeaderField: "sign")
        request.setValue(timestamp, forHTTPHeaderField: "t")
        request.setValue(nonce, forHTTPHeaderField: "nonce")
        request.setValue("HMAC-SHA256", forHTTPHeaderField: "sign_method")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LampControlError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LampControlError.http(httpResponse.statusCode)
        }

        let envelope = try JSONDecoder().decode(TuyaEnvelope<Result>.self, from: data)
        guard envelope.success else {
            throw TuyaAPIError(
                message: envelope.msg ?? NSLocalizedString("error.tuya.invalid.response", comment: ""),
                code: envelope.code.flatMap { Int($0.description) }
            )
        }

        guard let result = envelope.result else {
            throw LampControlError.invalidResponse
        }

        return result
    }

    private func ensureToken() async throws {
        if !accessToken.isEmpty && Date() < tokenExpiresAt {
            return
        }
        if let inFlight = tokenTask {
            return try await inFlight.value
        }

        let task = Task { try await self.fetchToken() }
        tokenTask = task
        defer { tokenTask = nil }
        try await task.value
    }

    private func fetchToken() async throws {
        let token: TuyaTokenResult = try await request("GET", path: "/v1.0/token", query: ["grant_type": "1"], body: Optional<Data>.none)
        accessToken = token.accessToken
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(max(30, token.expireTime - 60)))
    }

    private func signedPath(_ path: String, query: [String: String]) -> String {
        guard !query.isEmpty else { return path }

        let items = query
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")

        return "\(path)?\(items)"
    }

    private func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func hmacHex(_ value: String) -> String {
        let key = SymmetricKey(data: Data(accessSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: key)
        return signature.map { String(format: "%02x", $0) }.joined().uppercased()
    }
}
