import HerdrKit
import SwiftUI

/// Its own view, so that a key typed in the reply box or a card resized does not build the rows again.
struct ChatMessages: View, Equatable {
    let chat: Chat
    let page: Page
    let floats: Bool
    var composing: FocusState<Bool>.Binding
    @State private var tops = Tops()
    @State private var atBottom = true
    @State private var away = false
    @State private var width: CGFloat?
    @State private var settling: Task<Void, Never>?
    @State private var first: String?
    @State private var earlier = false
    /// The rows come on the turn after the view is made, so that a switch to a tab whose chat is made draws the window,
    /// the tab and the card in the click's own turn (the rows take 124 ms of a long chat).
    @State private var drawn = false
    /// Only asked, never told: a place the scroll view names as a scroll begins or ends, given back to it, snaps that
    /// row to the top.
    @State private var position = ScrollPosition(idType: String.self)
    /// A greeting and the reply box's placeholder that goes with it.
    @State private var phrase = Self.phrases.randomElement() ?? Self.phrases[0]
    /// Not observed: a body run rebuilds the rows, and the height changes at each frame of a resize.
    @State private var height = Height()
    @State private var viewHeight = ViewHeight()
    @Environment(\.look) private var look
    private static let phrases: [(greeting: String, placeholder: String)] = [
        ("What's on your mind?", "Ask or tell me anything"), ("What are we building?", "Describe the feature"),
        ("Where should we start?", "Name a file, a bug or a goal"),
        ("What can I help with?", "Ask a question or give a task"), ("Ready when you are.", "Type your first message"),
    ]
    private static let end = "end"
    nonisolated static let space = "chat.messages"
    /// About two views of text, at most `block` rows. Each time the card is made it lays them out: 31 rows of long
    /// replies, 383 Markdown blocks, took 394 ms of main thread, and 120 lines (5 rows) 124 ms, against 34 ms for a
    /// terminal tab. A split lays them out once, at its end: 40 rows of long replies took one frame of 40–50 ms, 100
    /// rows one of 110–160 ms.
    private static let block = 34
    private static let budget = 120

