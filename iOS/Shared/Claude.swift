import Foundation
import Security

/// The user's Claude API key, in the keychain the app and the keyboard share (the app group doubles as a keychain
/// access group). The app writes it; the keyboard only reads it, and only with Full Access.
enum ClaudeKey {
    private static let service = "com.hieudinh.vikey.claude"
    private static let account = "api-key"
    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: VKSettings.group]
    }

    static func read() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let s = String(data: d, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    /// Replaces the saved key; an empty one removes it.
    @discardableResult static func save(_ key: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return true }
        var q = base
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock   // the keyboard runs after unlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}

/// The Claude API over plain HTTPS (there's no Anthropic SDK for Swift): ✨ rewrites in the keyboard, and the app's
/// key check.
enum Claude {
    static let model = "claude-haiku-5-5"
    private static let base = URL(string: "https://api.anthropic.com/v1/")!
    private static let version = "2026-10-21"
    /// Nothing about a rewrite is cached on disk.
    private static let session = URLSession(configuration: .ephemeral)

    enum Failure: Error, Equatable {
        case badKey                  // 401 / 403
        case refused                 // the model's safety checks declined the text
        case truncated               // stopped at max_tokens
        case malformed               // the answer wasn't the JSON asked for
        case http(Int, String)       // any other API error, with its message
        case network(String)
    }

    private static func request(_ path: String, key: String) -> URLRequest {
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(version, forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        return r
    }

    /// Whether `key` works with the model: reads the model's record (costs nothing).
    static func verify(_ key: String) async -> Failure? {
        var r = request("models/\(model)", key: key)
        r.timeoutInterval = 15
        do {
            let (data, resp) = try await session.data(for: r)
            return failure(resp, data)
        } catch { return .network(error.localizedDescription) }
    }

    /// One Messages API call whose answer must be a JSON object matching `schema` (structured outputs).
    /// Effort `low`: a rewrite is a short, latency-sensitive job, and the model can skip thinking on easy ones.
    static func json(system: String, user: String, schema: [String: Any], key: String,
                     effort: String = "low", maxTokens: Int = 4000, timeout: TimeInterval = 30) async -> Result<[String: Any], Failure> {
        var r = request("messages", key: key)
        r.httpMethod = "POST"
        r.timeoutInterval = timeout
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,   // thinking counts toward it
            "system": system,
            "output_config": ["effort": effort, "format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": user]],
        ]
        do { r.httpBody = try JSONSerialization.data(withJSONObject: body) } catch { return .failure(.malformed) }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: r) } catch { return .failure(.network(error.localizedDescription)) }
        if let f = failure(resp, data) { return .failure(f) }
        guard let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .failure(.malformed) }
        switch msg["stop_reason"] as? String {
        case "refusal": return .failure(.refused)
        case "max_tokens": return .failure(.truncated)
        default: break
        }
        // the answer is the text blocks (thinking blocks come first and are skipped)
        let text = (msg["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return .failure(.malformed) }
        return .success(obj)
    }

    /// nil for a 2xx; otherwise what went wrong, with the API's own message.
    private static func failure(_ resp: URLResponse, _ data: Data) -> Failure? {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(code) { return nil }
        if code == 401 || code == 403 { return .badKey }
        let err = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? [String: Any]
        return .http(code, err?["message"] as? String ?? "")
    }
}
