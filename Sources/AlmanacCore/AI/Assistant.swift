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
    You are the analyst inside Almanac, a Mac app that shows an indie developer their App Store data.
    Answer from the data you are given. Quote real numbers. If the data can't answer, say what's missing.
    Be brief and concrete: short paragraphs, plain words, a small table when it helps. No preamble.
    For App Store Optimization advice, follow Apple's own guidance: name (30 chars) and subtitle (30) and keyword field (100, comma separated, no spaces) are indexed; never repeat a word across them; plurals and the app's category are matched automatically.
    """

    public enum AssistantError: Error, LocalizedError {
        case notInstalled(String), failed(String)
        public var errorDescription: String? {
            switch self {
            case .notInstalled(let p): "Couldn't find the \(p) command. Install it and sign in, then try again."
            case .failed(let m): m
            }
        }
    }

    public func isInstalled() async -> Bool {
        (try? await Self.shell("command -v \(provider.rawValue)", stdin: "")).map { !$0.isEmpty } ?? false
    }

    public func ask(_ question: String, context: String, history: [(role: String, text: String)] = []) async throws -> String {
        guard await isInstalled() else { throw AssistantError.notInstalled(provider.rawValue) }
        var prompt = "<data>\n\(context)\n</data>\n\n"
        for h in history.suffix(10) { prompt += "\(h.role == "user" ? "Developer" : "You"): \(h.text)\n\n" }
        prompt += "Developer: \(question)"
        let cmd: String
        switch provider {
        case .claude:
            cmd = "claude -p --tools '' --model \(Self.quote(model)) --output-format text --system-prompt \(Self.quote(Self.systemPrompt))"
        case .codex:
            prompt = Self.systemPrompt + "\n\n" + prompt
            cmd = "codex exec --skip-git-repo-check -"
        }
        let out = try await Self.shell(cmd, stdin: prompt)
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw AssistantError.failed("\(provider.title) returned nothing. Run `\(provider.rawValue)` once in Terminal to check you're signed in.") }
        return trimmed
    }

    /// CLI failure text without config warnings (they mask the real cause), sign-in problems spelled out.
    static func explain(_ raw: String) -> String {
        let lines = raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Permission allow rule") && !$0.hasPrefix("Permission deny rule") && !$0.hasPrefix("Permission ask rule") }
        let text = lines.joined(separator: "\n")
        let l = text.lowercased()
        if l.contains("authenticate") || l.contains("oauth") || l.contains("logged out") || l.contains("/login") || l.contains("not logged in") {
            return "Claude Code is signed out. Run `claude /login` in Terminal, then ask again."
        }
        return text.isEmpty ? "The AI command failed without saying why." : String(text.suffix(500))
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func shell(_ command: String, stdin: String) async throws -> String {
        #if !os(macOS)
        throw AssistantError.failed("AI chat runs in the Mac app, with your own Claude Code or Codex.")
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
