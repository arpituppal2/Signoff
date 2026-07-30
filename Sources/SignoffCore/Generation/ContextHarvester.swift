import Foundation
import AppKit
import ApplicationServices
import Carbon

/// Harvests context from the frontmost application for context-aware signoff generation.
/// Paid tier only: reads the selected text or focused text element from the active app
/// to understand what message the user is replying to, enabling relevant signoffs.
/// Not formally Sendable — AX API calls are not Sendable-safe — but accessed only
/// from `@MainActor` contexts, so strict isolation is unnecessary.
public struct ContextHarvester: @unchecked Sendable {
    
    public static let shared = ContextHarvester()
    
    public struct HarvestedContext: Sendable, Equatable {
        /// The text of the message being replied to (from selection or focused element).
        public let messageText: String
        /// The app the user is typing in.
        public let sourceApp: String
        /// Truncated preview for display.
        public var preview: String {
            let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 200 {
                return String(trimmed.prefix(200)) + "..."
            }
            return trimmed
        }
        
        public init(messageText: String, sourceApp: String) {
            self.messageText = messageText
            self.sourceApp = sourceApp
        }
    }
    
    /// Harvest context from the frontmost application.
    /// Returns nil if:
    /// - Accessibility permission is not granted
    /// - No text element is focused
    /// - The focused element is empty
    public func harvest() async -> HarvestedContext? {
        guard AccessibilityTrusted() else { return nil }
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else {
            return nil
        }
        
        let appPID = frontApp.processIdentifier
        let appRef = AXUIElementCreateApplication(appPID)
        
        // Try to get the focused UI element
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, "AXFocusedUIElement" as CFString, &focusedElement)
        
        guard result == .success,
              let element = focusedElement else {
            return nil
        }
        
        let elementRef = element as! AXUIElement
        
        // Try selected text first (most reliable)
        if let selectedText = getSelectedText(from: elementRef), !selectedText.isEmpty {
            return HarvestedContext(messageText: selectedText, sourceApp: appName)
        }
        
        // Fall back to the value of the focused element (text field content)
        if let valueText = getElementValue(from: elementRef), !valueText.isEmpty {
            return HarvestedContext(messageText: valueText, sourceApp: appName)
        }
        
        return nil
    }
    
    /// Harvest context from the provided text (e.g., clipboard or passed context).
    /// Used when AX harvest fails but we have text from another source.
    public func harvest(from text: String, sourceApp: String = "Unknown") -> HarvestedContext? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return HarvestedContext(messageText: trimmed, sourceApp: sourceApp)
    }
    
    // MARK: - Private Helpers
    
    private func AccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }
    
    private func getSelectedText(from element: AXUIElement) -> String? {
        var selectedText: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, "AXSelectedText" as CFString, &selectedText)
        guard result == .success, let text = selectedText as? String, !text.isEmpty else {
            return nil
        }
        return text
    }
    
    private func getElementValue(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, "AXValue" as CFString, &value)
        guard result == .success, let text = value as? String, !text.isEmpty else {
            return nil
        }
        return text
    }
}
