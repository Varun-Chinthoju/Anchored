import Foundation

public enum CloudClassifierError: Error, LocalizedError {
    case apiKeyMissing
    case invalidEndpoint
    case networkError(Error)
    case invalidResponse(String)
    case unauthorized
    case rateLimited
    case httpError(statusCode: Int)
    
    public var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "API Key is missing from Keychain."
        case .invalidEndpoint:
            return "The configured endpoint URL is invalid."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .invalidResponse(let detail):
            return "Received invalid response format: \(detail)"
        case .unauthorized:
            return "Unauthorized request. Please check your API key."
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .httpError(let code):
            return "HTTP request failed with status code: \(code)"
        }
    }
}

public final class CloudClassifier {
    private let preferences: PreferencesManager
    private let session: URLSession
    
    public init(preferences: PreferencesManager = .shared, session: URLSession? = nil) {
        self.preferences = preferences
        if let session = session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 2.0
            configuration.timeoutIntervalForResource = 2.0
            self.session = URLSession(configuration: configuration)
        }
    }
    
    public func classify(
        input: CloudClassificationInput,
        completion: @escaping (Result<ClassificationResult, Error>) -> Void
    ) {
        let providerIndex = preferences.cloudProvider
        let model = preferences.cloudModel
        let endpoint = preferences.cloudEndpoint
        let endpointComponents = URLComponents(string: endpoint)
        let endpointPath = endpointComponents?.path.lowercased() ?? ""
        let usesInputPayload = endpointPath.hasSuffix("/api/v1/chat") || endpointPath.contains("/responses")
        let usesOllamaChatPayload = providerIndex == 3 || endpointPath.hasSuffix("/api/chat")
        
        let providerName: String
        switch providerIndex {
        case 0: providerName = "gemini"
        case 1: providerName = "openai"
        case 2: providerName = "anthropic"
        case 3: providerName = "ollama"
        default: providerName = "gemini"
        }
        
        let apiKey: String?
        if providerIndex == 3 {
            apiKey = nil
        } else {
            guard let loadedKey = KeychainHelper.loadKey(forProvider: providerName), !loadedKey.isEmpty else {
                completion(.failure(CloudClassifierError.apiKeyMissing))
                return
            }
            apiKey = loadedKey
        }
        
        guard let structuredInputData = try? JSONEncoder().encode(input),
              let structuredInput = String(data: structuredInputData, encoding: .utf8) else {
            completion(.failure(CloudClassifierError.invalidResponse("Unable to encode structured input")))
            return
        }
        let structuredRequest = "{\"task\":\"productivity_classification\",\"guidance\":\"For social domains, treat feeds/home/explore/trending as distracting and only return productive when the title features indicate coding, documentation, developer work, or learning.\",\"input\":\(structuredInput),\"outputSchema\":{\"label\":\"productive|distracting|neutral\",\"confidence\":\"0..1\"}}"

        guard let urlComponents = URLComponents(string: endpoint) else {
            completion(.failure(CloudClassifierError.invalidEndpoint))
            return
        }
        
        var request: URLRequest
        
        switch providerIndex {
        case 0:
            // Google Gemini - key in header, not URL, to avoid leakage in logs
            if endpoint.contains("googleapis.com") {
                var baseEndpoint = endpoint
                if !baseEndpoint.hasSuffix("/") {
                    baseEndpoint += "/"
                }
                guard let requestURL = URL(string: "\(baseEndpoint)\(model):generateContent") else {
                    completion(.failure(CloudClassifierError.invalidEndpoint))
                    return
                }
                request = URLRequest(url: requestURL)
                if let apiKey {
                    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                }
            } else {
                guard let requestURL = urlComponents.url else {
                    completion(.failure(CloudClassifierError.invalidEndpoint))
                    return
                }
                request = URLRequest(url: requestURL)
                if let apiKey {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }
            }
            
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload = GeminiRequest(contents: [
                GeminiContent(parts: [
                    GeminiPart(text: structuredRequest)
                ])
            ])
            
            do {
                request.httpBody = try JSONEncoder().encode(payload)
            } catch {
                completion(.failure(error))
                return
            }
            
        case 1:
            // OpenAI-compatible or LM Studio native chat.
            guard let requestURL = endpointComponents?.url else {
                completion(.failure(CloudClassifierError.invalidEndpoint))
                return
            }
                request = URLRequest(url: requestURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let apiKey {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }

            do {
                if usesInputPayload {
                    let payload = InputPromptRequest(
                        model: model,
                        input: structuredRequest
                    )
                    request.httpBody = try JSONEncoder().encode(payload)
                } else if usesOllamaChatPayload {
                    let payload = OllamaChatRequest(
                        model: model,
                        messages: [
                            OpenAIMessage(role: "user", content: structuredRequest)
                        ],
                        stream: false,
                        format: "json"
                    )
                    request.httpBody = try JSONEncoder().encode(payload)
                } else {
                    let payload = OpenAIRequest(
                        model: model,
                        messages: [
                            OpenAIMessage(role: "user", content: structuredRequest)
                        ]
                    )
                        request.httpBody = try JSONEncoder().encode(payload)
                    }
                } catch {
                    completion(.failure(error))
                    return
                }

        case 3:
            // Ollama native chat uses messages and returns a single assistant message.
            guard let requestURL = endpointComponents?.url else {
                completion(.failure(CloudClassifierError.invalidEndpoint))
                return
            }
            request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            do {
                let payload = OllamaChatRequest(
                    model: model,
                    messages: [
                        OpenAIMessage(role: "user", content: structuredRequest)
                    ],
                    stream: false,
                    format: "json"
                )
                request.httpBody = try JSONEncoder().encode(payload)
            } catch {
                completion(.failure(error))
                return
            }
            
        case 2:
            // Anthropic
            guard let requestURL = endpointComponents?.url else {
                completion(.failure(CloudClassifierError.invalidEndpoint))
                return
            }
            request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            
            let payload = AnthropicRequest(
                model: model,
                max_tokens: 10,
                messages: [
                    AnthropicMessage(role: "user", content: structuredRequest)
                ]
            )
            
            do {
                request.httpBody = try JSONEncoder().encode(payload)
            } catch {
                completion(.failure(error))
                return
            }
            
        default:
            completion(.failure(CloudClassifierError.invalidEndpoint))
            return
        }
        
        let requestStartedAt = Date()
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(CloudClassifierError.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(CloudClassifierError.invalidResponse("Not HTTP response")))
                return
            }
            
            if httpResponse.statusCode == 401 {
                completion(.failure(CloudClassifierError.unauthorized))
                return
            } else if httpResponse.statusCode == 429 {
                completion(.failure(CloudClassifierError.rateLimited))
                return
            } else if !(200...299).contains(httpResponse.statusCode) {
                completion(.failure(CloudClassifierError.httpError(statusCode: httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                completion(.failure(CloudClassifierError.invalidResponse("Empty data")))
                return
            }
            
            do {
                let responseText: String
                switch providerIndex {
                case 0:
                    let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
                    guard let text = geminiResponse.candidates?.first?.content?.parts?.first?.text else {
                        throw CloudClassifierError.invalidResponse("Missing candidates.content.parts.text")
                    }
                    responseText = text
                    
                case 1:
                    if usesInputPayload {
                        let lmStudioResponse = try JSONDecoder().decode(InputPromptResponse.self, from: data)
                        guard let text = lmStudioResponse.output?.first(where: { $0.type == "message" })?.content
                                    ?? lmStudioResponse.output?.first?.content else {
                            throw CloudClassifierError.invalidResponse("Missing output.message.content")
                        }
                        responseText = text
                    } else if usesOllamaChatPayload {
                        let ollamaResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
                        guard let text = ollamaResponse.message?.content else {
                            throw CloudClassifierError.invalidResponse("Missing message.content")
                        }
                        responseText = text
                    } else {
                        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                        guard let text = openAIResponse.choices?.first?.message?.content else {
                            throw CloudClassifierError.invalidResponse("Missing choices.message.content")
                        }
                        responseText = text
                    }
                    
                case 3:
                    let ollamaResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
                    guard let text = ollamaResponse.message?.content else {
                        throw CloudClassifierError.invalidResponse("Missing message.content")
                    }
                    responseText = text
                    
                case 2:
                    let anthropicResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
                    guard let text = anthropicResponse.content?.first?.text else {
                        throw CloudClassifierError.invalidResponse("Missing content.text")
                    }
                    responseText = text
                    
                default:
                    throw CloudClassifierError.invalidResponse("Unknown provider index")
                }
                
                let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                let latency = Date().timeIntervalSince(requestStartedAt)
                if let structuredResponse = Self.decodeStructuredResponse(cleaned) {
                    let confidence = min(max(structuredResponse.confidence, 0), 1)
                    let label = confidence >= ClassificationPolicy.highConfidenceThreshold
                        ? structuredResponse.label
                        : .neutral
                    completion(.success(ClassificationResult(
                        label: label,
                        confidence: confidence,
                        modelVersion: "cloud-\(providerName)-\(model)",
                        latency: latency,
                        explanation: label == .neutral ? "cloud result below confidence gate" : "cloud structured evidence"
                    )))
                } else {
                    let legacyLabel: ClassificationLabel?
                    switch cleaned.lowercased() {
                    case "yes": legacyLabel = .productive
                    case "no": legacyLabel = .distracting
                    default: legacyLabel = nil
                    }
                    guard let legacyLabel else {
                        throw CloudClassifierError.invalidResponse("Response was not structured evidence")
                    }
                    completion(.success(ClassificationResult(
                        label: legacyLabel,
                        confidence: 0.85,
                        modelVersion: "cloud-\(providerName)-\(model)",
                        latency: latency,
                        explanation: "cloud legacy response"
                    )))
                }
                
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    /// Compatibility adapter for existing callers. The OCR, title, URL, and
    /// app-name values are reduced to categorical features before transmission.
    @available(*, deprecated, message: "Use classify(input:completion:) with CloudClassificationInput.")
    public func classify(
        appName: String,
        windowTitle: String,
        url: URL?,
        ocrText _: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        let input = CloudClassificationFeatureExtractor.make(
            appName: appName,
            url: url,
            title: windowTitle,
            source: .application
        )
        classify(input: input) { result in
            switch result {
            case .success(let evidence):
                completion(.success(evidence.label == .productive))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func decodeStructuredResponse(_ text: String) -> CloudStructuredResponse? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("```") {
            candidate = candidate
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = candidate.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CloudStructuredResponse.self, from: data)
    }
}

// MARK: - Gemini API Request & Response Models
struct GeminiRequest: Codable {
    let contents: [GeminiContent]
}

struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

struct GeminiPart: Codable {
    let text: String
}

struct GeminiResponse: Codable {
    struct Candidate: Codable {
        struct Content: Codable {
            struct Part: Codable {
                let text: String?
            }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}

// MARK: - OpenAI API Request & Response Models
struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
}

struct InputPromptRequest: Codable {
    let model: String
    let input: String
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String?
        }
        let message: Message?
    }
    let choices: [Choice]?
}

struct InputPromptResponse: Codable {
    struct OutputItem: Codable {
        let type: String?
        let content: String?
    }

    let output: [OutputItem]?
}

// MARK: - Ollama API Request & Response Models
struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool
    let format: String
}

struct OllamaChatResponse: Codable {
    struct Message: Codable {
        let role: String?
        let content: String?
    }

    let message: Message?
}

// MARK: - Anthropic API Request & Response Models
struct AnthropicRequest: Codable {
    let model: String
    let max_tokens: Int
    let messages: [AnthropicMessage]
}

struct AnthropicMessage: Codable {
    let role: String
    let content: String
}

struct AnthropicResponse: Codable {
    struct ContentBlock: Codable {
        let text: String?
        let type: String?
    }
    let content: [ContentBlock]?
}
