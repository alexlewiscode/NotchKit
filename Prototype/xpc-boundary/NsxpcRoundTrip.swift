import Foundation

// Codable model. It is NOT an Obj-C type and does NOT cross NSXPC directly.
struct Greeting: Codable, Equatable {
    var text: String
    var count: Int
}

// The only vocabulary NSXPCInterface understands: an @objc protocol whose
// arguments are Obj-C representable. `Data` carries the JSON-encoded model.
@objc protocol RoundTripProtocol {
    func echo(_ payload: Data, withReply reply: @escaping (Data) -> Void)
}

final class Service: NSObject, RoundTripProtocol {
    func echo(_ payload: Data, withReply reply: @escaping (Data) -> Void) {
        guard let greeting = try? JSONDecoder().decode(Greeting.self, from: payload) else {
            reply(Data())
            return
        }
        let out = Greeting(text: greeting.text.uppercased(), count: greeting.count + 1)
        reply((try? JSONEncoder().encode(out)) ?? Data())
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service = Service()
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        // The exported interface must be built from the @objc protocol.
        conn.exportedInterface = NSXPCInterface(with: RoundTripProtocol.self)
        conn.exportedObject = service
        conn.resume()
        return true
    }
}

func main() -> Int32 {
    // Anonymous listener + listenerEndpoint: a real NSXPC round trip with no
    // launchd registration, no bundle, no signing. Fully headless.
    let listener = NSXPCListener.anonymous()
    let delegate = ListenerDelegate()
    listener.delegate = delegate
    listener.resume()

    let conn = NSXPCConnection(listenerEndpoint: listener.endpoint)
    conn.remoteObjectInterface = NSXPCInterface(with: RoundTripProtocol.self)
    conn.resume()

    let input = Greeting(text: "hello", count: 41)
    guard let payload = try? JSONEncoder().encode(input) else {
        print("ROUND_TRIP_FAIL encode")
        return 3
    }

    var result: Greeting?
    var failure: Error?
    let proxy = conn.remoteObjectProxyWithErrorHandler { error in
        failure = error
    } as! RoundTripProtocol

    proxy.echo(payload) { data in
        result = try? JSONDecoder().decode(Greeting.self, from: data)
    }

    let deadline = Date().addingTimeInterval(5)
    while result == nil && failure == nil && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    if let failure {
        print("ROUND_TRIP_FAIL error=\(failure)")
        return 1
    }
    guard let result else {
        print("ROUND_TRIP_TIMEOUT")
        return 2
    }

    let expected = Greeting(text: "HELLO", count: 42)
    print("ROUND_TRIP_OK input=\(input) output=\(result)")
    return result == expected ? 0 : 4
}

exit(main())