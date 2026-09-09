import Foundation
import Testing
@testable import Glossa

private let successfulStream = """
: keep-alive\r
\r
data: {"choices":[{"index":0,"delta":{"reasoning_content":"hidden"}}]}

data: {"choices":[{"index":0,"delta":{"content":"你好 **world**"}}]}

data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: {"choices":[],"usage":{"total_tokens":10}}

data: [DONE]


"""

@Test func compatibleRequestsShareConfigurationWithoutLeakingDeepSeekParameters() throws {
    let deepSeek = try APIConfiguration(baseURL: "https://API.DEEPSEEK.COM:443/v1/", model: " deepseek-v4-flash ").validated()
    let request = try ChatCompletionsClient.request(configuration: deepSeek, key: "test-key", prompt: "Define 你好")
    #expect(request.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    let requestData = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
    #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
    #expect(body["stream"] as? Bool == true)
    let custom = APIConfiguration(baseURL: "https://example.com/v1", model: "my-model")
    let other = try ChatCompletionsClient.request(configuration: custom, key: "different-key", prompt: "Define hello")
    let otherData = try #require(other.httpBody)
    let otherBody = try #require(JSONSerialization.jsonObject(with: otherData) as? [String: Any])
    #expect(otherBody["thinking"] == nil)
    #expect(otherBody["model"] as? String == "my-model")
    for url in ["http://example.com", "https://key@example.com", "https://example.com?key=x", "https://example.com/#x", "garbage"] {
        #expect(throws: APIError.invalidConfiguration) { try APIConfiguration(baseURL: url, model: "model").validated() }
    }
    #expect(throws: APIError.invalidKey) { try ChatCompletionsClient.request(configuration: custom, key: "key\r\nInjected: header", prompt: "word") }
}

@Test func streamingHandlesUnicodeKeepAliveUsageAndTruncationWithMemoryBounds() throws {
    var stream = CompletionStream()
    for byte in successfulStream.utf8 { _ = try stream.consume(byte) }
    try stream.validateCompletion()
    #expect(stream.text == "你好 **world**")

    var truncated = CompletionStream()
    for byte in successfulStream.replacingOccurrences(of: "\"stop\"", with: "\"length\"").utf8 { _ = try truncated.consume(byte) }
    #expect(throws: APIError.incomplete) { try truncated.validateCompletion() }
    var disconnected = CompletionStream()
    for byte in successfulStream.replacingOccurrences(of: "data: [DONE]", with: "").utf8 { _ = try disconnected.consume(byte) }
    #expect(throws: APIError.incomplete) { try disconnected.validateCompletion() }
    var malformed = CompletionStream()
    #expect(throws: APIError.invalidResponse) {
        for byte in "data: not-json\n\n".utf8 { _ = try malformed.consume(byte) }
    }
    var oversized = CompletionStream()
    #expect(throws: APIError.responseTooLarge) {
        for _ in 0...65_536 { _ = try oversized.consume(65) }
    }
}

@Test func keychainKeysAreScopedToBaseURLAndCanBeReplacedAndDeleted() throws {
    let first = APIConfiguration(baseURL: "https://glossa-test.invalid/\(UUID().uuidString)", model: "test")
    let second = APIConfiguration(baseURL: first.baseURL + "/other", model: "test")
    defer { try? APIKeyStore.delete(for: first) }
    #expect(try APIKeyStore.containsKey(for: first) == false)
    try APIKeyStore.save("dummy-key-one", for: first)
    #expect(try APIKeyStore.containsKey(for: first))
    #expect(try APIKeyStore.read(for: first) == "dummy-key-one")
    #expect(throws: APIError.missingKey) { try APIKeyStore.read(for: second) }
    try APIKeyStore.save("dummy-key-two", for: first)
    #expect(try APIKeyStore.read(for: first) == "dummy-key-two")
    try APIKeyStore.delete(for: first)
    #expect(try APIKeyStore.containsKey(for: first) == false)
    #expect(throws: APIError.missingKey) { try APIKeyStore.read(for: first) }
}

private final class OfflineProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = request.url?.lastPathComponent == "unauthorized" ? 401 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(successfulStream.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor ReceivedText {
    var value = ""
    func set(_ value: String) { self.value = value }
}

@Test func realURLSessionPathUsesOfflineTransportAndReportsHTTPFailure() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OfflineProtocol.self]
    let received = ReceivedText()
    try await ChatCompletionsClient.stream(request: URLRequest(url: URL(string: "https://glossa-test.invalid/success")!),
                                           configuration: configuration) { await received.set($0) }
    #expect(await received.value == "你好 **world**")
    await #expect(throws: APIError.http(401)) {
        try await ChatCompletionsClient.stream(request: URLRequest(url: URL(string: "https://glossa-test.invalid/unauthorized")!),
                                               configuration: configuration) { _ in }
    }
}

private actor PendingLookup {
    private var resume: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func pause() async {
        await withCheckedContinuation { resume = $0; started = true }
    }
    func finish() { resume?.resume(); resume = nil }
}

@MainActor @Test func dismissalRejectsLateResponsesEvenWhenTransportIgnoresCancellation() async {
    let pending = PendingLookup()
    let completed = AsyncStream<Void>.makeStream()
    let model = LookupController(settings: isolatedLookupSettings()) { _, update in
        await pending.pause()
        await update("Late result")
        completed.continuation.yield(())
        completed.continuation.finish()
    }
    model.submit("word")
    while !(await pending.started) { await Task.yield() }
    #expect(model.isLoading)
    model.dismiss()
    await pending.finish()
    for await _ in completed.stream { }
    #expect(model.answer.isEmpty)
    #expect(model.text.isEmpty)
    #expect(!model.isLoading)
    #expect(model.lookupError == nil)
}

@MainActor @Test func newQueryKeepsItsResultWhenPreviousQueryFinishesLate() async {
    let pending = PendingLookup()
    let completed = AsyncStream<String>.makeStream()
    let model = LookupController(settings: isolatedLookupSettings()) { query, update in
        if query.text == "old" { await pending.pause() }
        await update(query.text)
        completed.continuation.yield(query.text)
    }
    var results = completed.stream.makeAsyncIterator()
    model.submit("old")
    while !(await pending.started) { await Task.yield() }
    model.submit("new")
    #expect(await results.next() == "new")
    #expect(model.answer == "new")
    await pending.finish()
    #expect(await results.next() == "old")
    #expect(model.answer == "new")
    completed.continuation.finish()
    model.dismiss()
}
