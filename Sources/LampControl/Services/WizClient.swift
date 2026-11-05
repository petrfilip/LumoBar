import Foundation
import Network

final class WizClient {
    private let timeout: TimeInterval = 3.0

    func getState(device: WizDevice) async throws -> WizStateResult {
        let req = WizRequest(method: "getPilot", params: WizParams())
        let data = try await send(req, to: device)
        let response = try JSONDecoder().decode(WizResponse.self, from: data)
        guard let result = response.result else { throw LampControlError.invalidResponse }
        return result
    }

    func setPower(device: WizDevice, value: Bool) async throws {
        let req = WizRequest(method: "setPilot", params: WizParams(state: value))
        _ = try await send(req, to: device)
    }

    func setDimming(device: WizDevice, value: Int) async throws {
        let req = WizRequest(method: "setPilot", params: WizParams(state: true, dimming: max(1, min(100, value))))
        _ = try await send(req, to: device)
    }

    func setTemp(device: WizDevice, kelvin: Int) async throws {
        let req = WizRequest(method: "setPilot", params: WizParams(state: true, temp: max(2200, min(6500, kelvin))))
        _ = try await send(req, to: device)
    }

    func setRGB(device: WizDevice, r: Int, g: Int, b: Int, dimming: Int) async throws {
        let req = WizRequest(method: "setPilot", params: WizParams(state: true, dimming: max(1, min(100, dimming)), r: r, g: g, b: b))
        _ = try await send(req, to: device)
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

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false

            let timer = DispatchWorkItem {
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(throwing: LampControlError.offline)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + self.timeout, execute: timer)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            timer.cancel()
                            guard !resumed else { return }
                            resumed = true
                            connection.cancel()
                            continuation.resume(throwing: error)
                            return
                        }
                        connection.receiveMessage { data, _, _, error in
                            timer.cancel()
                            guard !resumed else { return }
                            resumed = true
                            connection.cancel()
                            if let error {
                                continuation.resume(throwing: error)
                            } else if let data {
                                continuation.resume(returning: data)
                            } else {
                                continuation.resume(throwing: LampControlError.invalidResponse)
                            }
                        }
                    })
                case .failed(let error):
                    timer.cancel()
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            connection.start(queue: .global())
        }
    }
}
