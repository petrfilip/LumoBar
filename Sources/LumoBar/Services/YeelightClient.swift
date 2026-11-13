import Foundation
import Network

final class YeelightClient {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 4.0) {
        self.timeout = timeout
    }

    func sendCommand(host: String, port: Int, method: String, params: [Any]) async throws -> [String] {
        let requestID = Int.random(in: 1...1_000_000)
        let payload: [String: Any] = [
            "id": requestID,
            "method": method,
            "params": params
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard var line = String(data: data, encoding: .utf8) else {
            throw LampControlError.invalidResponse
        }
        line.append("\r\n")

        return try await exchange(host: host, port: port, command: line, requestID: requestID)
    }

    /// Outcome of parsing one line received from the bulb.
    enum LineOutcome {
        case result([String])
        case failure(Error)
        case ignore
    }

    /// Yeelight bulbs broadcast `{"method":"props",...}` notifications to *every*
    /// open TCP connection whenever their state changes. Because we open a fresh
    /// connection per command, the first bytes we read are often a notification
    /// triggered by the previous command (e.g. `set_hsv` followed by `set_bright`),
    /// not the reply to ours. Only lines carrying our request id are answers.
    static func parse(line: Substring, requestID: Int) -> LineOutcome {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(YeelightResponse.self, from: data),
              decoded.id == requestID
        else { return .ignore }

        if let error = decoded.error {
            return .failure(LampControlError.yeelight("\(error.message) (\(error.code))"))
        }
        if let result = decoded.result {
            return .result(result)
        }
        return .ignore
    }

    /// A refused TCP connection means nothing listens on the bulb's control port: LAN Control is
    /// switched off (or the address is wrong). Network.framework reports it as `.waiting`, not
    /// `.failed`, and retries until the timeout, so it has to be recognised to fail fast.
    static func isConnectionRefused(_ error: NWError) -> Bool {
        if case .posix(let code) = error { return code == .ECONNREFUSED }
        return false
    }

    /// The error shown for a connection-level failure.
    static func connectionError(_ error: NWError) -> LampControlError {
        if isConnectionRefused(error) {
            return .yeelight(NSLocalizedString("error.yeelight.refused", comment: ""))
        }
        return .yeelight("\(error.localizedDescription)")
    }

    private func exchange(host: String, port: Int, command: String, requestID: Int) async throws -> [String] {
        guard let rawPort = UInt16(exactly: port), let nwPort = NWEndpoint.Port(rawValue: rawPort) else {
            throw LampControlError.configuration(NSLocalizedString("error.yeelight.port.invalid", comment: ""))
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let timeout = self.timeout

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var finished = false
            var buffer = Data()

            func finish(_ result: Result<[String], Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(with: result)
            }

            /// Reads until a line answering `requestID` arrives, skipping
            /// notifications and partial lines, or until the bulb closes the socket.
            func receiveNext() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, receiveError in
                    if let receiveError {
                        finish(.failure(LampControlError.yeelight("\(receiveError.localizedDescription)")))
                        return
                    }
                    if let data {
                        buffer.append(data)
                    }

                    // Process every complete line; keep a trailing partial line in the buffer.
                    while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = buffer[buffer.startIndex..<newline]
                        buffer.removeSubrange(buffer.startIndex...newline)
                        guard let text = String(data: lineData, encoding: .utf8) else { continue }
                        switch Self.parse(line: Substring(text), requestID: requestID) {
                        case .result(let values):
                            finish(.success(values))
                            return
                        case .failure(let error):
                            finish(.failure(error))
                            return
                        case .ignore:
                            continue
                        }
                    }

                    if isComplete {
                        // Socket closed: the last line may lack a terminating newline.
                        if let text = String(data: buffer, encoding: .utf8),
                           case .result(let values) = Self.parse(line: Substring(text), requestID: requestID) {
                            finish(.success(values))
                        } else {
                            finish(.failure(LampControlError.invalidResponse))
                        }
                        return
                    }

                    receiveNext()
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let payload = command.data(using: .utf8) ?? Data()
                    connection.send(content: payload, completion: .contentProcessed { sendError in
                        if let sendError {
                            finish(.failure(LampControlError.yeelight("\(sendError.localizedDescription)")))
                            return
                        }
                        receiveNext()
                    })
                case .waiting(let error):
                    if Self.isConnectionRefused(error) {
                        finish(.failure(Self.connectionError(error)))
                    }
                case .failed(let error):
                    finish(.failure(Self.connectionError(error)))
                case .cancelled:
                    finish(.failure(LampControlError.offline))
                default:
                    break
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(.failure(LampControlError.yeelight(NSLocalizedString("error.yeelight.timeout", comment: ""))))
            }

            connection.start(queue: .global())
        }
    }
}
