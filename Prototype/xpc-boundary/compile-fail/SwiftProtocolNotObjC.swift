import Foundation

// EXPECTED TO FAIL AT COMPILE TIME.
// NSXPCInterface(with:) takes an Objective-C `Protocol`. A pure Swift protocol
// has no Obj-C runtime representation and cannot be used to build the interface.
protocol SwiftOnlyProtocol {
    func ping()
}

let interface = NSXPCInterface(with: SwiftOnlyProtocol.self)