import AlmanacCore
import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var role: String   // "user" | "assistant" | "error"
    var text: String
}

/// Ask about whatever is on screen. Each screen publishes its data to `model.chatContext`.
struct ChatPanel: View {
    @Environment(AppModel.self) private var model
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat").font(.headline)
                Spacer()
                Text(AISettings.provider.title).font(.caption).foregroundStyle(.secondary)
                Button { messages = [] } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.borderless).help("New chat").disabled(messages.isEmpty)
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty { suggestions }
                        ForEach(messages) { bubble($0).id($0.id) }
                        if busy { ProgressView().controlSize(.small).id("busy") }
                    }
                    .padding(12)
                }
                .onChange(of: messages) { withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) } }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about this screen…", text: $input, axis: .vertical)
                    .lineLimit(1...5).textFieldStyle(.plain)
                    .onSubmit { send(input) }
                Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .buttonStyle(.borderless).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            .padding(12)
        }
        .onAppear(perform: consumeSeed)
        .onChange(of: model.chatSeed) { consumeSeed() }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask about the chart, table or report you're looking at. The answer comes from your own \(AISettings.provider.title) subscription; your data goes straight from this Mac to it.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(["Explain this to me", "What changed recently, and why?", "What should I do next?"], id: \.self) { q in
                Button(q) { send(q) }.linkButtonStyle()
            }
        }
    }

    @ViewBuilder private func bubble(_ m: ChatMessage) -> some View {
        switch m.role {
        case "user":
            Text(m.text).padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case "error":
            Label(m.text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
        default:
            Text((try? AttributedString(markdown: m.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(m.text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu { Button("Copy") { copy(m.text) } }
        }
    }

    private func copy(_ s: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        #else
        UIPasteboard.general.string = s
        #endif
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
        let context = "App: \(model.app?.name ?? "")\nToday: \(Day.today())\n\(model.chatContext)"
        Task {
            do { messages.append(ChatMessage(role: "assistant", text: try await AISettings.assistant.ask(q, context: context, history: history))) }
            catch { messages.append(ChatMessage(role: "error", text: error.localizedDescription)) }
            busy = false
        }
    }
}
