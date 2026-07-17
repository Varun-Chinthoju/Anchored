import AppKit
import Foundation

protocol DiagnosticsRecording {
    func recordEngineStateTransition(from: SessionState, to: SessionState, reason: DiagnosticEngineTransitionReason)
    func recordSessionLifecycle(action: DiagnosticSessionAction, duration: TimeInterval?, bundleID: String?)
    func recordTimerScheduled(kind: DiagnosticTimerKind, delay: TimeInterval, generation: Int)
    func recordTimerCancelled(kind: DiagnosticTimerKind, reason: DiagnosticTimerCancellationReason, generation: Int?)
    func recordTimerRejected(kind: DiagnosticTimerKind, reason: DiagnosticTimerRejectionReason, generation: Int?)
    func recordClassificationDecision(
        source: ClassificationSource,
        decision: ClassificationLabel,
        reason: ClassificationReason,
        confidence: Double
    )
    func recordWorkspaceLifecycle(action: DiagnosticWorkspaceAction, pauseSeconds: TimeInterval?)
    func recordPermissionState(permission: DiagnosticPermissionKind, granted: Bool)
    func recordSanitizedError(category: DiagnosticErrorCategory)
}

struct DiagnosticReportHeader {
    let generatedAt: Date
    let appVersion: String
    let buildVersion: String
    let macOSVersion: String
    let databaseMigrationVersion: String
    let accessibilityPermissionGranted: Bool
    let screenRecordingPermissionGranted: Bool
    let enabledSubsystems: [String]
}

enum DiagnosticSubsystem: String, CaseIterable {
    case engine
    case timers
    case classification
    case session
    case workspace
    case permissions
    case errors
}

enum DiagnosticTimerKind: String, CaseIterable {
    case sessionExpiry
    case distractionCountdown
    case breakDuration
    case breakReturnGrace
    case doomscrollThreshold
    case focusPrompt
}

enum DiagnosticTimerCancellationReason: String, CaseIterable {
    case rescheduled
    case sessionEnded
    case breakStarted
    case workspacePaused
    case engineStopped
    case manualAction
    case scheduleChanged
    case featureDisabled
}

enum DiagnosticTimerRejectionReason: String, CaseIterable {
    case workspacePaused
    case sessionEnded
    case sessionMismatch
    case generationMismatch
    case expirationMismatch
    case expiredTooEarly
    case staleContext
    case newerTimerSuperseded
}

enum DiagnosticEngineTransitionReason: String, CaseIterable {
    case sessionStarted
    case sessionEnded
    case trackingReset
    case breakRequested
    case breakReviewed
    case workspacePaused
    case workspaceResumed
    case engineStopped
}

enum DiagnosticWorkspaceAction: String, CaseIterable {
    case paused
    case resumed
}

enum DiagnosticSessionAction: String, CaseIterable {
    case started
    case ended
}

enum DiagnosticPermissionKind: String, CaseIterable {
    case accessibility
    case screenRecording
}

enum DiagnosticPermissionState: String, CaseIterable {
    case granted
    case denied
}

enum DiagnosticErrorCategory: String, CaseIterable {
    case clipboardWrite
    case reportGeneration
    case databaseMigration
    case permissionState
    case unknown
}

struct DiagnosticEvent: Equatable {
    let timestamp: Date
    let subsystem: DiagnosticSubsystem
    let message: String
}

enum DiagnosticsPrivacy {
    static func redactedText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "<redacted>"
    }
}

final class DiagnosticsCenter: DiagnosticsRecording {
    static let shared = DiagnosticsCenter()

    private let lock = NSLock()
    private var events: [DiagnosticEvent] = []
    private let maximumEvents = 120

    init() {}

    private func record(_ event: DiagnosticEvent) {
        lock.lock()
        events.append(event)
        if events.count > maximumEvents {
            events.removeFirst(events.count - maximumEvents)
        }
        lock.unlock()
    }

    func recordEngineStateTransition(from: SessionState, to: SessionState, reason: DiagnosticEngineTransitionReason) {
        record(
            subsystem: .engine,
            message: "stateTransition from=\(from.rawValue) to=\(to.rawValue) reason=\(reason.rawValue)"
        )
    }

    func recordSessionLifecycle(action: DiagnosticSessionAction, duration: TimeInterval? = nil, bundleID: String? = nil) {
        var fields = ["action": action.rawValue]
        if let duration {
            fields["duration"] = Self.formatSeconds(duration)
        }
        if let bundleID, !bundleID.isEmpty {
            fields["bundleID"] = bundleID
        }
        record(subsystem: .session, message: Self.render(prefix: "sessionLifecycle", fields: fields))
    }

    func recordTimerScheduled(kind: DiagnosticTimerKind, delay: TimeInterval, generation: Int) {
        record(
            subsystem: .timers,
            message: "timerScheduled kind=\(kind.rawValue) delay=\(Self.formatSeconds(delay)) generation=\(generation)"
        )
    }

