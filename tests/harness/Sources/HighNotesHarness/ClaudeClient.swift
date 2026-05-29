import Foundation

// Minimal Anthropic Messages API client. Just enough surface for the harness:
// a single non-streaming text request with a system prompt, a user prompt, and
// a model choice. Output is the concatenated text from the response.
//
// It's an ACTOR on purpose: each request `await`s a URLSession call, so many
// requests interleave on the actor's executor → real network concurrency,
// bounded by the harness's task group, without data races on the session.

actor ClaudeClient {
    struct Config {
        var apiKey: String
        var model: String
        var maxTokens: Int
        var endpoint: URL
        var anthropicVersion: String

        static func fromEnv(model: String = "claude-opus-4-7", maxTokens: Int = 1500) throws -> Config {
            guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
                throw ClaudeError.missingAPIKey
            }
            return Config(
                apiKey: key,
                model: model,
                maxTokens: maxTokens,
                endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
                anthropicVersion: "2023-06-01"
            )
        }
    }

    enum ClaudeError: Error, LocalizedError {
        case missingAPIKey
        case httpError(status: Int, body: String)
        case malformedResponse(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "ANTHROPIC_API_KEY is not set in the environment."
            case .httpError(let s, let b): return "Claude HTTP \(s): \(b)"
            case .malformedResponse(let r): return "Malformed Claude response: \(r)"
            }
        }
    }

    private let config: Config
    private let urlSession: URLSession

    init(config: Config) {
        self.config = config
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 180
        self.urlSession = URLSession(configuration: cfg)
    }

    /// Send a single (system, user) pair. Returns the assistant's text content.
    func respond(system: String, user: String, maxTokensOverride: Int? = nil) async throws -> String {
        var req = URLRequest(url: config.endpoint)
        req.httpMethod = "POST"
        req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(config.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": maxTokensOverride ?? config.maxTokens,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ClaudeError.malformedResponse("non-HTTP response")
        }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "(non-utf8 body)"
            throw ClaudeError.httpError(status: http.statusCode, body: body)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = obj["content"] as? [[String: Any]] else {
            throw ClaudeError.malformedResponse(String(data: data, encoding: .utf8) ?? "(non-utf8)")
        }
        // Concatenate every text block in order.
        let text = blocks.compactMap { block -> String? in
            guard let type = block["type"] as? String, type == "text" else { return nil }
            return block["text"] as? String
        }.joined()
        return text
    }
}
