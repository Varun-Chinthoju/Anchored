import Foundation
import ApplicationServices

enum AccessibilityValue {
    static func copy(_ attribute: CFString, from element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return nil }
        return value
    }

    static func string(from value: AnyObject?) -> String? {
        value as? String
    }

    static func element(from value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    static func elements(from value: AnyObject?) -> [AXUIElement]? {
        guard let array = value as? [AnyObject] else {
            return nil
        }

        let elements = array.compactMap { element(from: $0) }
        return elements.isEmpty ? nil : elements
    }
}
