import Foundation

enum HostError: Error { case timeout, failed(Error) }

@main
struct HostMain {
    static func main() {
        let serviceName = ProcessInfo.processInfo.environment["NOTCHKIT_XPC_SERVICE_NAME"]
            ?? "com.notchkit.prototype.xpcservice"

        let conn = NSXPCConnection(serviceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: EchoServiceProtocol.self)
        conn.resume()

        var replyData: Data?
        var failure: Error?
        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            failure = error
        } as! EchoServiceProtocol

        proxy.echo(Data("host".utf8)) { data in
            replyData = data
        }

        let deadline = Date().addingTimeInterval(5)
        while replyData == nil && failure == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        if let failure {
            print("HOST_XPC_FAIL error=\(failure)")
            exit(1)
        }
        if let replyData {
            print("HOST_XPC_OK reply=\(String(data: replyData, encoding: .utf8) ?? "<binary>")")
            exit(0)
        }
        print("HOST_XPC_TIMEOUT")
        exit(2)
    }
}