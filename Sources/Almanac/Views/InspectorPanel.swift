#if os(macOS)
import AlmanacCore
import AppKit
import SwiftUI

/// "Ask about this screen": the Mac inspector. Each screen publishes its data to `model.chatContext`.
struct InspectorPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var busy = false

    private let starters = [String(localized: "Explain this to me"), String(localized: "What changed recently, and why?"), String(localized: "What should I do next?")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask about this screen").font(t.font(13, .semibold))
                    Text("\(AISettings.provider.title) · \(model.section.title)").font(t.font(11)).foregroundStyle(t.label2).lineLimit(1)
                }
                Spacer()
                if !messages.isEmpty {
                    iconButton("square.and.pencil", help: String(localized: "New chat")) { messages = [] }
                }
                iconButton("xmark", help: String(localized: "Close")) { model.chatOpen = false }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if messages.isEmpty {
                            Text("Ask about the chart, table or report you're looking at. The answer comes from your own \(AISettings.provider.title) account; your data goes straight from this Mac to it.")
                                .font(t.font(13)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(messages) { bubble($0).id($0.id) }
                        if busy { ProgressView().controlSize(.small).id("busy") }
                        if !busy && messages.last?.role == "assistant" {
                            Text("Based on the \(model.section.title) data on this screen. Nothing else left this Mac.")
                                .font(t.font(11)).foregroundStyle(t.label2)
                        }
                        if !busy {
                            VStack(spacing: 8) {
                                ForEach(messages.isEmpty ? starters : Array(starters.dropFirst()), id: \.self) { q in
                                    Button { send(q) } label: {
                                        Text(q).font(t.font(12, .semibold)).foregroundStyle(t.label).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 7).frame(minHeight: 30)
                                            .background(t.fill, in: RoundedRectangle(cornerRadius: t.rS, style: .continuous))
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
                .scrollIndicators(.never)
                .onChange(of: messages) { withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) } }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about \(model.section.title)…", text: $input, axis: .vertical)
                    .lineLimit(1...5).textFieldStyle(.plain).font(t.font(13))
                    .onSubmit { send(input) }
                    .padding(.vertical, 9)
                Button { send(input) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundStyle(t.onAccent)
                        .frame(width: 24, height: 24).background(t.accent, in: Circle())
                }
                .buttonStyle(.plain).padding(.bottom, 6)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            .padding(.leading, 14).padding(.trailing, 6)
            .frame(minHeight: 36)
            .background(t.field, in: RoundedRectangle(cornerRadius: t.inner(12, in: t.r - 4), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: t.inner(12, in: t.r - 4), style: .continuous).strokeBorder(t.sep2, lineWidth: 1))
            .padding(12)
        }
        .onAppear(perform: consumeSeed)
        .onChange(of: model.chatSeed) { consumeSeed() }
    }

    private func iconButton(_ s: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: s).font(.system(size: 11, weight: .semibold)).foregroundStyle(t.label2)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    @ViewBuilder private func bubble(_ m: ChatMessage) -> some View {
        switch m.role {
        case "user":
            Text(m.text).font(t.font(13)).foregroundStyle(t.onAccent)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(t.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: 232, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case "error":
            VStack(alignment: .leading, spacing: 8) {
                Label(m.text, systemImage: "exclamationmark.triangle").font(t.font(13)).foregroundStyle(t.warn)
                if m.text.contains("claude /login") {
                    // One click instead of "open Terminal and type this": Terminal runs the CLI's own sign-in.
                    SmallButton(label: String(localized: "Sign In in Terminal")) {
                        let script = "tell application \"Terminal\"\n activate\n do script \"claude /login\"\nend tell"
                        NSAppleScript(source: script)?.executeAndReturnError(nil)
                    }
                }
            }
        default:
            ChatMarkdown(text: m.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.text, forType: .string) }
                }
        }
    }

    private func consumeSeed() {
        guard let q = model.chatSeed else { return }
        model.chatSeed = nil
        send(q)
    }

    private func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        let history = messages.filter { $0.role != "error" }.map { (role: $0.role, text: $0.text) }
        messages.append(ChatMessage(role: "user", text: q))
        input = ""
        busy = true
        let context = "App: \(model.app?.name ?? "") (id \(model.appId ?? ""))\nToday: \(Day.today())\n\(model.chatContext)"
        Task {
            do { messages.append(ChatMessage(role: "assistant", text: try await AISettings.assistant.ask(q, context: context, history: history, database: model.store.path))) }
            catch { messages.append(ChatMessage(role: "error", text: error.localizedDescription)) }
            busy = false
        }
    }
}

/// Markdown for a narrow panel: paragraphs, bullets, numbered items and headings. Tables become
/// "cell · cell" lines (their separator rows dropped) so nothing shows raw pipes.
private struct ChatMarkdown: View {
    @Environment(\.theme) private var t
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b.kind {
                case .heading: inline(b.text).font(t.font(13, .semibold))
                case .bullet(let mark):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(mark).font(t.font(13)).foregroundStyle(t.label2).monospacedDigit()
                        inline(b.text).font(t.font(13))
                    }
                case .row: inline(b.text).font(t.font(12)).foregroundStyle(t.label2).monospacedDigit()
                case .paragraph: inline(b.text).font(t.font(13))
                }
            }
        }
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func inline(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
    }

    enum Kind { case heading, bullet(String), row, paragraph }
    struct Block { let kind: Kind; let text: String }

    var blocks: [Block] {
        var out: [Block] = []
        var para: [String] = []
        func flush() { if !para.isEmpty { out.append(Block(kind: .paragraph, text: para.joined(separator: " "))); para = [] } }
        for raw in text.components(separatedBy: .newlines) {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { flush(); continue }
            if l.hasPrefix("|") {
                flush()
                let cells = l.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { continue }
                out.append(Block(kind: .row, text: cells.joined(separator: " · ")))
            } else if l.hasPrefix("#") {
                flush(); out.append(Block(kind: .heading, text: l.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("• ") {
                flush(); out.append(Block(kind: .bullet("•"), text: String(l.dropFirst(2))))
            } else if let dot = l.firstIndex(of: "."), l[..<dot].allSatisfy(\.isNumber), !l[..<dot].isEmpty, l[l.index(after: dot)...].hasPrefix(" ") {
                flush(); out.append(Block(kind: .bullet(String(l[...dot])), text: String(l[l.index(dot, offsetBy: 2)...])))
            } else {
                para.append(l)
            }
        }
        flush()
        return out
    }
}
#endif