    /// The focus binding stays the same for a card. The rows are worked out in the body (3–4 ms for a 3,900-entry
    /// history).
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chat === rhs.chat && lhs.page === rhs.page && lhs.floats == rhs.floats
    }

    var body: some View {
        // A chat that may have a history shows a loader until it is read, unless a message is on its way; a new one,
        // the header and the reply box in the middle until the first message.
        let reading = !chat.current && chat.problem == nil && chat.outgoing.isEmpty
        let welcome = !reading && chat.history.entries.isEmpty && chat.outgoing.isEmpty && chat.problem == nil
        return Group {
            // No scroll view until there is something to show: one made empty keeps the top inset that held its empty
            // content at the bottom after a long history loads, a blank above the messages.
            if !drawn {
                Color.clear.task { withAnimation(.fade) { drawn = true } }
            } else if reading || welcome {
                empty(loading: reading)
            } else {
                // Also while the transcript a sent message starts loads (Claude Code and pi write it with the first
                // message): a spinner in its place took the message away right after it rose.
                messages.transition(.opacity)
            }
        }
        // The rows fade in as they first show, in a card just made or once its history is read.
        .animation(.fade, value: reading)
        // The first message rises from the reply box as the box goes down. Not a transition: an offset transition
        // moves nothing here, only its fade runs.
        .keyframeAnimator(initialValue: 0.0, trigger: Animation.reduced ? false : welcome) { content, rise in
            content.offset(y: rise)
        } keyframes: { _ in
            // From the middle, where the box was.
            MoveKeyframe(welcome ? 0 : max(0, height.value / 2 - topPadding))
            LinearKeyframe(0, duration: 0.22, timingCurve: .slide)
        }
        // Here, not on ChatView: its body runs at each resize frame, and a new action redraws every link.
        .environment(\.openURL, OpenURLAction(handler: openLink))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !chat.drawer {
                VStack(spacing: 8) {
                    if welcome {
                        header.padding(.bottom, 14).transition(.opacity)
                    }
                    if let question = chat.question, chat.phase == .waiting {
                        QuestionCard(question: question, paneID: chat.paneID) { chat.answer($0) }
                            .disabled(question.answered)
                            .id(question.raw)
                    }
                    Composer(chat: chat, composing: composing, placeholder: welcome ? phrase.placeholder : nil)
                        .alignmentGuide(.replyBox) { $0[VerticalAlignment.center] }
                }
                // The box's text on the messages' edges: the box reaches past them by its own padding.
                .padding(.bottom, 14).padding(.top, 4).readingColumn(margin: 32 - Composer.inset)
                // The empty chat's middle is the box's, its header above it.
                .frame(maxHeight: welcome ? .infinity : nil, alignment: .init(horizontal: .center, vertical: .replyBox))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height.value = $0 }
        .animation(.slide, value: welcome)
        .fadeEdges(.vertical, start: 12, end: 0)
    }

    private var header: some View {
        VStack(spacing: 14) {
            if let pane = page.store.pane(chat.paneID) {
                ProgramGlyph(icon: pane.iconID, letter: pane.letter, size: 64).opacity(0.5)
            }
            Text(phrase.greeting).font(.system(size: 26, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .readableText(phrase.greeting)
        .accessibilityIdentifier("chat.\(chat.paneID).empty")
    }

    private func empty(loading: Bool) -> some View {
        Color.clear.overlay {
            if loading {
                Loader(id: "chat.\(chat.paneID).loading", delay: .milliseconds(300))
            }
        }
        .onAppear {
            (tops, atBottom, away, first, earlier) = (Tops(), true, false, nil, false)
            position = ScrollPosition(idType: String.self)
        }
    }

    private var messages: some View {
        let rows = chat.history.rows()
        let kept = first.flatMap { id in rows.firstIndex { $0.id == id } }
        let start = kept ?? Self.start(rows[...])
        // ponytail: once pinned, a chat open for hours lays out every row since; cut it again at the exact bottom if a
        // split's layout gets slow.
        let pin = kept == nil && rows.indices.contains(start) && away
        // Read here: a change of the view's state or environment read inside the reader's content does not build it
        // again, only a change of what its closure holds. The chat's observed values are tracked inside.
        let (scrolledUp, loading, laidOut, error, place) = (!atBottom, earlier, width, look.error, position)
        return ScrollViewReader { proxy in
            ScrollView {
                // As tall as the view at least, its rows at the top: a short chat is then at its exact bottom, and the
                // bottom anchor follows it as its rows pass the view. A shorter stack, held at the top by the `.top`
                // alignment, kept its top.
                ZStack(alignment: .top) {
                    Filler(height: viewHeight)
                    // Not lazy: a lazy stack guesses the height of the rows it has not built, by up to four times,
                    // and after a split shows a blank where it guesses wrong. `start` keeps the layout short.
                    VStack(alignment: .leading, spacing: 10) {
                        if start > 0 {
                            earlierButton(loading: loading) { showEarlier(rows, before: start) }
                        }
                        Rows(chat: chat, rows: rows[start...], tops: tops) { position.scrollTo(y: $0) }
                        ForEach(chat.outgoing) { message in
                            outgoing(message, error: error)
                        }
                        if chat.phase == .working {
                            // Not the last turn's, interrupted, while the next message is on its way.
                            WorkingRow(since: chat.outgoing.isEmpty ? chat.history.turnStart : nil)
                        }
                        if let problem = chat.problem {
                            problemCard(problem, error: error)
                        }
                        Color.clear.frame(height: 22).id(Self.end)
                    }
                    .padding(.top, start > 0 ? 0 : topPadding).readingColumn()
                    .coordinateSpace(.named(Self.space))
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { viewHeight.value = $1 }
            .scrollPosition(.constant(place))
            .task(id: pin) {
                if pin {
                    first = rows[start].id
                }
            }
            // At the exact bottom the chat stays there as rows come and the card resizes; scrolled up, even by a
            // point, it keeps its offset.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            // A short chat reads from the top, where its first message went.
            .defaultScrollAnchor(.top, for: .alignment)
            // At a new width or Show Earlier this runs ahead of the rows' new places. x: how far the bottom is out of
            // view; at 0 the anchor holds the bottom instead.
            .onScrollGeometryChange(for: CGRect.self) { geometry in
                CGRect(x: geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY,
                       y: geometry.contentOffset.y, width: 0, height: geometry.contentSize.height)
            } action: { old, new in
                // The rows' new height can move the offset in the same update (a wider card's shorter content, clamped
                // at the end): the place is the one ahead of that update.
                let place = old.height == new.height ? new : old
                tops.hold(at: place.minY, bottom: place.minX <= 0.5)
                // Only a scroll moves it: during a load an update can report the grown rows ahead of the anchor.
                if old.height == new.height, away != (new.minX > 0.5) {
                    away = new.minX > 0.5
                }
                if old.height != new.height, earlier {
                    earlier = false
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY < 40
            } action: {
                atBottom = $1
            }
            .focusEffectDisabled()
            .accessibilityIdentifier("chat.\(chat.paneID)")
            // A lone new width (a split's motion gives the card its final size once) wraps the rows at once, with the
            // reply box; one in a run of them (a drag) waits for the run's end, so the rows wrap once, not at every
            // frame. At once while the reading column keeps its width.
            .frame(width: laidOut)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                let run = settling != nil
                guard run, let old = width, min(old, new) < ChatView.column + 64 else {
                    width = new
                    SettlingHost.settle(&settling) { settling = nil }
                    return
                }
                SettlingHost.settle(&settling) {
                    width = new
                    settling = nil
                }
            }
            // After the messages' id, which would replace its own.
            .overlay(alignment: .bottom) {
                if scrolledUp {
                    bottomButton { proxy.scrollTo(Self.end, anchor: .bottom) }
                }
            }
        }
    }

    private static func start(_ rows: ArraySlice<ChatRow>) -> Int {
        var first = rows.endIndex, total = 0
        while first > rows.startIndex, rows.endIndex - first < block, total < budget {
            first -= 1
            total += lines(rows[first])
        }
        return first
    }

    /// ponytail: long code lines (they do not wrap) and blank lines count too many, so a block of long logs, or a very
    /// tall card, can show the block's top with room above it; take the budget from the scroll view's height if so.
    private static func lines(_ row: ChatRow) -> Int {
        switch row {
        case let .user(_, text), let .reply(_, text):
            1 + text.utf8.count / 90 + text.utf8.count { $0 == UInt8(ascii: "\n") }
        case let .todos(_, todos): todos.count + 1
        default: 2
        }
    }

    private func bottomButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.down").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 30)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .help("Scroll to Bottom")
        .accessibilityLabel("Scroll to Bottom")
        .accessibilityIdentifier("chat.\(chat.paneID).bottom")
        .padding(.bottom, 10)
    }

    /// The spinner draws first: the run loop turn after its commit lays the rows out, which holds the main thread.
    private func showEarlier(_ rows: [ChatRow], before start: Int) {
        guard !earlier else { return }
        earlier = true
        let id = rows[Self.start(rows[..<start])].id
        // After this turn's commit, at `beforeWaiting` only: a click's tracking loop can exit ahead of the commit.
        // The wake-up runs the next turn without waiting for an event.
        let activity = CFRunLoopActivity.beforeWaiting.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, activity, false, Int.max) { _, _ in
            MainActor.assumeIsolated { first = id }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private func earlierButton(loading: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Show Earlier").opacity(loading ? 0 : 1)
                .overlay {
                    if loading {
                        ProgressView().controlSize(.small)
                    }
                }
                .font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(height: 28)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show Earlier")
        .accessibilityValue(loading ? "loading" : "")
        .accessibilityIdentifier("chat.\(chat.paneID).earlier")
        .frame(maxWidth: .infinity)
        .padding(.top, topPadding)
    }

    private var topPadding: CGFloat {
        floats ? 28 : 16
    }
}

private extension ChatMessages {
    func outgoing(_ message: Chat.Outgoing, error: Color) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Dimmed until the agent takes it.
            UserBubble(text: message.text, paneID: chat.paneID, sending: true)
                .opacity(message.notSent ? 0.5 : Chat.Outgoing.dimmed)
            if message.notSent {
                Text("Not sent").font(.system(size: 11)).foregroundStyle(error)
                    .accessibilityIdentifier("chat.\(chat.paneID).not-sent")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 8)
    }

    func problemCard(_ problem: String, error: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("The chat cannot read this session", systemImage: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(error)
            Text(problem).font(.system(size: 12)).foregroundStyle(.secondary)
                .accessibilityIdentifier("chat.\(chat.paneID).problem")
            Button("Show TUI") { chat.showsChat = false }.buttonStyle(.glass).controlSize(.small)
                .accessibilityIdentifier("chat.\(chat.paneID).show-terminal")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(error.opacity(0.1), in: .rect(cornerRadius: 10))
    }
}

private extension VerticalAlignment {
    enum ReplyBox: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    /// A custom guide, as a stack passes on only those: `center` is the stack's own.
    static let replyBox = VerticalAlignment(ReplyBox.self)
}

@MainActor
private final class Height {
    var value: CGFloat = 0
}

/// Observed by `Filler` alone: a resize lays out the stack again, and builds no rows.
@MainActor @Observable
private final class ViewHeight {
    var value: CGFloat = 0
}

private struct Filler: View {
    let height: ViewHeight

    var body: some View {
        Color.clear.frame(height: height.value)
    }
}
