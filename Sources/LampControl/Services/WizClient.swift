import Foundation
import Network

final class WizClient {
    private let timeout: TimeInterval = 3.0

    // MARK: - Reply parsing

    /// Decodes a WiZ reply and turns a device-reported `error` into a thrown, localized error.
    static func parseReply(_ data: Data) throws -> WizResponse {
        let response: WizResponse
        do {
            response = try JSONDecoder().decode(WizResponse.self, from: data)
        } catch {
            throw LampControlError.invalidResponse
        }
        if let error = response.error {
            let detail = error.message ?? error.code.map(String.init) ?? "?"
            throw LampControlError.device(String(format: NSLocalizedString("error.wiz.device", comment: ""), detail))
        }
        return response
    }

    /// Validates the reply to a `setPilot`: an explicit error or `success:false` is a failure.
    /// A reply we cannot decode at all is tolerated (the command was delivered).
    static func validateSetReply(_ data: Data) throws {
        let response: WizResponse
        do {
            response = try parseReply(data)
        } catch LampControlError.invalidResponse {
            return
        }
        if response.result?.success == false {
            throw LampControlError.device(String(format: NSLocalizedString("error.wiz.device", comment: ""),
                                                 NSLocalizedString("error.wiz.not.applied", comment: "")))
        }
    }

    func getState(device: WizDevice) async throws -> WizStateResult {
        let req = WizRequest(method: "getPilot", params: WizParams())
        let data = try await send(req, to: device)
        let response = try Self.parseReply(data)
        guard let result = response.result else { throw LampControlError.invalidResponse }
        return result
    }

    func setPower(device: WizDevice, value: Bool) async throws {
        let req = WizRequest(method: "setPilot", params: WizParams(state: value))
        try Self.validateSetReply(try await send(req, to: device))
    }

    func setDimming(device: WizDevice, value: Int) async throws {
        let req = WizRequest(method: "setPilot", params: WizParams(state: true, dimming: max(1, min(100, value))))
        try Self.validateSetReply(try await send(req, to: device))
    }

    func setTemp(device: WizDevice, kelvin: Int) async throws {
        let req = WizRequest(method: "setPilot", params: WizParams(state: true, temp: max(2200, min(6500, kelvin))))
        try Self.validateSetReply(try await send(req, to: device))
    }

    func setRGB(device: WizDevice, r: Int, g: Int, b: Int, dimming: Int) async throws {
        let req = WizRequest(method: "setPilot", params: WizParams(state: true, dimming: max(1, min(100, dimming)), r: r, g: g, b: b))
        try Self.validateSetReply(try await send(req, to: device))
    }

    // MARK: - UDP send/receive

    private func send(_ request: WizRequest, to device: WizDevice) async throws -> Data {
        let payload = try JSONEncoder().encode(request)
        let host = NWEndpoint.Host(device.host)
        guard let portValue = NWEndpoint.Port(rawValue: UInt16(device.port)) else {
            throw LampControlError.configuration(NSLocalizedString("error.wiz.port.invalid", comment: ""))
        }
        let endpoint = NWEndpoint.hostPort(host: host, port: portValue)
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let connection = NWConnection(to: endpoint, using: params)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let gate = OneShot<Data>(continuation) { connection.cancel() }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            gate.finish(.failure(error))
                            return
                        }
                        connection.receiveMessage { data, _, _, error in
                            if let error {
                                gate.finish(.failure(error))
                            } else if let data {
                                gate.finish(.success(data))
                            } else {
                                gate.finish(.failure(LampControlError.invalidResponse))
                            }
                        }
                    })
                case .failed(let error):
                    gate.finish(.failure(error))
                default:
                    break
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                gate.finish(.failure(LampControlError.offline))
            }

            connection.start(queue: .global())
        }
    }
}
