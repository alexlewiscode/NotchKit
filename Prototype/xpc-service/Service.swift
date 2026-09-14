import Foundation

final class EchoService: NSObject, EchoServiceProtocol {
    func echo(_ payload: Data, withReply reply: @escaping (Data) -> Void) {
        reply(Data("svc:".utf8) + payload)
    }

    func processIdentifier(withReply reply: @escaping (Int32) -> Void) {
        reply(getpid())
    }

    func crash() {
        abort()
    }
}

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: EchoServiceProtocol.self)
        conn.exportedObject = EchoService()
        conn.resume()
        return true
    }
}