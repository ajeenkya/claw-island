import Foundation

/// Events emitted during streaming
enum StreamEvent {
    /// A complete sentence ready for TTS
    case sentence(String)
    /// Stream finished — full accumulated response
    case done(String)
    /// Error during streaming
    case error(Error)
}

/// Client for sending messages to the OpenClaw gateway via chat completions API.
///
/// Routes through the gateway's full agent session system when model is "openclaw",
/// giving the agent access to tools, memory, skills, and conversation history.
class OpenClawClient {
    private let config: MiloConfig
    
    /// Local conversation buffer — keeps the last N turns for multi-turn context.
    private var conversationBuffer: [(role: String, content: String)] = []
    
    /// Reusable URLSession with keep-alive for lower latency
    private let session: URLSession

    init(config: MiloConfig) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpMaximumConnectionsPerHost = 2
        sessionConfig.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Streaming API (primary path)
    
    /// Stream a message to OpenClaw, yielding sentences as they complete.
    /// Returns an AsyncStream of StreamEvents — each `.sentence` is ready for immediate TTS.
    func streamMessage(text: String, screenshotPath: String?, runtimeContext: String?) -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            Task {
                do {
                    let request = try buildRequest(text: text, screenshotPath: screenshotPath, runtimeContext: runtimeContext, stream: true)
                    
                    miloLog("📡 Streaming to OpenClaw (model: \(config.model)): \(text)")
                    
                    let (bytes, response) = try await session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        miloLog("❌ Stream API error \(statusCode)")
                        continuation.yield(.error(OpenClawError.apiError(statusCode: statusCode, body: "Stream error")))
                        continuation.finish()
                        return
                    }
                    
                    var fullResponse = ""
                    var sentenceBuffer = ""
                    
                    for try await line in bytes.lines {
                        // SSE format: "data: {...}" or "data: [DONE]"
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        
                        if payload == "[DONE]" { break }
                        
                        // Parse the delta content from the SSE chunk
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first,
                              let delta = first["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            continue
                        }
                        
                        fullResponse += content
                        sentenceBuffer += content
                        
                        // Check for sentence boundaries and yield complete sentences
                        while let sentence = extractSentence(from: &sentenceBuffer) {
                            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                miloLog("🔊 Sentence ready: \(trimmed.prefix(60))...")
                                continuation.yield(.sentence(trimmed))
                            }
                        }
                    }
                    
                    // Flush any remaining text in the buffer
                    let remaining = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remaining.isEmpty {
                        miloLog("🔊 Final fragment: \(remaining.prefix(60))...")
                        continuation.yield(.sentence(remaining))
                    }
                    
                    // Update conversation buffer with full response
                    appendToBuffer(role: "user", content: text)
                    appendToBuffer(role: "assistant", content: fullResponse)
                    
