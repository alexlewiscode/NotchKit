import Foundation

@objc protocol EchoServiceProtocol {
    func echo(_ payload: Data, withReply reply: @escaping (Data) -> Void)
    // Lifecycle observability: prove a separate process exists.
    func processIdentifier(withReply reply: @escaping (Int32) -> Void)
    // Lifecycle observability: simulate a crash to trigger interruptionHandler.
    func crash()
}