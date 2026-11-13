import Foundation

final class LifxClient {
    private let baseURL = URL(string: "https://api.lifx.com/v1")!
    private let session: URLSession

    init(session: URLSession = ServiceSession.cloud) {
        self.session = session
    }

    func listLights(token: String) async throws -> [LifxLightDTO] {
        try await request(
            token: token,
            method: "GET",
            path: "/lights/all",
            body: Optional<EmptyLifxBody>.none
        )
    }

    func setState(token: String, selector: String, command: LifxStateCommand) async throws {
        // With `fast: true` LIFX answers 202 Accepted with an empty body, and a normal reply
        // carries a results list we do not need: success is the status code, nothing is decoded.
        _ = try await send(
            token: token,
            method: "PUT",
            path: "/lights/\(escapePath(selector))/state",
            body: command
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        token: String,
        method: String,
        path: String,
        body: Body?
    ) async throws -> Response {
        let data = try await send(token: token, method: method, path: path, body: body)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    /// Performs the request and returns the raw body of a 2xx reply (possibly empty).
    private func send<Body: Encodable>(
        token: String,
        method: String,
        path: String,
        body: Body?
    ) async throws -> Data {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
            let decoded = try? JSONDecoder().decode(LifxErrorResponse.self, from: data)
            throw LampControlError.device("LIFX HTTP \(httpResponse.statusCode): \(decoded?.error ?? NSLocalizedString("error.http.refused", comment: ""))")
        }

        return data
    }

    private func escapePath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private struct EmptyLifxBody: Encodable {}

private struct LifxErrorResponse: Decodable {
    let error: String?
}
