import Foundation

@objc public protocol NativeExtensionSceneService {
    func handshake(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
    func crashForTesting()
}