    func recordTimerCancelled(kind: DiagnosticTimerKind, reason: DiagnosticTimerCancellationReason, generation: Int?) {
        var fields = [
            "kind": kind.rawValue,
            "reason": reason.rawValue
        ]
        if let generation {
            fields["generation"] = "\(generation)"
        }
        record(subsystem: .timers, message: Self.render(prefix: "timerCancelled", fields: fields))
    }

    func recordTimerRejected(kind: DiagnosticTimerKind, reason: DiagnosticTimerRejectionReason, generation: Int?) {
        var fields = [
            "kind": kind.rawValue,
            "reason": reason.rawValue
        ]
        if let generation {
            fields["generation"] = "\(generation)"
        }
        record(subsystem: .timers, message: Self.render(prefix: "timerRejected", fields: fields))
    }

    func recordClassificationDecision(
        source: ClassificationSource,
        decision: ClassificationLabel,
        reason: ClassificationReason,
        confidence: Double
    ) {
        record(
            subsystem: .classification,
            message: "classificationDecision source=\(source.rawValue) decision=\(decision.rawValue) reason=\(reason.rawValue) confidence=\(Self.formatConfidence(confidence))"
        )
    }

    func recordWorkspaceLifecycle(action: DiagnosticWorkspaceAction, pauseSeconds: TimeInterval? = nil) {
        var fields = ["action": action.rawValue]
        if let pauseSeconds {
            fields["pauseSeconds"] = Self.formatSeconds(pauseSeconds)
        }
        record(subsystem: .workspace, message: Self.render(prefix: "workspaceLifecycle", fields: fields))
    }

    func recordPermissionState(permission: DiagnosticPermissionKind, granted: Bool) {
        record(
            subsystem: .permissions,
            message: "permissionState permission=\(permission.rawValue) state=\(granted ? DiagnosticPermissionState.granted.rawValue : DiagnosticPermissionState.denied.rawValue)"
        )
    }

    func recordSanitizedError(category: DiagnosticErrorCategory) {
        record(
            subsystem: .errors,
            message: "sanitizedError category=\(category.rawValue)"
        )
    }

    func recentEvents(limit: Int = 40) -> [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        guard limit > 0 else { return [] }
        return Array(events.suffix(limit))
    }

    func reset() {
        lock.lock()
        events.removeAll()
        lock.unlock()
    }

    func makeDiagnosticReport(header: DiagnosticReportHeader) -> String {
        let events = recentEvents()
        let formatter = Self.timestampFormatter

        var lines: [String] = [
            "Anchored Diagnostic Report",
            "Generated: \(formatter.string(from: header.generatedAt))",
            "App Version: \(header.appVersion) (Build \(header.buildVersion))",
            "macOS: \(header.macOSVersion)",
            "Database Migration Version: \(header.databaseMigrationVersion)",
            "Permissions:",
            "  - Accessibility: \(header.accessibilityPermissionGranted ? "granted" : "denied")",
            "  - Screen Recording: \(header.screenRecordingPermissionGranted ? "granted" : "denied")",
            "Enabled Subsystems:"
        ]

        if header.enabledSubsystems.isEmpty {
            lines.append("  - none")
        } else {
            lines.append(contentsOf: header.enabledSubsystems.sorted().map { "  - \($0)" })
        }

        lines.append("Recent Events:")
        if events.isEmpty {
            lines.append("  - none")
        } else {
            lines.append(contentsOf: events.map { event in
                "[\(formatter.string(from: event.timestamp))] [\(event.subsystem.rawValue)] \(event.message)"
            }.map { "  - \($0)" })
        }

        lines.append("Privacy Boundary: raw titles, URLs, OCR, typed text, screenshots, browsing history, and API keys are omitted.")
        return lines.joined(separator: "\n")
    }

    @discardableResult
    func copyDiagnosticReport(header: DiagnosticReportHeader) -> Bool {
        let report = makeDiagnosticReport(header: header)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(report, forType: .string)
        if !success {
            recordSanitizedError(category: .clipboardWrite)
        }
        return success
    }

    private func record(subsystem: DiagnosticSubsystem, message: String) {
        record(DiagnosticEvent(timestamp: Date(), subsystem: subsystem, message: message))
    }

    private static func render(prefix: String, fields: [String: String]) -> String {
        let payload = fields
            .keys
            .sorted()
            .map { key in "\(key)=\(fields[key] ?? "")" }
            .joined(separator: " ")
        return "\(prefix) \(payload)"
    }

    private static func formatSeconds(_ value: TimeInterval) -> String {
        String(format: "%.1fs", max(0, value))
    }

    private static func formatConfidence(_ value: Double) -> String {
        String(format: "%.2f", min(max(value, 0.0), 1.0))
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
