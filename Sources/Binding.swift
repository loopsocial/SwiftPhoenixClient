//
//  Binding.swift
//  SwiftPhoenixClient
//

import Swift

final class Binding {
    let event: String
    let callback: (Message) -> ()

    /**
     Initializes an object for handling event/callback bindings
     - parameter event:    String indicating event name
     - parameter callback: Function to run on given event
     - returns: Tuple containing event and callback function
     */
    @discardableResult
    init(event: String, callback: @escaping (Message) -> ()) {
        self.event = event
        self.callback = callback
        create()
    }

    /**
     Creates a Binding object holding event/callback details
     - returns: Tuple containing event and callback function
     */
    @discardableResult
    func create() -> (String, (Message) -> ()) {
        return (event, callback)
    }
}
