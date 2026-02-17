#if canImport(Network)
import Foundation
import Network
import Logging

/// A TCP transport that advertises via Bonjour and exchanges newline-delimited JSON-RPC.
public final class TCPBonjourTransport: Transport, @unchecked Sendable {
    /// DNS-SD service type for MCP over TCP.
    public static let serviceType = "_mcp._tcp"

    public let server: MCPServer
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.TCPBonjourTransport")

    /// Optional override for the advertised Bonjour service name.
    /// When nil, the transport uses `server.serverName`.
    public let serviceName: String?
    public let serviceType: String
    public let serviceDomain: String
    public let acceptLocalOnly: Bool
    public let preferIPv4: Bool
    public private(set) var port: UInt16?

    private let queue = DispatchQueue(label: "com.cocoanetics.SwiftMCP.TCPBonjourTransport")
    private let state = TransportState()
    internal lazy var sessionManager = SessionManager(transport: self)

    private actor TransportState {
        private(set) var isRunning: Bool = false
        private var listener: NWListener?
        private var connections: [UUID: NWConnection] = [:]
        private var runContinuation: CheckedContinuation<Void, Never>?

        func running() -> Bool {
            isRunning
        }

        func start(listener: NWListener) {
            self.listener = listener
            isRunning = true
        }

        func stop() {
            isRunning = false
            listener?.cancel()
            listener = nil
            for connection in connections.values {
                connection.cancel()
            }
            connections.removeAll()
            if let continuation = runContinuation {
                runContinuation = nil
                continuation.resume()
            }
        }

        func waitUntilStopped() async {
            guard isRunning else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                runContinuation = continuation
            }
        }

        func addConnection(id: UUID, connection: NWConnection) {
            connections[id] = connection
        }

        func removeConnection(id: UUID) {
            connections.removeValue(forKey: id)
        }

