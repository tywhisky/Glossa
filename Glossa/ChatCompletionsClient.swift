import Foundation

struct ChatCompletionsClient: Sendable {
    static func request(configuration: APIConfiguration, key: String, prompt: String) throws -> URLRequest {
        let configuration = try configuration.validated()
        guard APIKeyStore.isValid(key) else { throw APIError.invalidKey }
        guard !prompt.isEmpty, prompt.utf8.count <= 65_536 else { throw APIError.invalidPrompt }
        var request = URLRequest(url: try configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["model": configuration.model, "stream": true, "max_tokens": 2_048,
                                   "messages": [["role": "user", "content": prompt]]]
        if configuration.isDeepSeek { body["thinking"] = ["type": "disabled"] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func lookup(_ query: PreparedLookup, update: @escaping @Sendable (String) async -> Void) async throws {
        try Task.checkCancellation()
        let request = try request(configuration: query.configuration, key: APIKeyStore.read(for: query.configuration),
                                  prompt: query.prompt)
        try await stream(request: request, update: update)
    }

    static func stream(request: URLRequest, configuration: URLSessionConfiguration = .ephemeral,
                       update: @escaping @Sendable (String) async -> Void) async throws {
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard response.statusCode == 200 else { throw APIError.http(response.statusCode) }
            guard response.mimeType?.lowercased() == "text/event-stream" else { throw APIError.invalidResponse }
            var decoder = CompletionStream()
            let clock = ContinuousClock()
            var lastUpdate = clock.now
            for try await byte in bytes {
                try Task.checkCancellation()
                let changed = try decoder.consume(byte)
                if changed, clock.now - lastUpdate >= .milliseconds(60) {
                    await update(decoder.text)
                    lastUpdate = clock.now
                }
                if decoder.done { break }
            }
            try Task.checkCancellation()
            await update(decoder.text)
            try decoder.validateCompletion()
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // A provider redirect must not forward the user's prompt or credentials.
        completionHandler(nil)
    }
}

// Incremental SSE decoding bounds memory even when a server never sends a newline.
struct CompletionStream {
    private var line = Data()
    private var event = Data()
    private var received = 0
    private var outputBytes = 0
    private var previousWasCR = false
    private var finishReason: String?
    private(set) var text = ""
    private(set) var done = false

    mutating func consume(_ byte: UInt8) throws -> Bool {
        received += 1
        guard received <= 1_048_576 else { throw APIError.responseTooLarge }
        if byte == 10, previousWasCR { previousWasCR = false; return false }
        previousWasCR = byte == 13
        guard byte == 10 || byte == 13 else {
            guard line.count < 65_536 else { throw APIError.responseTooLarge }
            line.append(byte)
            return false
        }
        defer { line.removeAll(keepingCapacity: true) }
        if !line.isEmpty {
            guard let value = String(data: line, encoding: .utf8) else { throw APIError.invalidResponse }
            if value.hasPrefix("data:") {
                var data = value.dropFirst(5)
                if data.first == " " { data = data.dropFirst() }
                guard event.count + data.utf8.count + 1 <= 65_536 else { throw APIError.responseTooLarge }
                event.append(contentsOf: data.utf8)
                event.append(10)
            }
            return false
        }
        guard !event.isEmpty else { return false }
        defer { event.removeAll(keepingCapacity: true) }
        if String(data: event, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            done = true
            return false
        }
        let chunk: Chunk
        do { chunk = try JSONDecoder().decode(Chunk.self, from: event) }
        catch { throw APIError.invalidResponse }
        guard let choice = chunk.choices.first(where: { $0.index == 0 }) else { return false }
        if let reason = choice.finish_reason { finishReason = reason }
        guard let content = choice.delta.content, !content.isEmpty else { return false }
        outputBytes += content.utf8.count
        guard outputBytes <= 65_536 else { throw APIError.responseTooLarge }
        text += content
        return true
    }

    func validateCompletion() throws {
        guard done, finishReason == "stop" else { throw APIError.incomplete }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidResponse }
    }

    private struct Chunk: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let index: Int
            let delta: Delta
            let finish_reason: String?
        }
        struct Delta: Decodable { let content: String? }
    }
}
