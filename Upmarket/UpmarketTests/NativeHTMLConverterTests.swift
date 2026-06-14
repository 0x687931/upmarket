import XCTest
@testable import Upmarket

/// Exercises the in-process HTML→Markdown walker. These guard the native path that lets
/// HTML convert in the Basic tier without the Enhanced runtime download.
final class NativeHTMLConverterTests: XCTestCase {

    private func md(_ html: String) throws -> String {
        try NativeHTMLConverter.convert(html: html).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testHeadings() throws {
        XCTAssertEqual(try md("<h1>Title</h1><h2>Sub</h2>"), "# Title\n\n## Sub")
        XCTAssertEqual(try md("<h3>Deep</h3>"), "### Deep")
    }

    func testParagraphsCollapseWhitespace() throws {
        let html = "<p>Hello   \n   world</p><p>Second</p>"
        XCTAssertEqual(try md(html), "Hello world\n\nSecond")
    }

    func testInlineEmphasis() throws {
        XCTAssertEqual(try md("<p>a <strong>bold</strong> and <em>italic</em></p>"),
                       "a **bold** and *italic*")
        XCTAssertEqual(try md("<p>use <code>print()</code></p>"), "use `print()`")
        XCTAssertEqual(try md("<p><del>gone</del></p>"), "~~gone~~")
    }

    func testLinksAndImages() throws {
        XCTAssertEqual(try md("<p><a href=\"https://x.com\">site</a></p>"),
                       "[site](https://x.com)")
        XCTAssertEqual(try md("<p><img src=\"a.png\" alt=\"cat\"></p>"),
                       "![cat](a.png)")
        // Anchor without href degrades to plain text.
        XCTAssertEqual(try md("<p><a>no href</a></p>"), "no href")
    }

    func testUnorderedAndOrderedLists() throws {
        XCTAssertEqual(try md("<ul><li>one</li><li>two</li></ul>"), "- one\n- two")
        XCTAssertEqual(try md("<ol><li>first</li><li>second</li></ol>"), "1. first\n2. second")
    }

    func testNestedList() throws {
        let html = "<ul><li>a<ul><li>a1</li></ul></li><li>b</li></ul>"
        XCTAssertEqual(try md(html), "- a\n  - a1\n- b")
    }

    func testBlockquote() throws {
        XCTAssertEqual(try md("<blockquote><p>quoted</p></blockquote>"), "> quoted")
    }

    func testPreservesCodeBlock() throws {
        let html = "<pre>let x = 1\nlet y = 2</pre>"
        XCTAssertEqual(try md(html), "```\nlet x = 1\nlet y = 2\n```")
    }

    func testHorizontalRule() throws {
        XCTAssertEqual(try md("<p>a</p><hr><p>b</p>"), "a\n\n---\n\nb")
    }

    func testHardBreak() throws {
        XCTAssertEqual(try md("<p>line one<br>line two</p>"), "line one  \nline two")
    }

    func testTable() throws {
        let html = "<table><thead><tr><th>H1</th><th>H2</th></tr></thead>" +
                   "<tbody><tr><td>a</td><td>b</td></tr></tbody></table>"
        XCTAssertEqual(try md(html), "| H1 | H2 |\n| --- | --- |\n| a | b |")
    }

    func testTableWithoutThead() throws {
        let html = "<table><tr><td>x</td><td>y</td></tr><tr><td>1</td><td>2</td></tr></table>"
        XCTAssertEqual(try md(html), "| x | y |\n| --- | --- |\n| 1 | 2 |")
    }

    func testDropsScriptAndStyle() throws {
        let html = "<style>p{color:red}</style><p>visible</p><script>alert(1)</script>"
        XCTAssertEqual(try md(html), "visible")
    }

    func testDecodesEntities() throws {
        XCTAssertEqual(try md("<p>a &amp; b &lt; c &gt; d &mdash; e</p>"),
                       "a & b < c > d — e")
    }

    /// Hard guarantee: the converter must never drop a character. `XMLDocument`'s tidy
    /// parser silently discards all non-ASCII unless we pin encoding and pre-escape, so this
    /// sweeps the whole range — supplementary plane, combining marks, RTL, ZWJ sequences,
    /// and non-ASCII inside attributes — to keep that workaround honest.
    func testNeverDropsNonASCIIAcrossUnicodeRange() throws {
        let payloads = [
            "😀",            // emoji, supplementary plane U+1F600
            "𠀀",            // supplementary-plane CJK U+20000
            "中文テスト한국어",  // BMP CJK / Japanese / Korean
            "café",          // precomposed accent
            "e\u{0301}",     // combining acute accent
            "مرحبا שלום",    // RTL Arabic + Hebrew
            "👩‍👩‍👧",          // ZWJ emoji sequence
            "—…©°½€",         // punctuation / symbols / currency
        ]
        for payload in payloads {
            XCTAssertEqual(try md("<p>\(payload)</p>"), payload,
                "Body text dropped or altered non-ASCII: \(payload)")
        }
        // Non-ASCII inside attributes (alt text, URLs) must survive too.
        XCTAssertEqual(try md("<p><img src=\"日本.png\" alt=\"café 😀\"></p>"),
                       "![café 😀](日本.png)")
        XCTAssertEqual(try md("<p><a href=\"https://x.com/café?q=日本\">链接</a></p>"),
                       "[链接](https://x.com/café?q=日本)")
    }

    func testPreservesNonASCIIAndNamedEntities() throws {
        // Encoding must be pinned to UTF-8: literal accents, named entities, and the
        // short HTML5 charset meta all survive without mojibake or dropped characters.
        XCTAssertEqual(try md("<p>café &copy; 2026 &mdash; 50&deg;</p>"),
                       "café © 2026 — 50°")
        let withCharsetMeta = "<html><head><meta charset=\"utf-8\"></head><body><p>déjà&nbsp;vu</p></body></html>"
        XCTAssertEqual(try md(withCharsetMeta), "déjà\u{00A0}vu")
    }

    func testRecoversFromMalformedHTML() throws {
        // Unclosed tags — libxml2 tidy must recover rather than throw.
        let html = "<p>open<b>bold<p>next"
        let out = try md(html)
        XCTAssertTrue(out.contains("open"))
        XCTAssertTrue(out.contains("next"))
    }

    func testFullDocumentSkipsHeadKeepsBody() throws {
        let html = "<html><head><title>T</title></head><body><h1>Doc</h1><p>Body</p></body></html>"
        XCTAssertEqual(try md(html), "# Doc\n\nBody")
    }

    func testEmptyInputProducesEmptyOutput() throws {
        XCTAssertEqual(try md(""), "")
        XCTAssertEqual(try md("<html><body></body></html>"), "")
    }

    // MARK: - Markdown escaping (literal text must not be reparsed as Markdown)

    func testEscapesInlineMarkdownChars() throws {
        XCTAssertEqual(try md("<p>literal *stars* and _unders_ here</p>"),
                       "literal \\*stars\\* and \\_unders\\_ here")
        XCTAssertEqual(try md("<p>see a[b]c and back\\slash</p>"),
                       "see a\\[b\\]c and back\\\\slash")
        // Backticks in flow text are escaped, but real <code> stays verbatim.
        XCTAssertEqual(try md("<p>tick ` here</p>"), "tick \\` here")
        XCTAssertEqual(try md("<p>call <code>a*b_c</code> now</p>"), "call `a*b_c` now")
    }

    func testEscapesLeadingBlockMarkers() throws {
        XCTAssertEqual(try md("<p># not a heading</p>"), "\\# not a heading")
        XCTAssertEqual(try md("<p>- not a list</p>"), "\\- not a list")
        XCTAssertEqual(try md("<p>1. not a list</p>"), "1\\. not a list")
        XCTAssertEqual(try md("<p>&gt; not a quote</p>"), "\\> not a quote")
        // A marker mid-text must NOT be escaped (no false positives).
        XCTAssertEqual(try md("<p>id - name</p>"), "id - name")
    }

    // MARK: - Structure the walker previously dropped

    func testDefinitionList() throws {
        let html = "<dl><dt>Term</dt><dd>Definition</dd><dt>T2</dt><dd>D2</dd></dl>"
        XCTAssertEqual(try md(html), "**Term**\nDefinition\n**T2**\nD2")
    }

    func testOrderedListStartAttribute() throws {
        XCTAssertEqual(try md("<ol start=\"5\"><li>five</li><li>six</li></ol>"),
                       "5. five\n6. six")
    }

    func testTaskListCheckboxes() throws {
        let html = "<ul><li><input type=\"checkbox\" checked>done</li>" +
                   "<li><input type=\"checkbox\">todo</li></ul>"
        XCTAssertEqual(try md(html), "- [x] done\n- [ ] todo")
    }

    func testTableCaption() throws {
        let html = "<table><caption>Sales</caption><tr><th>Q</th></tr><tr><td>1</td></tr></table>"
        XCTAssertEqual(try md(html), "**Sales**\n\n| Q |\n| --- |\n| 1 |")
    }

    func testEmptyAnchorIsDropped() throws {
        XCTAssertEqual(try md("<p><a href=\"u\"></a>after</p>"), "after")
        // Image-only anchors are still kept.
        XCTAssertEqual(try md("<p><a href=\"u\"><img src=\"i.png\" alt=\"x\"></a></p>"),
                       "[![x](i.png)](u)")
    }

    // MARK: - HTML5 semantic elements (libxml2 drops these; we preserve them)

    func testPreservesHTML5SectioningElements() throws {
        // <figure>/<figcaption> would be dropped by libxml2, merging the image and caption
        // into one line; preservation keeps them as separate blocks.
        XCTAssertEqual(try md("<figure><img src=\"i.png\" alt=\"x\"><figcaption>cap</figcaption></figure>"),
                       "![x](i.png)\n\ncap")
        XCTAssertEqual(try md("<section><h2>T</h2><p>body</p></section>"), "## T\n\nbody")
        XCTAssertEqual(try md("<article><p>a</p></article><article><p>b</p></article>"), "a\n\nb")
        XCTAssertEqual(try md("<main><aside><p>note</p></aside></main>"), "note")
    }

    func testPreservesHTML5InlineElements() throws {
        XCTAssertEqual(try md("<p>before <mark>hi</mark> and <time>2026</time> after</p>"),
                       "before hi and 2026 after")
    }

    func testHTML5RenameDoesNotTouchAttributesOrText() throws {
        // `data-*` attributes and similar tag-name substrings must not be rewritten.
        XCTAssertEqual(try md("<p data-section=\"x\">a &lt;section&gt; tag</p>"),
                       "a <section> tag")
    }
}
