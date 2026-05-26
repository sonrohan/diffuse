import AppKit
import SwiftUI

/// A transparent helper view that bridges AppKit's native window dragging behaviour to SwiftUI.
/// Placing this view in the background of any custom header or bar allows the user to
/// reposition the window by clicking and dragging on empty background areas.
public struct WindowDragView: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = DragNSView()
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    private class DragNSView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            // Initiate system window dragging on mouseDown
            window?.performDrag(with: event)
        }
    }
}
