//
//  Payload.swift
//  SwiftPhoenixClient
//

import Swift

public class Payload {
    let topic: String
    let event: String
    let message: Message

    /**
     Initializes a formatted Payload
     - parameter topic:   String topic name
     - parameter event:   String event name
     - parameter message: Message payload
     - returns: Payload
     */
    public init(topic: String, event: String, message: Message) {
        (self.topic, self.event, self.message) = (topic, event, message)
    }
}
