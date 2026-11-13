import Foundation

final class GoveeClient {
    private let baseURL = URL(string: "https://developer-api.govee.com/v1")!
    private let session: URLSession

    init(session: URLSession = ServiceSession.cloud) {
        self.session = session
    }

    func listDevices(apiKey: String) async throws -> [GoveeDeviceDTO] {
        let response: GoveeDevicesResponse = try await request(
            apiKey: apiKey,
            method: "GET",
            path: "/devices",
            body: Optional<EmptyGoveeBody>.none
        )
        return response.data.devices
    }

    func deviceState(apiKey: String, device: String, model: String) async throws -> [GoveeStatePropertyDTO] {
        var components = URLComponents(url: baseURL.appendingPathComponent("devices/state"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "device", value: device),
            URLQueryItem(name: "model", value: model)
        ]
        guard let url = components.url else {
            throw LampControlError.configuration(NSLocalizedString("error.govee.url.invalid", comment: ""))
        }

        let response: GoveeStateResponse = try await request(apiKey: apiKey, method: "GET", url: url, body: Optional<EmptyGoveeBody>.none)
        return response.data.properties
    }

    func control(apiKey: String, body: GoveeControlBody) async throws {
        let _: GoveeControlResponse = try await request(
            apiKey: apiKey,
            method: "PUT",
            path: "/devices/control",
            body: body
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        apiKey: String,
        method: String,
        path: String,
        body: Body?
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        return try await request(apiKey: apiKey, method: method, url: url, body: body)
    }

    private func request<Response: Decodable, Body: Encodable>(
        apiKey: String,
        method: String,
        url: URL,
        body: Body?
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "Govee-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LampControlError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let decoded = try? JSONDecoder().decode(GoveeErrorResponse.self, from: data)
            let message = decoded?.message ?? NSLocalizedString("error.http.refused", comment: "")
            throw LampControlError.device("Govee HTTP \(httpResponse.statusCode): \(message)")
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct EmptyGoveeBody: Encodable {}
private struct GoveeControlResponse: Decodable {}
private struct GoveeErrorResponse: Decodable {
    let message: String?
}
