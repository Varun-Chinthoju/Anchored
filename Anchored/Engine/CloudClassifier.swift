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
            if let mockProtocolClass = NSClassFromString("AnchoredTests.MockURLProtocol") as? URLProtocol.Type {
                configuration.protocolClasses = [mockProtocolClass]
            } else if let mockProtocolClass = NSClassFromString("MockURLProtocol") as? URLProtocol.Type {
                configuration.protocolClasses = [mockProtocolClass]
            }
            self.session = URLSession(configuration: configuration)
        }
    }
    
    public func classify(
        appName: String,
        windowTitle: String,
        url: URL?,
        ocrText: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        let providerIndex = preferences.cloudProvider
        let model = preferences.cloudModel
        let endpoint = preferences.cloudEndpoint
        
        let providerName: String
        switch providerIndex {
        case 0: providerName = "gemini"
        case 1: providerName = "openai"
        case 2: providerName = "anthropic"
        default: providerName = "gemini"
        }
        
        guard let apiKey = KeychainHelper.loadKey(forProvider: providerName), !apiKey.isEmpty else {
            completion(.failure(CloudClassifierError.apiKeyMissing))
            return
        }
        
        let profileName = ProfileManager.shared.activeProfile.name
        let urlString = url?.absoluteString ?? "N/A"
        let truncatedOcr = String(ocrText.prefix(2000))
        let prompt = "Is the application '\(appName)' with window title '\(windowTitle)', URL '\(urlString)', and screen text '\(truncatedOcr)' productive for '\(profileName)'? Answer only 'yes' or 'no'."
        
        guard var urlComponents = URLComponents(string: endpoint) else {
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
                request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            } else {
                guard let requestURL = urlComponents.url else {
                    completion(.failure(CloudClassifierError.invalidEndpoint))
                    return
                }
                request = URLRequest(url: requestURL)
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload = GeminiRequest(contents: [
                GeminiContent(parts: [
                    GeminiPart(text: prompt)
                ])
            ])
            
            do {
                request.httpBody = try JSONEncoder().encode(payload)
            } catch {
                completion(.failure(error))
                return
            }
            
        case 1:
            // OpenAI
            guard let requestURL = urlComponents.url else {
                completion(.failure(CloudClassifierError.invalidEndpoint))
                return
            }
            request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            
            let payload = OpenAIRequest(
                model: model,
                messages: [
                    OpenAIMessage(role: "user", content: prompt)
                ]
            )
            
            do {
                request.httpBody = try JSONEncoder().encode(payload)
            } catch {
                completion(.failure(error))
                return
            }
            
        case 2:
            // Anthropic
            guard let requestURL = urlComponents.url else {
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
                    AnthropicMessage(role: "user", content: prompt)
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
                    let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    guard let text = openAIResponse.choices?.first?.message?.content else {
                        throw CloudClassifierError.invalidResponse("Missing choices.message.content")
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
                
                let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if cleaned.contains("yes") {
                    completion(.success(true))
                } else if cleaned.contains("no") {
                    completion(.success(false))
                } else {
                    completion(.failure(CloudClassifierError.invalidResponse("Response did not contain yes/no: \(responseText)")))
                }
                
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
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
