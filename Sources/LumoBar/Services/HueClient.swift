import Foundation

final class HueClient {
    private let session: URLSession

    init(session: URLSession = ServiceSession.lan) {
        self.session = session
    }

    func discoverBridges() async throws -> [HueBridge] {
        guard let url = URL(string: "https://discovery.meethue.com/") else {
            throw LampControlError.configuration(NSLocalizedString("error.hue.discovery.invalid", comment: ""))
        }

        let (data, response) = try await session.data(from: url)
        try validate(response)
        return try JSONDecoder().decode([HueBridge].self, from: data)
    }

    func createUser(bridgeIP: String) async throws -> String {
        let items: [HueAPIItem] = try await request(
            bridgeIP: bridgeIP,
            method: "POST",
            path: "/api",
            username: nil,
            body: ["devicetype": "LumoBar#macOS"]
        )

        for item in items {
            switch item {
            case .success(let success):
                if let username = success["username"]?.stringValue {
                    return username
                }
            case .error(let error):
                throw LampControlError.configuration("Hue: \(error.description)")
            }
        }

        throw LampControlError.invalidResponse
    }

    func lights(settings: HueSettings) async throws -> [String: HueLightDTO] {
        let data = try await requestData(
            bridgeIP: settings.bridgeIP,
            method: "GET",
            path: "/api/\(escapePath(settings.username))/lights",
            username: settings.username,
            body: Optional<EmptyBody>.none
        )
        return try Self.decodeLights(data)
    }

    /// Hue v1 answers errors with HTTP 200 and an array (`[{"error":{"type":1,...}}]`) instead
    /// of the object we asked for. Surface that as a readable error, not a decoding failure.
    static func decodeLights(_ data: Data) throws -> [String: HueLightDTO] {
        do {
            return try JSONDecoder().decode([String: HueLightDTO].self, from: data)
        } catch {
            if let apiError = apiError(in: data) {
                throw map(apiError)
            }
            throw error
        }
    }

    /// The first `error` item of a Hue v1 reply array, if the body is such an array.
    static func apiError(in data: Data) -> HueAPIError? {
        guard let items = try? JSONDecoder().decode([HueAPIItem].self, from: data) else { return nil }
        for case .error(let error) in items { return error }
        return nil
    }

    /// Error type 1 is "unauthorized user": the stored username is no longer valid.
    static func map(_ error: HueAPIError) -> LampControlError {
        if error.type == 1 {
            return .configuration(NSLocalizedString("error.hue.unauthorized", comment: ""))
        }
        return .device("Hue: \(error.description)")
    }

    func setState(settings: HueSettings, lightID: String, state: HueStateCommand) async throws {
        let items: [HueAPIItem] = try await request(
            bridgeIP: settings.bridgeIP,
            method: "PUT",
            path: "/api/\(escapePath(settings.username))/lights/\(escapePath(lightID))/state",
            username: settings.username,
            body: state
        )

        if case .error(let error)? = items.first(where: {
            if case .error = $0 { return true }
            return false
        }) {
            throw LampControlError.device("Hue: \(error.description)")
        }
    }

    private func request<Response: Decodable, Body: Encodable>(
        bridgeIP: String,
        method: String,
        path: String,
        username: String?,
        body: Body?
    ) async throws -> Response {
        let data = try await requestData(bridgeIP: bridgeIP, method: method, path: path, username: username, body: body)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func requestData<Body: Encodable>(
        bridgeIP: String,
        method: String,
        path: String,
        username: String?,
        body: Body?
    ) async throws -> Data {
        guard var components = URLComponents(string: "http://\(bridgeIP)") else {
            throw LampControlError.configuration(NSLocalizedString("error.hue.bridge.address.invalid", comment: ""))
        }
        components.path = path
        guard let url = components.url else {
            throw LampControlError.configuration(NSLocalizedString("error.hue.url.invalid", comment: ""))
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let username {
            request.setValue(username, forHTTPHeaderField: "hue-application-key")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        try validate(response)
        // An invalid user must read as "pair again", whatever shape the caller expected.
        if username != nil, let apiError = Self.apiError(in: data), apiError.type == 1 {
            throw Self.map(apiError)
        }
        return data
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw LampControlError.invalidResponse
        }
    }

    private func escapePath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

struct HueStateCommand: Encodable {
    var on: Bool?
    var bri: Int?
    var hue: Int?
    var sat: Int?
    var ct: Int?
}

private struct EmptyBody: Encodable {}
