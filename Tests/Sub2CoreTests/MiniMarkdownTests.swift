import Foundation
import Testing
@testable import Sub2Core

// MARK: 60 §16.3 / §16.7 块级

@Test func miniMarkdownBlocksSplitHeadingsListsAndParagraphs() {
    let billing = "## 计费口径\n\n- 实际扣费 = 标准价 × 分组倍率\n- 缓存读取按官方折扣计费"
    #expect(MiniMarkdown.blocks(billing) == [.heading("计费口径"), .list(["实际扣费 = 标准价 × 分组倍率", "缓存读取按官方折扣计费"])])
    let maintenance = "**维护时间**：10 月 18 日 02:00–04:00（北京时间）\n\n维护期间：\n- API 请求可能短暂返回 502，请在客户端开启重试\n"
        + "- 控制台暂停充值与兑换\n\n如有问题，请在[工单中心](https://example.com/ticket)联系我们。"
    #expect(MiniMarkdown.blocks(maintenance) == [
        .paragraph("**维护时间**：10 月 18 日 02:00–04:00（北京时间）"), .paragraph("维护期间："),
        .list(["API 请求可能短暂返回 502，请在客户端开启重试", "控制台暂停充值与兑换"]),
        .paragraph("如有问题，请在[工单中心](https://example.com/ticket)联系我们。")
    ])
    #expect(MiniMarkdown.blocks("# 一级\n### 三级") == [.heading("一级"), .heading("三级")])
    #expect(MiniMarkdown.blocks("- 一\n二") == [.list(["一"]), .paragraph("二")])
    #expect(MiniMarkdown.blocks("说明\n## 小标题\n正文") == [.paragraph("说明"), .heading("小标题"), .paragraph("正文")])
}

@Test func miniMarkdownParagraphKeepsLineBreaksAndEdgeCases() {
    #expect(MiniMarkdown.blocks("第一行\n第二行") == [.paragraph("第一行\n第二行")])
    #expect(MiniMarkdown.blocks("一段\n\n\n二段") == [.paragraph("一段"), .paragraph("二段")])
    #expect(MiniMarkdown.blocks("-x\n#标题\n#### 四级") == [.paragraph("-x\n#标题\n#### 四级")])
    #expect(MiniMarkdown.blocks("a\r\nb\r\n\r\nc") == MiniMarkdown.blocks("a\nb\n\nc"))
    #expect(MiniMarkdown.blocks("a\r\nb\r\n\r\nc") == [.paragraph("a\nb"), .paragraph("c")])
    #expect(MiniMarkdown.blocks("").isEmpty)
    #expect(MiniMarkdown.blocks("  \n\t\n ").isEmpty)
    #expect(MiniMarkdown.blocks("## \n正文") == [.paragraph("正文")])
}

@Test func miniMarkdownAllowsOnlyWebLinks() throws {
    #expect(MiniMarkdown.isAllowedLink(try #require(URL(string: "https://example.com/ticket"))))
    #expect(MiniMarkdown.isAllowedLink(try #require(URL(string: "HTTP://example.com"))))
    for raw in ["javascript:alert(1)", "/etc/hosts", "mailto:a@example.com", "/relative/path", "tel:10086"] {
        #expect(!MiniMarkdown.isAllowedLink(try #require(URL(string: raw))), "\(raw)")
    }
}

// MARK: 行内（AttributedString(markdown:) 只在 Apple 平台有，S6D1-14）

#if canImport(Darwin)
private func run(_ text: AttributedString, containing part: String) -> AttributedString.Runs.Run? {
    text.runs.first { String(text[$0.range].characters).contains(part) }
}

@Test func miniMarkdownInlineKeepsBoldAndWebLinks() throws {
    let bold = MiniMarkdown.inline("**维护时间**：10 月")
    #expect(String(bold.characters) == "维护时间：10 月")
    #expect(try #require(run(bold, containing: "维护时间")).inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
    let amount = MiniMarkdown.inline("你的余额已低于 **$5.00**。")
    #expect(try #require(run(amount, containing: "$5.00")).inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
    let link = MiniMarkdown.inline("请在[工单中心](https://example.com/ticket)联系我们。")
    #expect(String(link.characters) == "请在工单中心联系我们。")
    #expect(try #require(run(link, containing: "工单中心")).link == URL(string: "https://example.com/ticket"))
    let plain = MiniMarkdown.inline("[官网](http://example.com)")
    #expect(try #require(run(plain, containing: "官网")).link == URL(string: "http://example.com"))
    #expect(String(MiniMarkdown.inline("第一行\n第二行").characters) == "第一行\n第二行")
}

@Test func miniMarkdownInlineStripsUnsafeLinksAndKeepsText() {
    for raw in ["[x](javascript:alert(1))", "[f](/etc/hosts)", "[m](mailto:a@example.com)", "[r](/admin)"] {
        let parsed = MiniMarkdown.inline(raw)
        #expect(parsed.runs.allSatisfy { $0.link == nil }, "\(raw)")
        #expect(String(parsed.characters).count == 1, "\(raw)")
    }
    #expect(String(MiniMarkdown.inline("**未闭合").characters) == "**未闭合")
    #expect(String(MiniMarkdown.inline("[半个链接").characters) == "[半个链接")
    let html = MiniMarkdown.inline("<b>x</b>")
    #expect(html.runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) != true })
    #expect(String(html.characters).contains("x"))
}
#endif