                    miloLog("✅ Stream complete: \(fullResponse.count) chars")
                    continuation.yield(.done(fullResponse))
                    continuation.finish()
                    
                } catch {
                    miloLog("❌ Stream error: \(error)")
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }
        }
    }
    
    // MARK: - Non-streaming fallback
    
    /// Send a non-streaming message using the same config-driven routing as streaming.
    func sendMessage(text: String, screenshotPath: String?, runtimeContext: String?) async throws -> String {
        let request = try buildRequest(text: text, screenshotPath: screenshotPath, runtimeContext: runtimeContext, stream: false)
        
        miloLog("📡 Sending to OpenClaw (non-streaming): \(text)")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenClawError.apiError(statusCode: statusCode, body: body)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let responseContent = message["content"] as? String {
            appendToBuffer(role: "user", content: text)
            appendToBuffer(role: "assistant", content: responseContent)
            return responseContent
        }

        return String(data: data, encoding: .utf8) ?? "No response"
    }
    
    /// Clear conversation history
    func clearHistory() {
        conversationBuffer.removeAll()
        miloLog("🧹 Conversation buffer cleared")
    }
    
    // MARK: - Sentence Extraction
    
    /// Extract the first complete sentence from the buffer.
    /// Returns the sentence and removes it from the buffer, or returns nil if no complete sentence yet.
    private func extractSentence(from buffer: inout String) -> String? {
        // Look for sentence-ending punctuation followed by a space or end
        // Handle: "Hello." "Hello! " "Hello? And" "Dr. Smith" (avoid false splits on abbreviations)
        let terminators: [Character] = [".", "!", "?", "\n"]
        
        for (i, char) in buffer.enumerated() {
            guard terminators.contains(char) else { continue }
            
            let nextIndex = buffer.index(buffer.startIndex, offsetBy: i + 1)
            
            // For periods, avoid splitting on common abbreviations
            if char == "." {
                let prefix = String(buffer[buffer.startIndex..<buffer.index(buffer.startIndex, offsetBy: i)])
                let lastWord = prefix.split(separator: " ").last.map(String.init) ?? prefix
                let abbreviations = ["Dr", "Mr", "Mrs", "Ms", "Jr", "Sr", "St", "vs", "etc", "i.e", "e.g"]
                if abbreviations.contains(lastWord) { continue }
            }
            
            // Need either end of buffer or a space/newline after the terminator
            if nextIndex >= buffer.endIndex || buffer[nextIndex] == " " || buffer[nextIndex] == "\n" {
                let sentence = String(buffer[buffer.startIndex...buffer.index(buffer.startIndex, offsetBy: i)])
                buffer = String(buffer[nextIndex...])
                return sentence
            }
        }
        
        // No complete sentence found yet
        return nil
    }
    
    // MARK: - Request Building
    
    private func buildRequest(text: String, screenshotPath: String?, runtimeContext: String?, stream: Bool) throws -> URLRequest {
        let urlString = "\(config.gatewayUrl)/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw OpenClawError.invalidURL
        }

        var messages: [[String: Any]] = []
        messages.append(["role": "system", "content": voiceSystemHint])
        
        for turn in conversationBuffer {
            messages.append(["role": turn.role, "content": turn.content])
        }
        
        var content: [[String: Any]] = [["type": "text", "text": text]]
        if let runtimeContext {
            let trimmedContext = runtimeContext.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContext.isEmpty {
                content.append([
                    "type": "text",
                    "text": "Desktop context (metadata, not user speech): \(trimmedContext)"
                ])
            }
        }
        if let path = screenshotPath,
           let imageData = FileManager.default.contents(atPath: path) {
            let base64 = imageData.base64EncodedString()
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/png;base64,\(base64)"]
            ])
        }
        messages.append(["role": "user", "content": content])

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "max_tokens": config.maxTokens,
            "stream": stream
        ]
        
        // Route through the configured OpenClaw session (if provided)
        if let sessionKey = config.sessionKey {
            body["user"] = sessionKey
            // Add debug info to help troubleshoot routing
            miloLog("🔍 API Request - sessionKey: \(sessionKey), agentId: \(config.agentId), model: \(config.model)")
        } else {
            body["user"] = "clawIsland"
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = config.gatewayToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(config.agentId, forHTTPHeaderField: "x-openclaw-agent-id")
        if let sessionKey = config.sessionKey {
            request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key")
        }
        request.httpBody = jsonData
        request.timeoutInterval = 120
        
        return request
    }
    
    // MARK: - Conversation Buffer
    
    private func appendToBuffer(role: String, content: String) {
        conversationBuffer.append((role: role, content: content))
        let maxEntries = config.conversationBufferSize * 2
        if conversationBuffer.count > maxEntries {
            conversationBuffer = Array(conversationBuffer.suffix(maxEntries))
        }
    }
    
    // MARK: - Voice Mode Hint
    
    private let voiceSystemHint = """
    You are responding via a voice overlay app (clawIsland). The user spoke to you and will hear \
    your response via TTS. Keep responses concise and conversational — aim for 1-3 sentences unless \
    the question requires more detail. Don't use markdown formatting, bullet points, or code blocks \
    — just natural speech. Don't narrate tool usage ("Let me check...") — just do it and give the answer.
    
    IMPORTANT: You should have access to your full memory including information about AJ's family \
    (Veda and Mithila), preferences, and conversation history. If you don't recognize AJ or don't \
    have access to this information, something is wrong with the session routing.
    """
}

enum OpenClawError: Error, LocalizedError {
    case invalidURL
    case apiError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid gateway URL"
        case .apiError(let code, let body): return "API error \(code): \(body)"
        }
    }
}
