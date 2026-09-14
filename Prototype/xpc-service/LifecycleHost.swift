import Foundation

@main
struct LifecycleHost {
    static func main() {
        let serviceName = ProcessInfo.processInfo.environment["NOTCHKIT_XPC_SERVICE_NAME"]
            ?? "com.notchkit.prototype.xpcservice"

        let conn = NSXPCConnection(serviceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: EchoServiceProtocol.self)
        conn.interruptionHandler = {
            print("LIFECYCLE_INTERRUPTION (remote process crashed or connection interrupted)")
            fflush(stdout)
        }
        conn.invalidationHandler = {
            print("LIFECYCLE_INVALIDATION (connection invalidated)")
            fflush(stdout)
        }
        conn.resume()

        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            print("LIFECYCLE_ERROR \(error)")
            fflush(stdout)
        } as! EchoServiceProtocol

        var pid: Int32?
        proxy.processIdentifier { pid = $0 }
        pump(until: { pid != nil }, timeout: 5)
        print("LIFECYCLE_LAUNCH remote_pid=\(pid.map(String.init) ?? "nil")")
        fflush(stdout)

        print("LIFECYCLE_CRASH_REQUEST triggering remote crash")
        fflush(stdout)
        proxy.crash()
        // Wait generously for the interruption handler.
        pump(until: { true }, timeout: 2.0)

        // Does the service relaunch on the next message?
        var newPid: Int32?
        proxy.processIdentifier { newPid = $0 }
        pump(until: { newPid != nil }, timeout: 4.0)
        print("LIFECYCLE_AFTER_CRASH remote_pid=\(newPid.map(String.init) ?? "nil")")
        fflush(stdout)

        print("LIFECYCLE_INVALIDATE_REQUEST calling invalidate()")
        fflush(stdout)
        conn.invalidate()
        pump(until: { true }, timeout: 2.0)

        print("LIFECYCLE_DONE")
        fflush(stdout)
        exit(0)
    }

    static func pump(until done: () -> Bool, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}