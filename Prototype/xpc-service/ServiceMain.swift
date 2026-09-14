import Foundation

@main
struct XPCServiceMain {
    static func main() {
        // XPC service entry point: listen on this service's mach port.
        let listener = NSXPCListener.service()
        let delegate = ServiceDelegate()
        listener.delegate = delegate
        listener.resume()
        RunLoop.main.run()
    }
}