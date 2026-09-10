import SwiftUI
import RillUI

/// A refined chat surface that renders each assistant turn with Rill and streams
/// the answer in token-by-token, exactly as an LLM client would.
public struct ChatView: View {
    let convo: Conversation
    @State private var source = MarkdownSource()
    @State private var streaming = true
    @State private var caretOn = true
    @State private var tick = 0

    public init(_ convo: Conversation) { self.convo = convo }

    private var p: Palette { convo.palette }
    private var theme: RillTheme { .chat(convo.palette, rounded: convo.rounded) }
    private var config: RenderConfig { RenderConfig(appendAnimation: .word, appendAnimationDuration: 0.18) }
    private var uiFont: Font.Design { convo.rounded ? .rounded : .default }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(p.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        userBubble
                        assistantRow
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: tick) { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            inputBar
        }
        .background(p.bg.ignoresSafeArea())
        .environment(\.colorScheme, p.scheme)
        .task { await play() }
        .task { await blink() }
    }

    // MARK: chrome

    private var header: some View {
        HStack(spacing: 11) {
            RillAvatar(p)
            VStack(alignment: .leading, spacing: 2) {
                Text(convo.title).font(.system(.subheadline, design: uiFont).weight(.semibold)).foregroundStyle(p.ink)
                Text(convo.subtitle).font(.system(size: 11)).foregroundStyle(p.ink2)
            }
            Spacer()
            statusPill
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            if streaming {
                Circle().fill(c(0.24, 0.82, 0.55)).frame(width: 7, height: 7)
                Text("streaming").font(.system(size: 11, weight: .medium)).foregroundStyle(p.ink2)
            } else {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(p.ink2)
                Text("done").font(.system(size: 11, weight: .medium)).foregroundStyle(p.ink2)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(p.surface).overlay(Capsule().stroke(p.border, lineWidth: 1)))
    }

    private var userBubble: some View {
        HStack { Spacer(minLength: 44)
            Text(convo.prompt).font(.system(.callout, design: uiFont)).foregroundStyle(p.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.userSurface)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(p.accent.opacity(p.scheme == .dark ? 0.22 : 0.14), lineWidth: 1)))
        }
    }

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 11) {
            RillAvatar(p)
            VStack(alignment: .leading, spacing: 5) {
                StreamingMarkdownView(source, theme: theme, config: config)
                if streaming {
                    RoundedRectangle(cornerRadius: 1.5).fill(p.accent)
                        .frame(width: 2.5, height: 18).opacity(caretOn ? 1 : 0.15)
                }
            }
            .padding(15)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(p.surface)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(p.border, lineWidth: 1)))
            Spacer(minLength: 8)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack { Text("Message").font(.callout).foregroundStyle(p.ink2); Spacer() }
                .padding(.horizontal, 15).padding(.vertical, 11)
                .background(Capsule().fill(p.surface).overlay(Capsule().stroke(p.border, lineWidth: 1)))
            ZStack {
                Circle().fill(p.accent).frame(width: 38, height: 38)
                Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(p.scheme == .dark ? c(0.04, 0.06, 0.09) : .white)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: streaming driver

    private func play() async {
        try? await Task.sleep(nanoseconds: 650_000_000)
        for token in Self.tokenize(convo.answer) {
            source.append(token)
            tick &+= 1
            let ws = token.first?.isWhitespace ?? false
            try? await Task.sleep(nanoseconds: ws ? 16_000_000 : 52_000_000)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.easeInOut(duration: 0.25)) { streaming = false }
    }

    private func blink() async {
        while streaming {
            try? await Task.sleep(nanoseconds: 480_000_000)
            withAnimation(.easeInOut(duration: 0.18)) { caretOn.toggle() }
        }
    }

    /// Splits text into alternating word / whitespace runs so streaming looks
    /// like real token arrival (whole words fade in, structure appears as typed).
    static func tokenize(_ s: String) -> [String] {
        var out: [String] = []; var cur = ""; var curWS: Bool? = nil
        for ch in s {
            let ws = ch.isWhitespace
            if curWS == nil { curWS = ws; cur.append(ch) }
            else if ws == curWS { cur.append(ch) }
            else { out.append(cur); cur = String(ch); curWS = ws }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}
