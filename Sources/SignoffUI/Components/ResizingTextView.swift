import AppKit

/// An `NSTextView` subclass that adds a context menu to resize images inserted
/// as `ScalableImageAttachment`. Right-/control-click an image → Small / Medium
/// / Large / Actual Size. Also supports drag-to-reposition images and visual
/// resize handles when an attachment is selected. Mutations call `didChangeText()`
/// so the SwiftUI document binding stays in sync and persists.
@MainActor
final class ResizingTextView: NSTextView {
    private var pendingIndex: Int?
    private var pendingAttachment: ScalableImageAttachment?

    // Drag repositioning state
    private var dragStartLocation: NSPoint?
    private var dragAttachmentIndex: Int?
    private var dragAttachmentOffset: NSPoint?

    // Resize handle state
    private var selectedAttachmentIndex: Int?
    private var selectedAttachmentHandle: ResizeHandle?

    enum ResizeHandle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if index != NSNotFound,
           let att = textStorage?.attribute(.attachment, at: index, effectiveRange: nil) as? ScalableImageAttachment {
            selectedAttachmentIndex = index
            return resizeMenu(characterIndex: index, attachment: att)
        }
        return super.menu(for: event)
    }

    private func resizeMenu(characterIndex: Int, attachment: ScalableImageAttachment) -> NSMenu {
        pendingIndex = characterIndex
        pendingAttachment = attachment
        let menu = NSMenu(title: "Resize Image")
        let presets: [(String, Selector, CGFloat)] = [
            ("Small", #selector(setImageSmall(_:)), 0.25),
            ("Medium", #selector(setImageMedium(_:)), 0.50),
            ("Large", #selector(setImageLarge(_:)), 0.75),
            ("Actual Size", #selector(setImageActual(_:)), 1.0),
        ]
        for (title, action, _) in presets {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func setImageSmall(_ sender: Any?) { applyScale(0.25) }
    @objc private func setImageMedium(_ sender: Any?) { applyScale(0.50) }
    @objc private func setImageLarge(_ sender: Any?) { applyScale(0.75) }
    @objc private func setImageActual(_ sender: Any?) { applyScale(1.0) }

    // MARK: - Drag & drop (auto-fit dropped images)

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard let images = pb.readObjects(forClasses: [NSImage.self],
                                          options: nil) as? [NSImage],
              !images.isEmpty else {
            return super.performDragOperation(sender)
        }
        let point = convert(sender.draggingLocation, from: nil)
        var index = characterIndexForInsertion(at: point)
        if index == NSNotFound { index = selectedRange().location }

        guard let storage = textStorage else { return false }
        let containerWidth = textContainer?.size.width ?? bounds.width
        let maxWidth = max(min(containerWidth - 16, 240), 100)

        storage.beginEditing()
        var insertAt = index
        for image in images {
            let displaySize = ScalableImageAttachment.fit(image: image, maxWidth: maxWidth)
            let attachment = ScalableImageAttachment(image: image, displaySize: displaySize)
            let attr = NSAttributedString(attachment: attachment)
            storage.insert(attr, at: insertAt)
            insertAt += attr.length
        }
        storage.endEditing()
        setSelectedRange(NSRange(location: insertAt, length: 0))
        didChangeText()
        needsDisplay = true
        scrollRangeToVisible(selectedRange())
        return true
    }

    // MARK: - Mouse handling for drag repositioning and resize handles

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)

        if index != NSNotFound,
           let _ = textStorage?.attribute(.attachment, at: index, effectiveRange: nil) as? ScalableImageAttachment {
            // Check if clicking on a resize handle
            if let handle = hitTestResizeHandle(at: point, for: index) {
                selectedAttachmentIndex = index
                selectedAttachmentHandle = handle
                // Store initial state for resize
                dragStartLocation = point
                return
            }

            // Otherwise start drag to reposition
            dragStartLocation = point
            dragAttachmentIndex = index

            // Get the attachment's display rect for offset calculation
            if let layoutManager = layoutManager,
               let textContainer = textContainer {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
                let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
                let containerOrigin = textContainerOrigin
                let attachmentOrigin = NSPoint(x: containerOrigin.x + glyphRect.minX, y: containerOrigin.y + glyphRect.minY)
                dragAttachmentOffset = NSPoint(x: point.x - attachmentOrigin.x, y: point.y - attachmentOrigin.y)
            }
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Handle resize if a handle is selected
        if let handle = selectedAttachmentHandle, let index = selectedAttachmentIndex,
           let att = textStorage?.attribute(.attachment, at: index, effectiveRange: nil) as? ScalableImageAttachment,
           let start = dragStartLocation {
            let deltaX = point.x - start.x
            let deltaY = point.y - start.y
            handleResize(attachment: att, index: index, handle: handle, deltaX: deltaX, deltaY: deltaY)
            dragStartLocation = point
            return
        }

        // Handle drag to reposition
        if let _ = dragStartLocation,
           let index = dragAttachmentIndex,
           let _ = textStorage?.attribute(.attachment, at: index, effectiveRange: nil) as? ScalableImageAttachment {
            // For text-based repositioning, we need to delete and re-insert at new location
            // This is a simplified approach - full implementation would be more complex
            let _ = point
            // Just update selection for visual feedback during drag
            setSelectedRange(NSRange(location: index, length: 1))
        }

        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        // Complete drag reposition if we dragged an attachment
        if let start = dragStartLocation,
           let index = dragAttachmentIndex,
           let _ = textStorage?.attribute(.attachment, at: index, effectiveRange: nil) as? ScalableImageAttachment {
            let point = convert(event.locationInWindow, from: nil)
            // Check if moved significantly
            let distance = hypot(point.x - start.x, point.y - start.y)
            if distance > 5 { // Threshold for intentional drag
                // Move the attachment to the new caret position
                moveAttachment(from: index, to: point)
            }
        }

        dragStartLocation = nil
        dragAttachmentIndex = nil
        dragAttachmentOffset = nil
        selectedAttachmentIndex = nil
        selectedAttachmentHandle = nil

        super.mouseUp(with: event)
    }

    private func hitTestResizeHandle(at point: NSPoint, for index: Int) -> ResizeHandle? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return nil }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        let containerOrigin = textContainerOrigin
        let attachmentRect = NSRect(
            x: containerOrigin.x + glyphRect.minX,
            y: containerOrigin.y + glyphRect.minY,
            width: glyphRect.width,
            height: glyphRect.height
        )

        let handleSize: CGFloat = 10
        let handles: [(ResizeHandle, NSRect)] = [
            (.topLeft, NSRect(x: attachmentRect.minX - handleSize/2, y: attachmentRect.minY - handleSize/2, width: handleSize, height: handleSize)),
            (.topRight, NSRect(x: attachmentRect.maxX - handleSize/2, y: attachmentRect.minY - handleSize/2, width: handleSize, height: handleSize)),
            (.bottomLeft, NSRect(x: attachmentRect.minX - handleSize/2, y: attachmentRect.maxY - handleSize/2, width: handleSize, height: handleSize)),
            (.bottomRight, NSRect(x: attachmentRect.maxX - handleSize/2, y: attachmentRect.maxY - handleSize/2, width: handleSize, height: handleSize))
        ]

        for (handle, rect) in handles {
            if rect.contains(point) { return handle }
        }
        return nil
    }

    private func handleResize(attachment: ScalableImageAttachment, index: Int, handle: ResizeHandle, deltaX: CGFloat, deltaY: CGFloat) {
        var newSize = attachment.displaySize
        let minSize: CGFloat = 20

        switch handle {
        case .topLeft:
            newSize.width = max(minSize, newSize.width - deltaX)
            newSize.height = max(minSize, newSize.height - deltaY)
        case .topRight:
            newSize.width = max(minSize, newSize.width + deltaX)
            newSize.height = max(minSize, newSize.height - deltaY)
        case .bottomLeft:
            newSize.width = max(minSize, newSize.width - deltaX)
            newSize.height = max(minSize, newSize.height + deltaY)
        case .bottomRight:
            newSize.width = max(minSize, newSize.width + deltaX)
            newSize.height = max(minSize, newSize.height + deltaY)
        }

        // Constrain proportions
        if let origImage = attachment.image {
            let ratio = origImage.size.height / origImage.size.width
            // Maintain aspect ratio based on which dimension changed more
            if abs(deltaX) > abs(deltaY) {
                newSize.height = newSize.width * ratio
            } else {
                newSize.width = newSize.height / ratio
            }
        }

        // Apply the new size
        textStorage?.beginEditing()
        attachment.setDisplaySize(newSize)
        textStorage?.addAttribute(.attachment, value: attachment, range: NSRange(location: index, length: 1))
        textStorage?.endEditing()
        didChangeText()
        needsDisplay = true
    }

    private func moveAttachment(from oldIndex: Int, to point: NSPoint) {
        let newIndex = characterIndexForInsertion(at: point)
        guard newIndex != NSNotFound, newIndex != oldIndex else { return }

        textStorage?.beginEditing()
        // Remove from old position
        textStorage?.replaceCharacters(in: NSRange(location: oldIndex, length: 1), with: NSAttributedString())
        // Insert at new position (adjust for removal if before new position)
        let adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex
        let attr = NSAttributedString(attachment: (textStorage?.attribute(.attachment, at: oldIndex, effectiveRange: nil) as? ScalableImageAttachment)!)
        textStorage?.insert(attr, at: adjustedIndex)
        textStorage?.endEditing()
        didChangeText()
        needsDisplay = true
        setSelectedRange(NSRange(location: adjustedIndex + 1, length: 0))
    }

    private func applyScale(_ scale: CGFloat) {
        guard let index = pendingIndex, let att = pendingAttachment else { return }
        textStorage?.beginEditing()
        att.setScale(scale)
        // Re-set the attribute so the layout manager invalidates + re-renders.
        textStorage?.addAttribute(.attachment, value: att, range: NSRange(location: index, length: 1))
        textStorage?.endEditing()
        didChangeText()
        needsDisplay = true
        pendingIndex = nil
        pendingAttachment = nil
    }
}
