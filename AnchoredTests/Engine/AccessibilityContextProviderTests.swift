import XCTest
@testable import Anchored

private struct StubAccessibilityNodeSource: AccessibilityNodeSource {
    let nodeByBundleID: [String: AccessibilityNode]

    func rootNode(for bundleID: String) -> AccessibilityNode? {
        nodeByBundleID[bundleID]
    }
}

final class AccessibilityContextProviderTests: XCTestCase {
    func testAccessibilityValueHelpersUseSafeCasting() {
        let element = AXUIElementCreateSystemWide()
        XCTAssertNotNil(AccessibilityValue.element(from: element))
        XCTAssertEqual(AccessibilityValue.string(from: "hello" as NSString), "hello")
        XCTAssertNil(AccessibilityValue.string(from: NSNumber(value: 42)))
    }

    func testSystemProviderReportsPermissionDenied() {
        let provider = SystemAccessibilityContextProvider(
            nodeSource: StubAccessibilityNodeSource(nodeByBundleID: [:]),
            permissionChecker: { false }
        )

        XCTAssertEqual(provider.context(for: "com.apple.dt.Xcode"), .permissionDenied)
    }

    func testSystemProviderReportsWindowUnavailable() {
        let provider = SystemAccessibilityContextProvider(
            nodeSource: StubAccessibilityNodeSource(nodeByBundleID: [:]),
            permissionChecker: { true }
        )

        XCTAssertEqual(provider.context(for: "com.apple.dt.Xcode"), .windowUnavailable)
    }

    func testNativeProviderPreservesEmptyTitleAsSuccess() {
        let provider = NativeAccessibilityContextProvider()
        let result = provider.context(from: AccessibilityNode())

        XCTAssertEqual(result, .success(title: "", url: nil))
    }

    func testFirefoxProviderFindsURLAndKeepsEmptyTitle() {
        let provider = FirefoxAccessibilityContextProvider(maxDepth: 8, maxVisitedNodes: 32)
        let tree = AccessibilityNode(
            role: "AXWindow",
            title: "",
            value: nil,
            children: [
                AccessibilityNode(
                    role: "AXGroup",
                    children: [
                        AccessibilityNode(
                            role: "AXTextField",
                            value: "https://example.com/path",
                            children: []
                        )
                    ]
                )
            ]
        )

        XCTAssertEqual(
            provider.context(from: tree),
            .success(title: "", url: URL(string: "https://example.com/path"))
        )
    }

    func testFirefoxProviderRejectsMissingURL() {
        let provider = FirefoxAccessibilityContextProvider(maxDepth: 4, maxVisitedNodes: 16)
        let tree = AccessibilityNode(
            role: "AXWindow",
            title: "Firefox",
            children: [
                AccessibilityNode(role: "AXGroup", children: [
                    AccessibilityNode(role: "AXTextField", value: "not-a-url")
                ])
            ]
        )

        XCTAssertEqual(provider.context(from: tree), .invalidResponse)
    }

    func testFirefoxProviderStopsAtDepthLimit() {
        let provider = FirefoxAccessibilityContextProvider(maxDepth: 1, maxVisitedNodes: 16)
        let tree = AccessibilityNode(
            role: "AXWindow",
            title: "Firefox",
            children: [
                AccessibilityNode(
                    role: "AXGroup",
                    children: [
                        AccessibilityNode(role: "AXGroup", children: [
                            AccessibilityNode(role: "AXTextField", value: "https://example.com")
                        ])
                    ]
                )
            ]
        )

        XCTAssertEqual(provider.context(from: tree), .invalidResponse)
    }
}
