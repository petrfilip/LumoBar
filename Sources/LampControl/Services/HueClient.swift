import Foundation

final class HueClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
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
            body: ["devicetype": "LampControl#macOS"]
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
        try await request(
            bridgeIP: settings.bridgeIP,
            method: "GET",
            path: "/api/\(escapePath(settings.username))/lights",
            username: settings.username,
            body: Optional<EmptyBody>.none
        )
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
            throw LampControlError.tuya("Hue: \(error.description)")
        }
    }

    private func request<Response: Decodable, Body: Encodable>(
        bridgeIP: String,
        method: String,
        path: String,
        username: String?,
        body: Body?
    ) async throws -> Response {
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
        return try JSONDecoder().decode(Response.self, from: data)
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
