import Foundation

/// Renders OOXML math (OMML, the `m:` namespace from shared-math.xsd) to a
/// LaTeX-ish string suitable for Markdown `$…$`. A pragmatic subset covering the
/// common constructs (fractions, sub/superscripts, radicals, n-ary operators,
/// delimiters, functions, matrices); anything else falls back to concatenating
/// the inner run text.
enum OMML {
    /// Render an `m:oMath` element's contents to LaTeX.
    static func latex(_ oMath: XMLElement) -> String { renderChildren(oMath) }

    private static func render(_ el: XMLElement) -> String {
        switch el.localName {
        case "t":
            return el.stringValue ?? ""
        case "f":   // fraction
            return "\\frac{\(child(el, "num"))}{\(child(el, "den"))}"
        case "sSup":
            return "{\(child(el, "e"))}^{\(child(el, "sup"))}"
        case "sSub":
            return "{\(child(el, "e"))}_{\(child(el, "sub"))}"
        case "sSubSup":
            return "{\(child(el, "e"))}_{\(child(el, "sub"))}^{\(child(el, "sup"))}"
        case "rad":   // radical
            let deg = child(el, "deg")
            let body = child(el, "e")
            return deg.isEmpty ? "\\sqrt{\(body)}" : "\\sqrt[\(deg)]{\(body)}"
        case "nary":  // n-ary operator (sum/integral/product)
            let op = naryOperator(el.firstChild("naryPr")?.firstChild("chr")?.attr("val"))
            var s = op
            let sub = child(el, "sub"), sup = child(el, "sup")
            if !sub.isEmpty { s += "_{\(sub)}" }
            if !sup.isEmpty { s += "^{\(sup)}" }
            return s + " " + child(el, "e")
        case "d":     // delimiter
            let pr = el.firstChild("dPr")
            let beg = delimiter(pr?.firstChild("begChr")?.attr("val") ?? "(")
            let end = delimiter(pr?.firstChild("endChr")?.attr("val") ?? ")")
            let inner = el.childElements("e").map(renderChildren).joined(separator: ", ")
            return "\\left\(beg)\(inner)\\right\(end)"
        case "func":  // named function
            return "\(child(el, "fName")) \(child(el, "e"))"
        case "m":     // matrix
            let rows = el.childElements("mr").map { mr in
                mr.childElements("e").map(renderChildren).joined(separator: " & ")
            }
            return "\\begin{matrix} " + rows.joined(separator: " \\\\ ") + " \\end{matrix}"
        default:
            return renderChildren(el)
        }
    }

    /// Concatenate rendered children, skipping property elements (`*Pr`).
    private static func renderChildren(_ el: XMLElement) -> String {
        var out = ""
        for case let c as XMLElement in el.children ?? [] {
            if c.localName?.hasSuffix("Pr") == true { continue }   // rPr, fPr, naryPr, dPr, ctrlPr…
            out += render(c)
        }
        return out
    }

    private static func child(_ el: XMLElement, _ name: String) -> String {
        el.firstChild(name).map(renderChildren) ?? ""
    }

    private static func naryOperator(_ chr: String?) -> String {
        switch chr {
        case "∑": return "\\sum"
        case "∏": return "\\prod"
        case "∫", nil: return "\\int"
        default: return chr ?? "\\int"
        }
    }

    private static func delimiter(_ c: String) -> String {
        switch c {
        case "{": return "\\{"
        case "}": return "\\}"
        default:  return c   // ( ) [ ] | etc.
        }
    }
}
