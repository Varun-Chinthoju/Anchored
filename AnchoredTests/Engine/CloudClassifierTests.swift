import XCTest
import Combine
import ServiceManagement
@testable import Anchored

final class CloudClassifierTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var preferences: PreferencesManager!
    private var session: URLSession!
    private var classifier: CloudClassifier!
    
    override func setUp() {
        super.setUp()
        let suiteName = "com.varun.Anchored.CloudClassifierTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        
        let mockService = MockLoginItemService()
        preferences = PreferencesManager(defaults: testDefaults, loginItemService: mockService)
        
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
        
        classifier = CloudClassifier(preferences: preferences, session: session)
        KeychainHelper.mockKeys = [:]
        KeychainHelper.useMockOnly = true
        KeychainHelper.clearCachedKeys()
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "com.varun.Anchored.CloudClassifierTests")
        testDefaults = nil
        preferences = nil
        session = nil
        classifier = nil
        MockURLProtocol.requestHandler = nil
        KeychainHelper.mockKeys = [:]
        KeychainHelper.useMockOnly = false
        KeychainHelper.clearCachedKeys()
        super.tearDown()
    }

    func testStructuredClassificationRedactsRawContextAndReturnsEvidence() {
        preferences.cloudProvider = 0
        preferences.cloudModel = "gemini-2.5-flash"
        preferences.cloudEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/"
        KeychainHelper.mockKeys["gemini"] = "gemini-test-key"

        let expectation = XCTestExpectation(description: "structured cloud evidence")
        MockURLProtocol.requestHandler = { request in
            let body = String(data: request.httpBodyData ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("editor"))
            XCTAssertTrue(body.contains("documentation"))
            XCTAssertTrue(body.contains("social domains"))
            XCTAssertFalse(body.contains("CloudClassifier.swift"))
            XCTAssertFalse(body.contains("typed secret"))
            XCTAssertFalse(body.contains("youtube.com"))
            XCTAssertFalse(body.lowercased().contains("ocr"))

            let responseBody = """
            {
                "candidates": [{
                    "content": {"parts": [{"text": "{\\"label\\":\\"productive\\",\\"confidence\\":0.92,\\"explanation\\":\\"structured evidence\\"}"}]}
                }]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseBody.data(using: .utf8))
        }

        let input = CloudClassificationInput(
            appCategory: .editor,
            domainCategory: .documentation,
            titleFeatures: [.code, .documentation],
            source: .chromium
        )
        classifier.classify(input: input) { result in
            switch result {
            case .success(let evidence):
                XCTAssertEqual(evidence.label, .productive)
                XCTAssertEqual(evidence.confidence, 0.92, accuracy: 0.001)
            case .failure(let error):
                XCTFail("Expected structured evidence, but got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testSocialFeedAddsSocialTitleFeaturesAndGuidance() {
        let input = CloudClassificationFeatureExtractor.make(
            appName: "Chrome",
            bundleID: "com.google.Chrome",
            url: URL(string: "https://x.com/home")!,
            title: "X / Home",
            source: .chromium
        )

        XCTAssertEqual(input.domainCategory, .social)
        XCTAssertTrue(input.titleFeatures.contains(.socialFeed))
    }

    func testLowConfidenceStructuredCloudResultStaysNeutral() {
        preferences.cloudProvider = 1
        preferences.cloudModel = "gpt-4o-mini"
        preferences.cloudEndpoint = "https://api.openai.com/v1/chat/completions"
        KeychainHelper.mockKeys["openai"] = "openai-test-key"

        MockURLProtocol.requestHandler = { request in
            let responseBody = """
            {"choices":[{"message":{"role":"assistant","content":"{\\"label\\":\\"productive\\",\\"confidence\\":0.55}"}}]}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseBody.data(using: .utf8))
        }

        let expectation = XCTestExpectation(description: "low confidence neutral")
        classifier.classify(input: CloudClassificationInput(
            appCategory: .unknown,
            domainCategory: .general,
            titleFeatures: [.unknown],
            source: .application
        )) { result in
            switch result {
            case .success(let evidence):
                XCTAssertEqual(evidence.label, .neutral)
            case .failure(let error):
                XCTFail("Expected neutral evidence, but got error: \(error)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGeminiClassifyYes() {
        preferences.cloudProvider = 0
        preferences.cloudModel = "gemini-2.5-flash"
        preferences.cloudEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/"
        KeychainHelper.mockKeys["gemini"] = "gemini-test-key"
        
        let expectation = XCTestExpectation(description: "Gemini classifies Yes")
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            
            if let bodyData = request.httpBodyData,
               let payload = try? JSONDecoder().decode(GeminiRequest.self, from: bodyData) {
                XCTAssertTrue(payload.contents.first?.parts.first?.text.contains("productive") ?? false)
            } else {
                XCTFail("Failed to parse request body")
            }
            
            let jsonString = """
            {
                "candidates": [
                    {
                        "content": {
                            "parts": [
                                {
                                    "text": "yes"
                                }
                            ]
                        }
                    }
                ]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8))
        }
        
        classifier.classify(appName: "Xcode", windowTitle: "CloudClassifier.swift", url: URL(string: "https://apple.com"), ocrText: "code writing") { result in
            switch result {
            case .success(let productive):
                XCTAssertTrue(productive)
            case .failure(let error):
                XCTFail("Expected success, but got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGeminiClassifyNo() {
        preferences.cloudProvider = 0
        preferences.cloudModel = "gemini-2.5-flash"
        preferences.cloudEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/"
        KeychainHelper.mockKeys["gemini"] = "gemini-test-key"
        
        let expectation = XCTestExpectation(description: "Gemini classifies No")
        
        MockURLProtocol.requestHandler = { request in
            let jsonString = """
            {
                "candidates": [
                    {
                        "content": {
                            "parts": [
                                {
                                    "text": "no"
                                }
                            ]
                        }
                    }
                ]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8))
        }
        
        classifier.classify(appName: "Safari", windowTitle: "Funny Videos", url: URL(string: "https://youtube.com"), ocrText: "cat video") { result in
            switch result {
            case .success(let productive):
                XCTAssertFalse(productive)
            case .failure(let error):
                XCTFail("Expected success, but got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testOpenAIClassifyYes() {
        preferences.cloudProvider = 1
        preferences.cloudModel = "gpt-4o-mini"
        preferences.cloudEndpoint = "https://api.openai.com/v1/chat/completions"
        KeychainHelper.mockKeys["openai"] = "openai-test-key"
        
        let expectation = XCTestExpectation(description: "OpenAI classifies Yes")
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-test-key")
            
            if let bodyData = request.httpBodyData,
               let payload = try? JSONDecoder().decode(OpenAIRequest.self, from: bodyData) {
                XCTAssertEqual(payload.model, "gpt-4o-mini")
                XCTAssertTrue(payload.messages.first?.content.contains("productive") ?? false)
            } else {
                XCTFail("Failed to parse request body")
            }
            
            let jsonString = """
            {
                "choices": [
                    {
                        "message": {
                            "role": "assistant",
                            "content": "yes"
                        }
                    }
                ]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8))
        }
        
        classifier.classify(appName: "Xcode", windowTitle: "CloudClassifier.swift", url: URL(string: "https://apple.com"), ocrText: "code writing") { result in
            switch result {
            case .success(let productive):
                XCTAssertTrue(productive)
            case .failure(let error):
                XCTFail("Expected success, but got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testLMStudioNativeChatClassifyYes() {
        preferences.cloudProvider = 1
        preferences.cloudModel = "qwen3.5-0.8b"
        preferences.cloudEndpoint = "http://localhost:1234/api/v1/chat"
        KeychainHelper.mockKeys["openai"] = "lmstudio-test-token"

        let expectation = XCTestExpectation(description: "LM Studio native chat classifies Yes")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:1234/api/v1/chat")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer lmstudio-test-token")

            if let bodyData = request.httpBodyData,
               let payload = try? JSONDecoder().decode(InputPromptRequest.self, from: bodyData) {
                XCTAssertEqual(payload.model, "qwen3.5-0.8b")
                XCTAssertTrue(payload.input.contains("productive"))
            } else {
                XCTFail("Failed to parse LM Studio request body")
            }

            let jsonString = """
            {
                "model_instance_id": "qwen3.5-0.8b",
                "output": [
                    {
                        "type": "message",
                        "content": "{\\"label\\":\\"productive\\",\\"confidence\\":0.9,\\"explanation\\":\\"lm studio response\\"}"
                    }
                ]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8))
        }

        classifier.classify(appName: "Xcode", windowTitle: "CloudClassifier.swift", url: URL(string: "https://apple.com"), ocrText: "code writing") { result in
            switch result {
            case .success(let productive):
                XCTAssertTrue(productive)
            case .failure(let error):
                XCTFail("Expected success, but got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testOllamaClassifyYes() {
        preferences.cloudProvider = 3
        preferences.cloudModel = "llama3.2"
        preferences.cloudEndpoint = "http://localhost:11434/api/chat"

        let expectation = XCTestExpectation(description: "Ollama classifies Yes")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            if let bodyData = request.httpBodyData,
               let payload = try? JSONDecoder().decode(OllamaChatRequest.self, from: bodyData) {
                XCTAssertEqual(payload.model, "llama3.2")
                XCTAssertFalse(payload.stream)
                XCTAssertEqual(payload.format, "json")
                XCTAssertTrue(payload.messages.first?.content.contains("productive") ?? false)
            } else {
                XCTFail("Failed to parse Ollama request body")
            }

            let jsonString = """
            {
                "model": "llama3.2",
                "message": {
                    "role": "assistant",
                    "content": "{\\"label\\":\\"productive\\",\\"confidence\\":0.91,\\"explanation\\":\\"ollama response\\"}"
                },
                "done": true
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8))
        }

        classifier.classify(appName: "Xcode", windowTitle: "CloudClassifier.swift", url: URL(string: "https://apple.com"), ocrText: "code writing") { result in
            switch result {
            case .success(let productive):
                XCTAssertTrue(productive)
            case .failure(let error):
                XCTFail("Expected success, but got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
    
    func testAnthropicClassifyYes() {
        preferences.cloudProvider = 2
        preferences.cloudModel = "claude-3-5-haiku"
        preferences.cloudEndpoint = "https://api.anthropic.com/v1/messages"
        KeychainHelper.mockKeys["anthropic"] = "anthropic-test-key"
        
        let expectation = XCTestExpectation(description: "Anthropic classifies Yes")
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            
            if let bodyData = request.httpBodyData,
               let payload = try? JSONDecoder().decode(AnthropicRequest.self, from: bodyData) {
                XCTAssertEqual(payload.model, "claude-3-5-haiku")
                XCTAssertEqual(payload.max_tokens, 10)
                XCTAssertTrue(payload.messages.first?.content.contains("productive") ?? false)
            } else {
                XCTFail("Failed to parse request body")
            }
            
            let jsonString = """
            {
                "content": [
                    {
                        "type": "text",
                        "text": "yes"
                    }
                ]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8))
        }
        
        classifier.classify(appName: "Xcode", windowTitle: "CloudClassifier.swift", url: URL(string: "https://apple.com"), ocrText: "code writing") { result in
            switch result {
            case .success(let productive):
                XCTAssertTrue(productive)
            case .failure(let error):
                XCTFail("Expected success, but got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGeminiCustomEndpoint() {
        preferences.cloudProvider = 0
        preferences.cloudModel = "gemini-custom"
        preferences.cloudEndpoint = "https://custom.gemini-proxy.com/v1/generate"
        KeychainHelper.mockKeys["gemini"] = "custom-gemini-key"
        
        let expectation = XCTestExpectation(description: "Gemini custom endpoint")
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://custom.gemini-proxy.com/v1/generate")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer custom-gemini-key")
            
            let jsonString = """
            {
                "candidates": [
                    {
                        "content": {
                            "parts": [
                                {
                                    "text": "yes"
                                }
                            ]
                        }
                    }
                ]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8))
        }
        
        classifier.classify(appName: "Xcode", windowTitle: "CloudClassifier.swift", url: nil, ocrText: "") { result in
            switch result {
            case .success(let productive):
                XCTAssertTrue(productive)
            case .failure(let error):
                XCTFail("Expected success, but got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testMissingAPIKey() {
        preferences.cloudProvider = 0
        KeychainHelper.mockKeys["gemini"] = nil
        
        let expectation = XCTestExpectation(description: "Fails with missing key")
        
        classifier.classify(appName: "Xcode", windowTitle: "CloudClassifier.swift", url: nil, ocrText: "") { result in
            switch result {
            case .success:
                XCTFail("Expected failure due to missing API key")
            case .failure(let error):
                if let cloudError = error as? CloudClassifierError, case .apiKeyMissing = cloudError {
                    // Passed
                } else {
                    XCTFail("Expected apiKeyMissing, got \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testHTTPUnauthorized() {
        preferences.cloudProvider = 1
        KeychainHelper.mockKeys["openai"] = "bad-key"
        
        let expectation = XCTestExpectation(description: "Fails with unauthorized")
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }
        
        classifier.classify(appName: "Xcode", windowTitle: "CloudClassifier.swift", url: nil, ocrText: "") { result in
            switch result {
            case .success:
                XCTFail("Expected failure due to unauthorized status")
            case .failure(let error):
                if let cloudError = error as? CloudClassifierError, case .unauthorized = cloudError {
                    // Passed
                } else {
                    XCTFail("Expected unauthorized, got \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testHTTPRateLimited() {
        preferences.cloudProvider = 1
        KeychainHelper.mockKeys["openai"] = "test-key"
        
        let expectation = XCTestExpectation(description: "Fails with rate limited")
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }
        
        classifier.classify(appName: "Xcode", windowTitle: "CloudClassifier.swift", url: nil, ocrText: "") { result in
            switch result {
            case .success:
                XCTFail("Expected failure due to rate limited status")
            case .failure(let error):
                if let cloudError = error as? CloudClassifierError, case .rateLimited = cloudError {
                    // Passed
                } else {
                    XCTFail("Expected rateLimited, got \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testNetworkTimeout() {
        preferences.cloudProvider = 1
        KeychainHelper.mockKeys["openai"] = "test-key"
        
        let expectation = XCTestExpectation(description: "Fails with timeout")
        
        MockURLProtocol.requestHandler = { request in
            throw URLError(.timedOut)
        }
        
        classifier.classify(appName: "Xcode", windowTitle: "CloudClassifier.swift", url: nil, ocrText: "") { result in
            switch result {
            case .success:
                XCTFail("Expected failure due to timeout")
            case .failure(let error):
                if let cloudError = error as? CloudClassifierError, case .networkError(let underlying) = cloudError {
                    XCTAssertEqual((underlying as? URLError)?.code, .timedOut)
                } else {
                    XCTFail("Expected networkError containing URLError(.timedOut), got \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Login Item Service
private class MockLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    func register() throws {}
    func unregister() throws {}
}

// MARK: - Mock URL Protocol
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}

// MARK: - URLRequest Extension for HTTPBody data from Streams
private extension URLRequest {
    var httpBodyData: Data? {
        if let httpBody = httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else {
            return nil
        }
        
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }
        
        stream.open()
        defer {
            stream.close()
        }
        
        while true {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                return nil
            } else if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }
        
        return data
    }
}
