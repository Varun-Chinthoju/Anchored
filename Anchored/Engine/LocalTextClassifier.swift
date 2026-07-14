import Foundation

/// A small, deterministic on-device text classifier used as an opt-in
/// promotion candidate. It consumes only the sanitized identity of a
/// ContextSnapshot and never performs enforcement itself.
public final class LocalTextClassifier: ContextClassifying, Sendable {
    public static let version = "local-text-v1"

    private static let productiveSignals = [
        "xcode", "vscode", "visual studio", "terminal", "iterm", "notion", "obsidian",
        "bear", "craft", "pages", "word", "figma", "github", "stackoverflow", "stackexchange",
        "developer", "documentation", "programming", "coding", "software", "api", "tutorial",
        "swift", "kotlin", "java", "python", "rust", "javascript", "typescript", "database",
        "compiler", "docker", "kubernetes", "learn", "course"
    ]

    private static let distractingSignals = [
        "spotify", "steam", "youtube", "netflix", "twitch", "tiktok", "instagram",
        "facebook", "reddit", "twitter", "gaming", "gameplay", "livestream", "entertainment",
        "music", "movie", "stream"
    ]

    public init() {}

    public func classify(snapshot: ContextSnapshot) -> ClassificationResult {
        let identity = snapshot.identity
        let searchableText = [
            identity.bundleID,
            identity.sanitizedURL ?? "",
            identity.normalizedTitle
        ]
        .joined(separator: " ")
        .lowercased()

        let productiveScore = Self.score(Self.productiveSignals, in: searchableText)
        let distractingScore = Self.score(Self.distractingSignals, in: searchableText)

        if productiveScore > 0 && distractingScore > 0 {
            return ClassificationResult(
                label: .neutral,
                confidence: 0.5,
                modelVersion: Self.version,
                latency: 0,
                explanation: "local signals conflict"
            )
        }

        if productiveScore > 0 {
            return ClassificationResult(
                label: .productive,
                confidence: min(0.98, 0.90 + Double(max(0, productiveScore - 1)) * 0.04),
                modelVersion: Self.version,
                latency: 0,
                explanation: "local productive signals"
            )
        }

        if distractingScore > 0 {
            return ClassificationResult(
                label: .distracting,
                confidence: min(0.98, 0.90 + Double(max(0, distractingScore - 1)) * 0.04),
                modelVersion: Self.version,
                latency: 0,
                explanation: "local distracting suggestion"
            )
        }

        return ClassificationResult(
            label: .neutral,
            confidence: 0,
            modelVersion: Self.version,
            latency: 0,
            explanation: "local confidence below gate"
        )
    }
}

private extension LocalTextClassifier {
    static func score(_ signals: [String], in text: String) -> Int {
        signals.reduce(into: 0) { score, signal in
            if text.contains(signal) {
                score += 1
            }
        }
    }
}

public struct LocalClassificationFixture: Codable, Equatable {
    public let id: String
    public let snapshot: ContextSnapshot
    public let expectedLabel: ClassificationLabel
    public let fixtureVersion: String

    public init(
        id: String,
        snapshot: ContextSnapshot,
        expectedLabel: ClassificationLabel,
        fixtureVersion: String = "local-text-fixtures-v1"
    ) {
        self.id = id
        self.snapshot = snapshot
        self.expectedLabel = expectedLabel
        self.fixtureVersion = fixtureVersion
    }
}

public struct LocalClassifierResourceMetrics: Codable, Equatable {
    public let cpuTimeMilliseconds: Double
    public let peakMemoryBytes: Int64

    public init(cpuTimeMilliseconds: Double = 0, peakMemoryBytes: Int64 = 0) {
        self.cpuTimeMilliseconds = max(0, cpuTimeMilliseconds)
        self.peakMemoryBytes = max(0, peakMemoryBytes)
    }
}

public struct LocalClassifierEvaluationReport: Codable, Equatable {
    public let classifierVersion: String
    public let fixtureVersion: String
    public let fixtureCount: Int
    public let falseDistractionRate: Double
    public let distractingPrecision: Double
    public let calibrationError: Double
    public let p50LatencyMilliseconds: Double
    public let p95LatencyMilliseconds: Double
    public let cpuTimeMilliseconds: Double
    public let peakMemoryBytes: Int64
    public let precisionGatePassed: Bool

