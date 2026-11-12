import Markdown
import SwiftUI

/// swift-markdown has its own `Text`, `Image`, `Link` and `Table`: SwiftUI's `Text` here, the others by module.
private typealias Text = SwiftUI::Text

struct Markdown: View {
    let text: String

    var body: some View {
        Blocks(container: Document(parsing: text))
            .font(.system(size: 14))
            // 14 pt text on 20 pt lines (1.43, between Messages' 1.23 and a web page's 1.5); 14 pt's own line is 17 pt.
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .readableText(text)
    }
}

private struct Blocks: View {
    let container: any Markup

    var body: some View {
        let blocks = Array(container.children)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { index in
                let space = index == 0 ? 0 : Self.space(blocks[index - 1], blocks[index])
                Block(markup: blocks[index]).padding(.top, space)
            }
        }
    }

    private static func space(_ above: any Markup, _ block: any Markup) -> CGFloat {
        if let heading = block as? Heading {
            heading.level < 3 ? 26 : 17
        } else if above is Heading {
            8
        } else if block.parent is ListItem {
            block is ListItemContainer ? 0 : 6
        } else {
            17
        }
    }
}

private struct Block: View {
    let markup: any Markup

    var body: some View {
        switch markup {
        case let heading as Heading:
            let size: CGFloat = [22, 18, 16][min(max(heading.level, 1), 3) - 1]
            let weight: Font.Weight = heading.level < 3 ? .bold : .semibold
            LinkedText(text: Inline.text(heading, size: size)).font(.system(size: size, weight: weight))
        case let paragraph as Paragraph:
            LinkedText(text: Inline.text(paragraph, size: 14))
        case let code as CodeBlock:
            ScrollView(.horizontal) {
                // A code block's last newline is no line of its own.
                LinkedText(text: ChatLinks.linked(code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code))
                    .font(.system(size: 12.5, design: .monospaced)).lineSpacing(2).fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .scrollIndicators(.never)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 8))
        case is BlockQuote:
            Blocks(container: markup).foregroundStyle(.secondary).padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(.tertiary).frame(width: 3) }
        case let list as ListItemContainer:
            ListBlock(list: list)
        case let table as Markdown::Table:
            TableGrid(table: table)
        case is ThematicBreak:
            Divider().padding(.vertical, 4)
        case let html as HTMLBlock:
            Text(html.rawHTML.trimmingCharacters(in: .newlines)).font(.system(size: 12.5, design: .monospaced))
        default:
            Text(markup.format())
        }
    }
}

private struct ListBlock: View {
    let list: any ListItemContainer

    var body: some View {
        let items = Array(list.listItems)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    marker(items[index], index).foregroundStyle(.secondary).frame(minWidth: 12, alignment: .trailing)
                    Blocks(container: items[index])
                }
            }
        }
    }

    @ViewBuilder private func marker(_ item: ListItem, _ index: Int) -> some View {
        if let checkbox = item.checkbox {
            SwiftUI::Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
        } else if let ordered = list as? OrderedList {
            Text("\(Int(ordered.startIndex) + index).")
        } else {
            Text(["•", "◦", "▪"][depth % 3])
        }
    }

    private var depth: Int {
        sequence(first: list.parent) { $0?.parent }.prefix { $0 != nil }.count { $0 is ListItemContainer }
    }
}

private struct TableGrid: View {
    let table: Markdown::Table

    var body: some View {
        let rows = [Array(table.head.cells)] + table.body.rows.map { Array($0.cells) }
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(rows.indices, id: \.self) { row in
                if row > 0 {
                    Divider()
                }
                GridRow {
                    ForEach(rows[row].indices, id: \.self) { column in
                        let alignment = alignment(column)
                        LinkedText(text: Inline.text(rows[row][column], size: 14))
                            .fontWeight(row == 0 ? .semibold : nil)
                            .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: Alignment(horizontal: alignment, vertical: .center))
                            .background(row == 0 ? AnyShapeStyle(.primary.opacity(0.05)) : AnyShapeStyle(.clear))
                            .gridColumnAlignment(alignment)
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }

    private func alignment(_ column: Int) -> HorizontalAlignment {
        switch column < table.columnAlignments.count ? table.columnAlignments[column] : nil {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
    }
}

private enum Inline {
    static func text(_ markup: any Markup, size: CGFloat) -> AttributedString {
        markup.children.reduce(into: AttributedString()) { result, child in
            switch child {
            case let text as Markdown::Text: result += ChatLinks.linked(text.string)
            case let code as InlineCode:
                // A monospaced face reads larger.
                var code = ChatLinks.linked(code.code)
                code.font = .system(size: size * 0.9, design: .monospaced)
                code.backgroundColor = .primary.opacity(0.08)
                result += code
            case is Emphasis: result += styled(child, size, .emphasized)
            case is Strong: result += styled(child, size, .stronglyEmphasized)
            case is Strikethrough: result += styled(child, size, .strikethrough)
            case let link as Markdown::Link:
                var label = Self.text(link, size: size)
                if let url = ChatLinks.markdown(link.destination) {
                    label.link = url
                }
                result += label
            case let image as Markdown::Image:
                // Its description, a link to it: loaded on its own, a reply could send what the agent read to any
                // server.
                var label = Self.text(image, size: size)
                if let url = ChatLinks.markdown(image.source) {
                    label.link = url
                }
                result += label
            default: result += AttributedString((child as? InlineMarkup)?.plainText ?? "")
            }
        }
    }

    private static func styled(_ markup: any Markup, _ size: CGFloat,
                               _ intent: InlinePresentationIntent) -> AttributedString
    {
        var text = text(markup, size: size)
        for run in text.runs {
            text[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(intent)
        }
        return text
    }
}
