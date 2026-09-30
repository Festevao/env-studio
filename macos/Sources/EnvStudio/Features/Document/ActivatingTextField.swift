import AppKit
import SwiftUI

enum SingleLineFieldPolicy {
    static func sanitize(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    static func configureSingleLineScrollable(_ field: NSTextField) {
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true
        if let cell = field.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = true
            cell.lineBreakMode = .byClipping
            cell.truncatesLastVisibleLine = false
        }
    }
}

private final class ClickActivatingTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        AppActivation.activateForUserInput()
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }
}

private final class ClickActivatingSecureTextField: NSSecureTextField {
    override func mouseDown(with event: NSEvent) {
        AppActivation.activateForUserInput()
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }
}

struct ActivatingTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isSecure: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure
            ? ClickActivatingSecureTextField()
            : ClickActivatingTextField()
        field.placeholderString = placeholder
        field.stringValue = SingleLineFieldPolicy.sanitize(text)
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        SingleLineFieldPolicy.configureSingleLineScrollable(field)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.editingEnded(_:))
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        let sanitized = SingleLineFieldPolicy.sanitize(text)
        if nsView.stringValue != sanitized {
            nsView.stringValue = sanitized
        }
        SingleLineFieldPolicy.configureSingleLineScrollable(nsView)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            applySanitized(to: field)
        }

        @objc func editingEnded(_ sender: NSTextField) {
            applySanitized(to: sender)
        }

        private func applySanitized(to field: NSTextField) {
            let sanitized = SingleLineFieldPolicy.sanitize(field.stringValue)
            if field.stringValue != sanitized {
                field.stringValue = sanitized
            }
            if text.wrappedValue != sanitized {
                text.wrappedValue = sanitized
            }
        }
    }
}
