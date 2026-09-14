import Foundation

// EXPECTED TO FAIL AT COMPILE TIME.
// A Codable Swift struct is not an Obj-C representable type, so it cannot be a
// method parameter of an @objc protocol (the only thing NSXPCInterface accepts).
struct Payload: Codable {
    var value: Int
}

@objc protocol WireProtocol {
    func send(_ payload: Payload, withReply reply: @escaping (Bool) -> Void)
}