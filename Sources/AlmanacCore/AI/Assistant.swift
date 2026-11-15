import Foundation

/// Runs the user's own `claude` or `codex` CLI, under their own subscription.
/// Goes through a login shell so PATH matches their terminal (nvm, Homebrew, ~/.local/bin).
public struct Assistant: Sendable {
    public enum Provider: String, CaseIterable, Identifiable, Sendable {
        case claude, codex
        public var id: String { rawValue }
        public var title: String { self == .claude ? "Claude Code" : "Codex" }
    }

    public var provider: Provider
    public var model: String
    public init(provider: Provider = .claude, model: String = "sonnet") { self.provider = provider; self.model = model }

    public static let systemPrompt = """
    You are the analyst inside Vane, an app that shows an indie developer their App Store data.
    Answer from the data you are given. Quote real numbers. If the data can't answer, say what's missing.
    Be brief and concrete: two to four short paragraphs or a few bullets, plain words. No preamble, no headings, no tables: the answer shows in a narrow side panel.
    Don't repeat the numbers back as a list; use them inside sentences. A value marked "not available yet" is missing, not zero.
    Start with the answer itself. Never say Vane lacks a number that is in the data, and don't send the user to App Store Connect for something the data already shows.
    For App Store Optimization advice, follow Apple's own guidance: name (30 chars) and subtitle (30) and keyword field (100, comma separated, no spaces) are indexed; never repeat a word across them; plurals and the app's category are matched automatically.
    Reply in the language of the developer's last message, whatever the app's language. If that message gives no clue (a bare number, a name), use the language with code \(Locale.preferredLanguages.first ?? "en").
    """

    public enum AssistantError: Error, LocalizedError {
        case notInstalled(String), failed(String)
        public var errorDescription: String? {
            switch self {
            case .notInstalled(let p): String(localized: "Couldn't find the \(p) command. Install it and sign in, then try again.")
            case .failed(let m): m
            }
        }
    }

    public func isInstalled() async -> Bool { await location() != nil }

    /// Where the command lives in the user's shell PATH, nil if it isn't there.
    public func location() async -> String? {
        (try? await Self.shell("command -v \(provider.rawValue)", stdin: ""))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The read-only MCP server shipped next to the app's executable (Contents/MacOS/vane-mcp), nil outside the Mac app.
    static var mcpServer: String? {
        Bundle.main.executableURL.map { $0.deletingLastPathComponent().appendingPathComponent("vane-mcp").path }
            .flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
    }

    static let toolsPrompt = """
    You also have read-only SQL access to the developer's whole Vane database through the vane tools (schema, then query).
    When the data block doesn't hold what the question needs (another period, a country's daily series, download sources, reviews, releases), look it up instead of saying it's missing. Keep queries few and aggregated.
    Never mention tables, SQL, queries or tools in your answer: speak about the data itself.
    """

    /// `database`: give the assistant read-only SQL access to that Vane database (Claude only; slower, so chats only).
    public func ask(_ question: String, context: String, history: [(role: String, text: String)] = [], database: String? = nil) async throws -> String {
        guard await isInstalled() else { throw AssistantError.notInstalled(provider.rawValue) }
        var prompt = "<data>\n\(context)\n</data>\n\n"
        for h in history.suffix(10) { prompt += "\(h.role == "user" ? "Developer" : "You"): \(h.text)\n\n" }
        prompt += "Developer: \(question)"
        let cmd: String
        switch provider {
        case .claude:
            if let database, let server = Self.mcpServer,
               let json = try? JSONSerialization.data(withJSONObject: ["mcpServers": ["vane": ["command": server, "args": [database]]]]) {
                cmd = "claude -p --tools '' --strict-mcp-config --mcp-config \(Self.quote(String(decoding: json, as: UTF8.self)))"
                    + " --allowedTools mcp__vane__schema mcp__vane__query --model \(Self.quote(model)) --output-format text"
                    + " --system-prompt \(Self.quote(Self.systemPrompt + "\n" + Self.toolsPrompt + "\n" + AssistantLink.prompt))"
            } else {
                let links = database == nil ? "" : "\n" + AssistantLink.prompt   // chats only: they show the buttons
                cmd = "claude -p --tools '' --model \(Self.quote(model)) --output-format text --system-prompt \(Self.quote(Self.systemPrompt + links))"
            }
        case .codex:
            prompt = Self.systemPrompt + "\n\n" + prompt
            cmd = "codex exec --skip-git-repo-check -"
        }
        let out = try await Self.shell(cmd, stdin: prompt)
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw AssistantError.failed(String(localized: "\(provider.title) returned nothing. Run `\(provider.rawValue)` once in Terminal to check you're signed in.")) }
        return trimmed
    }

    /// CLI failure text without config warnings (they mask the real cause), sign-in problems spelled out.
    static func explain(_ raw: String) -> String {
        let lines = raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Permission allow rule") && !$0.hasPrefix("Permission deny rule") && !$0.hasPrefix("Permission ask rule") }
        let text = lines.joined(separator: "\n")
        let l = text.lowercased()
        if l.contains("authenticate") || l.contains("oauth") || l.contains("logged out") || l.contains("/login") || l.contains("not logged in") {
            return String(localized: "Claude Code is signed out. Run claude /login in Terminal, then try again.")
        }
        return text.isEmpty ? String(localized: "The AI command failed without saying why.") : String(text.suffix(500))
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func shell(_ command: String, stdin: String) async throws -> String {
        #if !os(macOS)
        throw AssistantError.failed(String(localized: "AI chat runs in the Mac app, with your own Claude Code or Codex."))
        #else
        return try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", command]
            p.currentDirectoryURL = FileManager.default.temporaryDirectory
            let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
            p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
            try p.run()
            // Write stdin and drain stderr concurrently so neither pipe can fill up and block the child.
            DispatchQueue.global().async {
                inPipe.fileHandleForWriting.write(Data(stdin.utf8))
                try? inPipe.fileHandleForWriting.close()
            }
            var errData = Data()
            let errDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); errDone.signal() }
            let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            errDone.wait()
            guard p.terminationStatus == 0 else {
                throw AssistantError.failed(Self.explain(String(decoding: errData, as: UTF8.self) + "\n" + out))
            }
            return out
        }.value
        #endif
    }
}
