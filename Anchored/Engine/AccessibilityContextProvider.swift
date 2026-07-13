import Foundation
import AppKit
import ApplicationServices

public struct AccessibilityNode: Equatable {
    public let role: String?
    public let title: String?
    public let value: String?
    public let children: [AccessibilityNode]

    public init(role: String? = nil, title: String? = nil, value: String? = nil, children: [AccessibilityNode] = []) {
        self.role = role
        self.title = title
        self.value = value
        self.children = children
    }
}

public enum AccessibilityContextProviderResult: Equatable {
    case success(title: String, url: URL?)
    case permissionDenied
    case windowUnavailable
    case invalidResponse
}

public protocol AccessibilityContextProviding {
    func context(for bundleID: String) -> AccessibilityContextProviderResult
}

public protocol AccessibilityNodeSource {
    func rootNode(for bundleID: String) -> AccessibilityNode?
}

public struct NativeAccessibilityContextProvider {
    public init() {}

    public func context(from node: AccessibilityNode) -> AccessibilityContextProviderResult {
        .success(title: node.title ?? "", url: nil)
    }
}

public struct FirefoxAccessibilityContextProvider {
    public let maxDepth: Int
    public let maxVisitedNodes: Int

    public init(maxDepth: Int = 16, maxVisitedNodes: Int = 256) {
        self.maxDepth = maxDepth
        self.maxVisitedNodes = maxVisitedNodes
    }

    public func context(from node: AccessibilityNode) -> AccessibilityContextProviderResult {
        var visitedCount = 0
        let url = findURL(in: node, depth: 0, visitedCount: &visitedCount)
        guard let url else {
            return .invalidResponse
        }
        return .success(title: node.title ?? "", url: url)
    }

    private func findURL(in node: AccessibilityNode, depth: Int, visitedCount: inout Int) -> URL? {
        guard depth <= maxDepth, visitedCount < maxVisitedNodes else { return nil }
        visitedCount += 1

        if let value = node.value?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty
        {
            if let url = URL(string: value), url.scheme != nil, url.host != nil {
                return url
            }

            if value.contains("://"), let url = URL(string: value), url.scheme != nil {
                return url
            }
        }

        for child in node.children {
            if let url = findURL(in: child, depth: depth + 1, visitedCount: &visitedCount) {
                return url
            }
        }

        return nil
    }
}

public struct SystemAccessibilityContextProvider: AccessibilityContextProviding {
    private let nodeSource: AccessibilityNodeSource
    private let permissionChecker: () -> Bool
    private let nativeProvider: NativeAccessibilityContextProvider
    private let firefoxProvider: FirefoxAccessibilityContextProvider

    public init(
        nodeSource: AccessibilityNodeSource = SystemAccessibilityNodeSource(),
        permissionChecker: @escaping () -> Bool = AXIsProcessTrusted,
        nativeProvider: NativeAccessibilityContextProvider = NativeAccessibilityContextProvider(),
        firefoxProvider: FirefoxAccessibilityContextProvider = FirefoxAccessibilityContextProvider()
    ) {
        self.nodeSource = nodeSource
        self.permissionChecker = permissionChecker
        self.nativeProvider = nativeProvider
        self.firefoxProvider = firefoxProvider
    }

    public func context(for bundleID: String) -> AccessibilityContextProviderResult {
        guard permissionChecker() else {
            return .permissionDenied
        }

        guard let node = nodeSource.rootNode(for: bundleID) else {
            return .windowUnavailable
        }

        if bundleID == "org.mozilla.firefox" {
            return firefoxProvider.context(from: node)
        }

        return nativeProvider.context(from: node)
    }
}

public struct SystemAccessibilityNodeSource: AccessibilityNodeSource {
    public init() {}

    private func runOnMainThread<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        } else {
            return DispatchQueue.main.sync {
                block()
            }
        }
    }

    public func rootNode(for bundleID: String) -> AccessibilityNode? {
        runOnMainThread {
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
                return nil
            }

            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appRef, 0.25)
            
            guard let window = focusedWindow(for: appRef) ?? firstWindow(for: appRef) else {
                return nil
            }

            var visitedCount = 0
            return snapshot(from: window, depth: 0, visitedCount: &visitedCount)
        }
    }

    private func focusedWindow(for appRef: AXUIElement) -> AXUIElement? {
        let value = AccessibilityValue.copy(kAXFocusedWindowAttribute as CFString, from: appRef)
        return AccessibilityValue.element(from: value)
    }

    private func firstWindow(for appRef: AXUIElement) -> AXUIElement? {
        let value = AccessibilityValue.copy(kAXWindowsAttribute as CFString, from: appRef)
        return AccessibilityValue.elements(from: value)?.first
    }

    private func snapshot(from element: AXUIElement, depth: Int, visitedCount: inout Int) -> AccessibilityNode? {
        guard depth <= 16, visitedCount < 256 else { return nil }
        visitedCount += 1

        let role = AccessibilityValue.string(from: AccessibilityValue.copy(kAXRoleAttribute as CFString, from: element))
        let title = AccessibilityValue.string(from: AccessibilityValue.copy(kAXTitleAttribute as CFString, from: element))
        let value = AccessibilityValue.string(from: AccessibilityValue.copy(kAXValueAttribute as CFString, from: element))

        var children: [AccessibilityNode] = []
        if let childElements = AccessibilityValue.elements(from: AccessibilityValue.copy(kAXChildrenAttribute as CFString, from: element)) {
            children = childElements.compactMap { snapshot(from: $0, depth: depth + 1, visitedCount: &visitedCount) }
        }

        return AccessibilityNode(role: role, title: title, value: value, children: children)
    }
}
