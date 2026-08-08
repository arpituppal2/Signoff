import Foundation
import AppKit
import ApplicationServices

/// Resolves the insertion-point (caret) rect, in AppKit screen coordinates, of
/// the system-wide focused text element via Accessibility.
///
/// Used by the shortcut signature animation to place the little `signature`
/// SF Symbol right where the user is typing. Best-effort: many apps implement
/// `AXBoundsForRange`, some don't; on failure we return `nil` and the caller
/// simply shows the overlay above the menu-bar area instead of failing generation.
///
/// Crash fix: the previous version force-unwrapped `CFTypeRef?` references
/// (`ref! as! AXValue`) after only checking `ref != nil`. When AX returned `nil`
/// under an untrusted or non-text state, that crashed generation (`EXC_BAD_ACCESS`).
/// We now optional-bind every ref, so an empty AX state degrades to `nil` instead.
@MainActor
public final class CaretLocator {
    public static let shared = CaretLocator()
    private init() {}

    /// AppKit bottom-left-origin screen rect of the current selection/caret,
    /// or `nil` if the focused element doesn't expose text bounds via AX.
    public func caretScreenRect() -> NSRect? {
        let system = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system,
                                             kAXFocusedUIElementAttribute as CFString,
                                             &focusedRef) == .success,
              let focusedRaw = focusedRef else {
            return nil
        }
        let focused = focusedRaw as! AXUIElement

        var resultRect = CGRect.zero
        var gotBounds = false

        // 1. Preferred: bounds for the selection range, widened to ≥1 char so a
        //    0-length caret still resolves a glyph rect.
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused,
                                          kAXSelectedTextRangeAttribute as CFString,
                                          &rangeRef) == .success,
           let rangeRaw = rangeRef {
            let rangeValue = rangeRaw as! AXValue
            var cfRange = CFRange(location: 0, length: 0)
            if AXValueGetValue(rangeValue, .cfRange, &cfRange), cfRange.location != -1 {
                var queryRange = CFRange(location: max(cfRange.location, 0),
                                        length: max(cfRange.length, 1))
                if let queryValue = AXValueCreate(.cfRange, &queryRange) {
                    var boundsRef: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(
                        focused,
                        kAXBoundsForRangeParameterizedAttribute as CFString,
                        queryValue,
                        &boundsRef) == .success,
                       let boundsRaw = boundsRef {
                        let boundsValue = boundsRaw as! AXValue
                        var r = CGRect.zero
                        if AXValueGetValue(boundsValue, .cgRect, &r),
                           r.width > 0, r.height > 0 {
                            resultRect = r
                            gotBounds = true
                        }
                    }
                }
            }
        }

        // 2. Fallback: the whole element frame (less precise — field, not caret).
        if !gotBounds {
            let frame = elementFrame(of: focused)
            if frame.width > 0, frame.height > 0 {
                resultRect = frame
                gotBounds = true
            }
        }

        guard gotBounds else { return nil }

        // Convert top-left-origin (CG) → bottom-left-origin (AppKit/NSScreen).
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let flippedY = screen.frame.maxY - resultRect.minY - resultRect.height
        return NSRect(x: resultRect.minX,
                       y: flippedY,
                       width: max(resultRect.width, 2),
                       height: max(resultRect.height, 2))
    }

    private func elementFrame(of element: AXUIElement) -> CGRect {
        var position = CGPoint.zero
        var size = CGSize.zero
        var posRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           let posRaw = posRef {
            let posValue = posRaw as! AXValue
            _ = AXValueGetValue(posValue, .cgPoint, &position)
        }
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeRaw = sizeRef {
            let sizeValue = sizeRaw as! AXValue
            _ = AXValueGetValue(sizeValue, .cgSize, &size)
        }
        return CGRect(origin: position, size: size)
    }
}