        func connection(for id: UUID) -> NWConnection? {
            connections[id]
        }
    }

    public init(
        server: MCPServer,
        serviceName: String? = nil,
        serviceType: String = TCPBonjourTransport.serviceType,
        serviceDomain: String = "local.",
        port: UInt16? = nil,
        acceptLocalOnly: Bool = true,
        preferIPv4: Bool = true
    ) {
        self.server = server
        self.serviceName = serviceName
        self.serviceType = serviceType
        self.serviceDomain = serviceDomain
        self.port = port
        self.acceptLocalOnly = acceptLocalOnly
        self.preferIPv4 = preferIPv4
    }

    public convenience init(server: MCPServer) {
        self.init(
            server: server,
            serviceName: nil,
            serviceType: TCPBonjourTransport.serviceType,
            serviceDomain: "local.",
            port: nil,
            acceptLocalOnly: true,
            preferIPv4: true
        )
    }

    public func start() async throws {
        if await state.running() {
            return
        }

        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = acceptLocalOnly
        parameters.includePeerToPeer = false
        if preferIPv4,
           let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }

        let listener: NWListener
        if let port {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw TransportError.bindingFailed("Invalid TCP port: \(port)")
            }
            listener = try NWListener(using: parameters, on: nwPort)
        } else {
            listener = try NWListener(using: parameters)
        }

        let advertisedName = serviceName ?? server.serverName
        listener.service = NWListener.Service(name: advertisedName, type: serviceType, domain: serviceDomain)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener.stateUpdateHandler = { [weak self] newState in
            self?.handleListenerState(newState, listener: listener)
        }

        await state.start(listener: listener)
        listener.start(queue: queue)
    }

    public func run() async throws {
        try await start()
        await state.waitUntilStopped()
    }

    public func stop() async throws {
        await state.stop()
    }

    /// Broadcasts a log message to all connected sessions.
    public func broadcastLog(_ message: LogMessage) async {
        await sessionManager.broadcastLog(message)
    }

    public func send(_ data: Data) async throws {
        precondition(Session.current != nil)
        let currentSession = Session.current!
        let sameTransport: Bool
        if let transport = await currentSession.transport {
            sameTransport = transport === self
        } else {
            sameTransport = false
        }
        precondition(sameTransport)

        guard let connection = await state.connection(for: currentSession.id) else {
            throw TransportError.bindingFailed("TCP connection unavailable for session \(currentSession.id)")
        }

        let string = String(data: data, encoding: .utf8) ?? ""
        logger.trace("TCP OUT:\n\n\(string)")

        var out = data
        let newline = "\n".data(using: .utf8) ?? Data()
        out.append(newline)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: out, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func handleListenerState(_ state: NWListener.State, listener: NWListener) {
        switch state {
        case .ready:
            if let boundPort = listener.port?.rawValue {
                port = boundPort
            }
            logger.info("TCP+Bonjour transport ready on port \(port.map(String.init) ?? "unknown")")
        case .failed(let error):
            logger.error("TCP+Bonjour listener failed: \(error)")
        case .cancelled:
            logger.info("TCP+Bonjour listener cancelled")
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let connectionID = UUID()

        Task {
            let session = await sessionManager.session(id: connectionID)

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.logger.info("TCP connection ready: \(connectionID)")
                case .failed(let error):
                    self.logger.error("TCP connection failed (\(connectionID)): \(error)")
                    Task {
                        await self.cleanupConnection(id: connectionID)
                    }
                case .cancelled:
                    Task {
                        await self.cleanupConnection(id: connectionID)
                    }
                default:
                    break
                }
            }

            await state.addConnection(id: connectionID, connection: connection)
            connection.start(queue: queue)
            startReceiveLoop(connection: connection, session: session, connectionID: connectionID)
        }
    }

    private func cleanupConnection(id: UUID) async {
        await state.removeConnection(id: id)
        await sessionManager.removeSession(id: id)
    }

    private func startReceiveLoop(connection: NWConnection, session: Session, connectionID: UUID) {
        let lineBuffer = LineBuffer()
        receiveNext(connection: connection, session: session, connectionID: connectionID, lineBuffer: lineBuffer)
    }

    private func receiveNext(
        connection: NWConnection,
        session: Session,
        connectionID: UUID,
        lineBuffer: LineBuffer
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                Task {
                    await lineBuffer.append(data)
                    let lines = await lineBuffer.processLines()
                    for line in lines {
                        await self.handleLine(line, session: session)
                    }
                }
            }

            if let error {
                self.logger.error("TCP receive error (\(connectionID)): \(error)")
                Task {
                    await self.cleanupConnection(id: connectionID)
                }
                return
            }

            if isComplete {
                Task {
                    if let remaining = await lineBuffer.getRemaining() {
                        await self.handleLine(remaining, session: session)
                    }
                    await self.cleanupConnection(id: connectionID)
                }
                return
            }

            self.receiveNext(connection: connection, session: session, connectionID: connectionID, lineBuffer: lineBuffer)
        }
    }

    private func handleLine(_ line: String, session: Session) async {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = line.data(using: .utf8) else {
            return
        }

        logger.trace("TCP IN:\n\n\(line)")

        await session.work { _ in
            do {
                let messages = try JSONRPCMessage.decodeMessages(from: data)
                let responses = await server.processBatch(messages)
                guard !responses.isEmpty else { return }
                try await send(responses)
            } catch {
                logger.error("Error decoding TCP message: \(error)")
            }
        }
    }
}
#else
import Foundation
import Logging

/// Stub implementation for platforms without Network framework.
public final class TCPBonjourTransport: Transport, @unchecked Sendable {
    /// DNS-SD service type for MCP over TCP.
    public static let serviceType = "_mcp._tcp"

    public let server: MCPServer
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.TCPBonjourTransport")

    /// Optional override for the advertised Bonjour service name.
    /// When nil, the transport uses `server.serverName`.
    public let serviceName: String?
    public let serviceType: String
    public let serviceDomain: String
    public let acceptLocalOnly: Bool
    public let preferIPv4: Bool
    public private(set) var port: UInt16?

    public init(
        server: MCPServer,
        serviceName: String? = nil,
        serviceType: String = TCPBonjourTransport.serviceType,
        serviceDomain: String = "local.",
        port: UInt16? = nil,
        acceptLocalOnly: Bool = true,
        preferIPv4: Bool = true
    ) {
        self.server = server
        self.serviceName = serviceName
        self.serviceType = serviceType
        self.serviceDomain = serviceDomain
        self.port = port
        self.acceptLocalOnly = acceptLocalOnly
        self.preferIPv4 = preferIPv4
    }

    public convenience init(server: MCPServer) {
        self.init(
            server: server,
            serviceName: nil,
            serviceType: TCPBonjourTransport.serviceType,
            serviceDomain: "local.",
            port: nil,
            acceptLocalOnly: true,
            preferIPv4: true
        )
    }

    public func start() async throws {
        throw TransportError.bindingFailed("TCP+Bonjour transport requires the Network framework.")
    }

    public func run() async throws {
        try await start()
    }

    public func stop() async throws {
    }

    public func send(_ data: Data) async throws {
    }
}
#endif
