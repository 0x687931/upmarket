import Foundation

/// Optimal ordered tree edit distance (Zhang–Shasha). Produces the same distance APTED would;
/// APTED is only a speed optimization and can replace this later without changing results.
struct ZhangShasha {
    let deleteCost: (TableTreeNode) -> Double
    let insertCost: (TableTreeNode) -> Double
    let renameCost: (TableTreeNode, TableTreeNode) -> Double

    /// TEDS cost model: insert/delete = 1 per node; rename = 0 for matching `table`/`tr`; for
    /// `td`, 1 if spans differ, else 0 (structural) or normalized content edit distance (total).
    init(structural: Bool) {
        deleteCost = { _ in 1 }
        insertCost = { _ in 1 }
        renameCost = { a, b in
            if a.tag != b.tag { return 1 }
            if a.tag == "td" {
                if a.colspan != b.colspan || a.rowspan != b.rowspan { return 1 }
                return structural ? 0 : ZhangShasha.normalizedLevenshtein(a.content, b.content)
            }
            return 0
        }
    }

    func distance(_ a: TableTreeNode, _ b: TableTreeNode) -> Double {
        let A = annotate(a)
        let B = annotate(b)
        let sizeA = A.nodes.count - 1
        let sizeB = B.nodes.count - 1
        var treedist = Array(repeating: Array(repeating: 0.0, count: sizeB + 1), count: sizeA + 1)

        for i in A.keyroots {
            for j in B.keyroots {
                let li = A.leftmost[i], lj = B.leftmost[j]
                let offA = li - 1, offB = lj - 1
                let rows = i - li + 2, cols = j - lj + 2
                var fd = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)

                var di = li
                while di <= i { fd[di - offA][0] = fd[di - 1 - offA][0] + deleteCost(A.nodes[di]); di += 1 }
                var dj = lj
                while dj <= j { fd[0][dj - offB] = fd[0][dj - 1 - offB] + insertCost(B.nodes[dj]); dj += 1 }

                di = li
                while di <= i {
                    dj = lj
                    while dj <= j {
                        let del = fd[di - 1 - offA][dj - offB] + deleteCost(A.nodes[di])
                        let ins = fd[di - offA][dj - 1 - offB] + insertCost(B.nodes[dj])
                        if A.leftmost[di] == li && B.leftmost[dj] == lj {
                            let ren = fd[di - 1 - offA][dj - 1 - offB] + renameCost(A.nodes[di], B.nodes[dj])
                            let best = min(del, ins, ren)
                            fd[di - offA][dj - offB] = best
                            treedist[di][dj] = best
                        } else {
                            let sub = fd[A.leftmost[di] - 1 - offA][B.leftmost[dj] - 1 - offB] + treedist[di][dj]
                            fd[di - offA][dj - offB] = min(del, ins, sub)
                        }
                        dj += 1
                    }
                    di += 1
                }
            }
        }
        return treedist[sizeA][sizeB]
    }

    // MARK: - Postorder annotation

    private struct Annotated {
        var nodes: [TableTreeNode]   // 1-based; index 0 is a dummy
        var leftmost: [Int]          // 1-based postorder index of each node's leftmost leaf
        var keyroots: [Int]          // ascending
    }

    private func annotate(_ root: TableTreeNode) -> Annotated {
        var nodes: [TableTreeNode] = [TableTreeNode(tag: "")]
        var leftmost: [Int] = [0]

        @discardableResult
        func visit(_ node: TableTreeNode) -> Int {
            var firstChildLeftmost = 0
            for (k, child) in node.children.enumerated() {
                let childLeftmost = visit(child)
                if k == 0 { firstChildLeftmost = childLeftmost }
            }
            nodes.append(node)
            let myIndex = nodes.count - 1
            let leftmostLeaf = node.children.isEmpty ? myIndex : firstChildLeftmost
            leftmost.append(leftmostLeaf)
            return leftmostLeaf
        }
        visit(root)

        var seen = Set<Int>()
        var keyroots: [Int] = []
        for k in stride(from: nodes.count - 1, through: 1, by: -1) where !seen.contains(leftmost[k]) {
            keyroots.append(k)
            seen.insert(leftmost[k])
        }
        keyroots.sort()
        return Annotated(nodes: nodes, leftmost: leftmost, keyroots: keyroots)
    }

    // MARK: - String distance (total-TEDS cell content)

    /// Levenshtein distance normalized to 0...1 by the longer string. 0 = identical.
    static func normalizedLevenshtein(_ s1: String, _ s2: String) -> Double {
        let a = Array(s1), b = Array(s2)
        if a.isEmpty && b.isEmpty { return 0 }
        if a.isEmpty || b.isEmpty { return 1 }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return Double(prev[b.count]) / Double(max(a.count, b.count))
    }
}
