import Foundation

final class CleanupProtocol: URLProtocol {
    static var response: [String: Any] = [:]
    static var sent: [String: Any] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var collected = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                collected.append(contentsOf: bytes.prefix(count))
            }
            data = collected
        }
        Self.sent = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] ?? [:]
        let reply = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: Self.response))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct CleanupContracts {
    static func main() async throws {
        URLProtocol.registerClass(CleanupProtocol.self)
        defer { URLProtocol.unregisterClass(CleanupProtocol.self) }
        let provider = OpenAICompatibleCleanup(backend: .anthropic, apiKey: "offline-fixture")
        let raw = "um hello world"
        CleanupProtocol.response = ["stop_reason": "end_turn", "content": [
            ["type": "thinking", "thinking": "private reasoning must not enter dictation"],
            ["type": "text", "text": "Hello "],
            ["type": "text", "text": "world."],
        ]]
        let cleaned = try await provider.cleanup(raw, style: .default, context: "")
        precondition(cleaned == "Hello world.", "Thinking blocks must be skipped; all text blocks must survive")
        precondition(CleanupProtocol.sent["model"] as? String == CleanupFactory.defaultModel(for: .anthropic))
        precondition(CleanupProtocol.sent["temperature"] == nil)
        for stop in ["refusal", "max_tokens", "model_context_window_exceeded"] {
            CleanupProtocol.response = ["stop_reason": stop, "content": [["type": "text", "text": "partial or refused"]]]
            let preserved = try await provider.cleanup(raw, style: .default, context: "")
            precondition(preserved == raw, "Never paste a refused or incomplete cleanup")
        }
        CleanupProtocol.response = ["stop_reason": "end_turn", "content": [["type": "thinking", "thinking": "reasoning only"]]]
        let preserved = try await provider.cleanup(raw, style: .default, context: "")
        precondition(preserved == raw)
        print("PASS cleanup: thinking/text blocks, incomplete/refused fallback, request/default contract")
    }
}
