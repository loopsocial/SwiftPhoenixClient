//
//  Socket.swift
//  SwiftPhoenixClient
//

import Swift
import Starscream
import Foundation

public protocol SocketDelegate: class {
    func socketDidOpen(_ socket: Socket)
    func socketDidClose(_ socket: Socket)
    func socketDidError(_ socket: Socket, error: Error)
}

public class Socket: WebSocketDelegate {
    var conn: WebSocket?
    var endPoint: String?
    var channels: [Channel] = []

    var sendBuffer: [Void] = []
    var sendBufferTimer = Timer()
    let flushEveryMs = 1.0

    var reconnectTimer = Timer()
    let reconnectAfterMs = 1.0

    var heartbeatTimer = Timer()
    let heartbeatDelay = 30.0

    var messageReference: UInt64 = UInt64.min // 0 (max: 18,446,744,073,709,551,615)

    public weak var delegate: SocketDelegate?

    /**
     Indicates if connection is established
     - returns: Bool
     */
    public var isConnected: Bool {
        return conn?.isConnected ?? false
    }

    /**
     Initializes a Socket connection
     - parameter domainAndPort: Phoenix server root path and proper port
     - parameter path:          Websocket path on Phoenix Server
     - parameter transport:     Transport for Phoenix.Server - traditionally "websocket"
     - parameter prot:          Connection protocol - default is HTTP
     - returns: Socket
     */
    public init(domainAndPort:String, path:String, transport:String, prot:String = "http", params: [String: Any]? = nil) {
        self.endPoint = Path.endpointWithProtocol(prot: prot, domainAndPort: domainAndPort, path: path, transport: transport)

        if let parameters = params {
            self.endPoint = self.endPoint! + "?" + parameters.map({ "\($0.0)=\($0.1)" }).joined(separator: "&")
        }

        resetBufferTimer()
        reconnect()
    }

    deinit {
        close()
    }

    /**
     Closes socket connection
     - parameter callback: Function to run after close
     */
    public func close(callback: (() -> ()) = {}) {
        if let connection = self.conn {
            connection.delegate = nil
            connection.disconnect()
        }

        invalidateTimers()
        callback()
    }

    /**
     Invalidate open timers to allow socket to be deallocated when closed
     */
    func invalidateTimers() {
        heartbeatTimer.invalidate()
        reconnectTimer.invalidate()
        sendBufferTimer.invalidate()

        heartbeatTimer = Timer()
        reconnectTimer = Timer()
        sendBufferTimer = Timer()
    }

