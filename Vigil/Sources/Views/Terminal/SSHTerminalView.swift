import SwiftUI
import AppKit

/// A native SSH terminal that spawns an ssh process connected to a pseudo-terminal.
struct SSHTerminalView: NSViewRepresentable {
    let server: Server
    @Binding var masterFileDescriptor: Int32

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = TerminalTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        context.coordinator.masterFDBinding = $masterFileDescriptor
        context.coordinator.startSSH(server: server)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.stop()
    }

    class Coordinator: @unchecked Sendable {
        var textView: TerminalTextView?
        var masterFDBinding: Binding<Int32>?
        private var process: Process?
        private var masterFD: Int32 = -1
        private var readSource: DispatchSourceRead?

        func startSSH(server: Server) {
            var slaveFD: Int32 = -1
            masterFD = posix_openpt(O_RDWR | O_NOCTTY)
            guard masterFD >= 0 else {
                appendOutputOnMain("Failed to open pseudo-terminal\r\n")
                return
            }
            guard grantpt(masterFD) == 0, unlockpt(masterFD) == 0 else {
                appendOutputOnMain("Failed to configure pseudo-terminal\r\n")
                return
            }

            guard let slaveName = ptsname(masterFD) else {
                appendOutputOnMain("Failed to get slave pty name\r\n")
                return
            }
            let slavePath = String(cString: slaveName)
            slaveFD = open(slavePath, O_RDWR)
            guard slaveFD >= 0 else {
                appendOutputOnMain("Failed to open slave pty\r\n")
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

            var args = [String]()
            args.append("-o"); args.append("StrictHostKeyChecking=accept-new")
            args.append("-t")
            args.append("-p"); args.append("\(server.port)")

            switch server.authMethod {
            case .key(let path):
                if !path.isEmpty {
                    args.append("-i"); args.append(path)
                }
            case .password:
                appendOutputOnMain("Password authentication is not yet supported.\r\n")
                return
            }

            let host = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
            let username = server.username.trimmingCharacters(in: .whitespacesAndNewlines)
            args.append("\(username)@\(host)")

            process.arguments = args
            process.standardInput = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
            process.standardOutput = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
            process.standardError = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)

            // Read from master fd on a background queue
            let fd = masterFD
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInteractive))
            source.setEventHandler { [weak self] in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                self?.appendOutputOnMain(text)
            }
            let slaveFDCopy = slaveFD
            source.setCancelHandler {
                close(slaveFDCopy)
            }
            source.resume()
            self.readSource = source

            // Set up the text view to write to master and expose FD to SwiftUI
            DispatchQueue.main.async { [weak self] in
                self?.textView?.masterFD = fd
                self?.masterFDBinding?.wrappedValue = fd
            }

            do {
                try process.run()
                self.process = process
            } catch {
                appendOutputOnMain("Failed to launch SSH: \(error.localizedDescription)\r\n")
            }
        }

        private func appendOutputOnMain(_ text: String) {
            DispatchQueue.main.async { [weak self] in
                guard let textView = self?.textView else { return }

                // Strip basic ANSI escape sequences
                let cleaned = text.replacingOccurrences(
                    of: #"\x1b(\[[0-9;?]*[a-zA-Z@]|\][^\x07]*\x07|\(B)"#,
                    with: "",
                    options: .regularExpression
                )

                let attributed = NSAttributedString(
                    string: cleaned,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                        .foregroundColor: NSColor.labelColor
                    ]
                )

                textView.textStorage?.append(attributed)
                textView.scrollToEndOfDocument(nil)
            }
        }

        func stop() {
            readSource?.cancel()
            readSource = nil
            process?.terminate()
            process = nil
            if masterFD >= 0 {
                close(masterFD)
                masterFD = -1
            }
            DispatchQueue.main.async { [weak self] in
                self?.masterFDBinding?.wrappedValue = -1
            }
        }
    }
}

/// Custom NSTextView that intercepts keystrokes and writes them to the pty master
class TerminalTextView: NSTextView {
    var masterFD: Int32 = -1

    override func keyDown(with event: NSEvent) {
        // Let Cmd shortcuts (Cmd+C, Cmd+V, Cmd+Q, Cmd+W, etc.) pass through to the responder chain
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }

        guard masterFD >= 0 else { return }

        var bytes: Data?

        switch event.keyCode {
        case 36: // Return
            bytes = Data("\r".utf8)
        case 51: // Backspace
            bytes = Data([0x7f])
        case 48: // Tab
            bytes = Data("\t".utf8)
        case 53: // Escape
            bytes = Data([0x1b])
        case 123: // Left arrow
            bytes = Data("\u{1b}[D".utf8)
        case 124: // Right arrow
            bytes = Data("\u{1b}[C".utf8)
        case 125: // Down arrow
            bytes = Data("\u{1b}[B".utf8)
        case 126: // Up arrow
            bytes = Data("\u{1b}[A".utf8)
        default:
            if let chars = event.characters {
                bytes = Data(chars.utf8)
            }
        }

        if let bytes = bytes {
            let fd = masterFD
            bytes.withUnsafeBytes { ptr in
                _ = write(fd, ptr.baseAddress!, ptr.count)
            }
        }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // Handled by keyDown
    }

    override func paste(_ sender: Any?) {
        guard masterFD >= 0,
              let text = NSPasteboard.general.string(forType: .string) else { return }
        let fd = masterFD
        let data = Data(text.utf8)
        data.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, ptr.count)
        }
    }
}