    public init(
        classifierVersion: String,
        fixtureVersion: String,
        fixtureCount: Int,
        falseDistractionRate: Double,
        distractingPrecision: Double,
        calibrationError: Double,
        p50LatencyMilliseconds: Double,
        p95LatencyMilliseconds: Double,
        resourceMetrics: LocalClassifierResourceMetrics,
        precisionGatePassed: Bool
    ) {
        self.classifierVersion = classifierVersion
        self.fixtureVersion = fixtureVersion
        self.fixtureCount = fixtureCount
        self.falseDistractionRate = falseDistractionRate
        self.distractingPrecision = distractingPrecision
        self.calibrationError = calibrationError
        self.p50LatencyMilliseconds = p50LatencyMilliseconds
        self.p95LatencyMilliseconds = p95LatencyMilliseconds
        self.cpuTimeMilliseconds = resourceMetrics.cpuTimeMilliseconds
        self.peakMemoryBytes = resourceMetrics.peakMemoryBytes
        self.precisionGatePassed = precisionGatePassed
    }
}

public enum LocalClassifierEvaluationGate {
    public static let maximumFalseDistractionRate = 0.01
    public static let minimumDistractingPrecision = 0.99
    public static let maximumCalibrationError = 0.15
    public static let maximumP95LatencyMilliseconds = 50.0
}

public enum LocalClassifierEvaluator {
    public static func evaluate(
        classifier: ContextClassifying,
        fixtures: [LocalClassificationFixture],
        resourceMetrics: LocalClassifierResourceMetrics = LocalClassifierResourceMetrics()
    ) -> LocalClassifierEvaluationReport {
        let measurements = fixtures.map { fixture -> (fixture: LocalClassificationFixture, result: ClassificationResult, latency: Double) in
            let start = DispatchTime.now().uptimeNanoseconds
            let result = classifier.classify(snapshot: fixture.snapshot)
            let end = DispatchTime.now().uptimeNanoseconds
            let measuredMilliseconds = Double(end - start) / 1_000_000
            return (fixture, result, max(measuredMilliseconds, result.latency * 1_000))
        }

        let productiveCount = fixtures.filter { $0.expectedLabel == .productive }.count
        let falseDistractionCount = measurements.filter {
            $0.fixture.expectedLabel == .productive && $0.result.label == .distracting
        }.count
        let distractingPredictions = measurements.filter { $0.result.label == .distracting }
        let correctDistractingPredictions = distractingPredictions.filter {
            $0.fixture.expectedLabel == .distracting
        }.count

        let falseDistractionRate = productiveCount > 0
            ? Double(falseDistractionCount) / Double(productiveCount)
            : 0
        let distractingPrecision = distractingPredictions.isEmpty
            ? 0
            : Double(correctDistractingPredictions) / Double(distractingPredictions.count)

        let calibratedPredictions = measurements.filter { $0.result.label != .neutral }
        let calibrationError = calibratedPredictions.isEmpty
            ? 0
            : calibratedPredictions.reduce(0.0) { total, item in
                let correctness = item.fixture.expectedLabel == item.result.label ? 1.0 : 0.0
                return total + abs(item.result.confidence - correctness)
            } / Double(calibratedPredictions.count)

        let latencies = measurements.map(\.latency).sorted()
        let p50 = percentile(0.50, values: latencies)
        let p95 = percentile(0.95, values: latencies)
        let gatePassed = !fixtures.isEmpty
            && falseDistractionRate <= LocalClassifierEvaluationGate.maximumFalseDistractionRate
            && distractingPrecision >= LocalClassifierEvaluationGate.minimumDistractingPrecision
            && calibrationError <= LocalClassifierEvaluationGate.maximumCalibrationError
            && p95 <= LocalClassifierEvaluationGate.maximumP95LatencyMilliseconds

        return LocalClassifierEvaluationReport(
            classifierVersion: measurements.first?.result.modelVersion ?? "unknown",
            fixtureVersion: fixtures.first?.fixtureVersion ?? "unknown",
            fixtureCount: fixtures.count,
            falseDistractionRate: falseDistractionRate,
            distractingPrecision: distractingPrecision,
            calibrationError: calibrationError,
            p50LatencyMilliseconds: p50,
            p95LatencyMilliseconds: p95,
            resourceMetrics: resourceMetrics,
            precisionGatePassed: gatePassed
        )
    }

    private static func percentile(_ percentile: Double, values: [Double]) -> Double {
        guard let last = values.indices.last else { return 0 }
        let index = min(last, Int(Double(last) * percentile))
        return values[index]
    }
}