    /**
     Initializes a 30s timer to let Phoenix know this device is still alive
     */
    func startHeartbeatTimer() {
        heartbeatTimer.invalidate()
        heartbeatTimer = Timer.scheduledTimer(timeInterval: heartbeatDelay, target: self, selector: #selector(heartbeat), userInfo: nil, repeats: true)
    }

    /**
     Heartbeat payload (Message) to send with each pulse
     */
    @objc func heartbeat() {
        let message = Message(message: ["body": "Pong"])
        let payload = Payload(topic: "phoenix", event: "heartbeat", message: message)
        send(data: payload)
    }

    /**
     Reconnects to a closed socket connection
     */
    @objc public func reconnect() {
        close() {
            self.conn = WebSocket(url: URL(string: self.endPoint!)!)
            if let connection = self.conn {
                connection.delegate = self
                connection.connect()
            }
        }
    }

    /**
     Resets the message buffer timer and invalidates any existing ones
     */
    func resetBufferTimer() {
        sendBufferTimer.invalidate()
        sendBufferTimer = Timer.scheduledTimer(timeInterval: flushEveryMs, target: self, selector: #selector(flushSendBuffer), userInfo: nil, repeats: true)
        sendBufferTimer.fire()
    }

    /**
     Kills reconnect timer and joins all open channels
     */
    func onOpen() {
        delegate?.socketDidOpen(self)
        reconnectTimer.invalidate()
        startHeartbeatTimer()
        rejoinAll()
    }

    /**
     Starts reconnect timer onClose
     - parameter event: String event name
     */
    func onClose(event: String) {
        delegate?.socketDidClose(self)
        reconnectTimer.invalidate()
        reconnectTimer = Timer.scheduledTimer(timeInterval: reconnectAfterMs, target: self, selector: #selector(reconnect), userInfo: nil, repeats: true)
    }

    /**
     Triggers error event
     - parameter error: NSError
     */
    func onError(error: NSError) {
        print("Error: \(error)")
        delegate?.socketDidError(self, error: error)
        for chan in channels {
            let msg = Message(message: ["body": error.localizedDescription])
            chan.trigger(triggerEvent: "error", msg: msg)
        }
    }

    /**
     Rejoins all Channel instances
     */
    func rejoinAll() {
        for chan in channels {
            rejoin(chan: chan)
        }
    }

    /**
     Rejoins a given Phoenix Channel
     - parameter chan: Channel
     */
    func rejoin(chan: Channel) {
        chan.reset()
        let payload = Payload(topic: chan.topic, event: "phx_join", message: chan.message)
        send(data: payload)
        chan.callback(chan)
    }

    /**
     Joins socket
     - parameter topic:    String topic name
     - parameter message:  Message payload
     - parameter callback: Function to trigger after join
     */
    public func join(topic: String, message: Message, callback: @escaping (Channel) -> ()) {
        let chan = Channel(topic: topic, message: message, callback: callback, socket: self)
        channels.append(chan)
        if isConnected {
            print("joining")
            rejoin(chan: chan)
        }
    }

    /**
     Leave open socket
     - parameter topic:   String topic name
     - parameter message: Message payload
     */
    public func leave(topic: String, message: Message) {
        let leavingMessage = Message(subject: "status", body: "leaving")
        let payload = Payload(topic: topic, event: "phx_leave", message: leavingMessage)
        send(data: payload)
        var newChannels: [Channel] = []
        for channel in channels {
            if !channel.isMember(topic: topic) {
                newChannels.append(channel)
            }
        }
        channels = newChannels
    }

    /**
     Send payload over open socket
     - parameter data: Payload
     */
    public func send(data: Payload) {
        let callback: (Payload) -> () = { payload in
            guard let connection = self.conn else { return }
            let json = self.payloadToJson(payload: payload)
            print("json: \(json)")
            connection.write(string: json)
        }

        if isConnected {
            callback(data)
        } else {
            sendBuffer.append(callback(data))
        }
    }

    /**
     Flush message buffer
     */
    @objc func flushSendBuffer() {
        guard isConnected, !sendBuffer.isEmpty else { return }

        for callback in sendBuffer {
            callback
        }
        sendBuffer = []
        resetBufferTimer()
    }

    /**
     Trigger event on message received
     - parameter payload: Payload
     */
    func onMessage(payload: Payload) {
        let (topic, event, message) = (payload.topic, payload.event, payload.message)
        for chan in channels {
            if chan.isMember(topic: topic) {
                chan.trigger(triggerEvent: event, msg: message)
            }
        }
    }

    // WebSocket Delegate Methods

    public func websocketDidReceiveMessage(socket: WebSocket, text: String) {
        print("socket message: \(text)")

        guard let data = text.data(using: String.Encoding.utf8)
            , let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                print("Unable to parse JSON: \(text)")
                return
        }

        guard let topic = json["topic"] as? String
            , let event = json["event"] as? String
            , let msg = json["payload"] as? [String: Any] else {
                print("No phoenix message: \(text)")
                return
        }

        let messagePayload = Payload(topic: topic, event: event, message: Message(message: msg))
        onMessage(payload: messagePayload)
    }

    public func websocketDidReceiveData(socket: WebSocket, data: Data) {
        print("got some data: \(data.count)")
    }

    public func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        if let err = error { onError(error: err) }
        print("socket closed: \(String(describing: error?.localizedDescription))")
        onClose(event: "reason: \(String(describing: error?.localizedDescription))")
    }

    public func websocketDidConnect(socket: WebSocket) {
        print("socket opened")
        onOpen()
    }

    public func websocketDidWriteError(error: NSError?) {
        onError(error: error!)
    }

    func unwrappedJsonString(string: String?) -> String {
        return string ?? ""
    }

    func makeRef() -> UInt64 {
        let newRef = messageReference + 1
        messageReference = (newRef == UInt64.max) ? 0 : newRef
        return newRef
    }

    func payloadToJson(payload: Payload) -> String {
        let ref = makeRef()
        var json: [String: Any] = [
            "topic": payload.topic,
            "event": payload.event,
            "ref": "\(ref)"
        ]

        if let msg = payload.message.message {
            json["payload"] = msg
        } else {
            json["payload"] = payload.message.toDictionary()
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [])
            , let jsonString = String(data: jsonData, encoding: String.Encoding.utf8) else { return "" }

        return jsonString
    }
}
