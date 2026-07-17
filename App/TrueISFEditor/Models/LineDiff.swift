import Foundation

/// One row of a computed line diff.
struct DiffLine: Equatable, Identifiable {
    enum Kind: Equatable { case same, removed, added }
    let kind: Kind
    let text: String
    /// 1-based line number in the old text (nil for added lines).
    let oldLine: Int?
    /// 1-based line number in the new text (nil for removed lines).
    let newLine: Int?
    var id: String { "\(kind)-\(oldLine ?? 0)-\(newLine ?? 0)" }
}

/// A display row: a diff line, or a fold standing in for a run of unchanged lines.
enum DiffRow: Equatable, Identifiable {
    case line(DiffLine)
    case fold(count: Int, index: Int)
    var id: String {
        switch self {
        case .line(let l): return l.id
        case .fold(_, let i): return "fold-\(i)"
        }
    }
}

/// LCS line diff (D2). Shader sources are small (hundreds of lines), so the O(n·m) table is
/// fine; a size guard degrades giant inputs to remove-all/add-all instead of blowing memory.
enum LineDiff {
    static func diff(old: String, new: String) -> [DiffLine] {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")

        // ~2000×2000 lines ≈ 32 MB of Int — anything bigger degrades gracefully.
        guard a.count * b.count <= 4_000_000 else {
            return a.enumerated().map { DiffLine(kind: .removed, text: $1, oldLine: $0 + 1, newLine: nil) }
                 + b.enumerated().map { DiffLine(kind: .added, text: $1, oldLine: nil, newLine: $0 + 1) }
        }

        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1
                                           : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var result: [DiffLine] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                result.append(DiffLine(kind: .same, text: a[i], oldLine: i + 1, newLine: j + 1))
                i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                result.append(DiffLine(kind: .removed, text: a[i], oldLine: i + 1, newLine: nil))
                i += 1
            } else {
                result.append(DiffLine(kind: .added, text: b[j], oldLine: nil, newLine: j + 1))
                j += 1
            }
        }
        while i < a.count {
            result.append(DiffLine(kind: .removed, text: a[i], oldLine: i + 1, newLine: nil)); i += 1
        }
        while j < b.count {
            result.append(DiffLine(kind: .added, text: b[j], oldLine: nil, newLine: j + 1)); j += 1
        }
        return result
    }

    /// Fold unchanged runs for display: keep `context` lines on each side of a change, collapse
    /// the middle of a longer same-run into a fold row. Changed lines always survive.
    static func displayRows(_ diff: [DiffLine], context: Int = 3) -> [DiffRow] {
        var rows: [DiffRow] = []
        var foldIndex = 0
        var i = 0
        while i < diff.count {
            guard diff[i].kind == .same else {
                rows.append(.line(diff[i])); i += 1; continue
            }
            var runEnd = i
            while runEnd < diff.count, diff[runEnd].kind == .same { runEnd += 1 }
            let run = Array(diff[i..<runEnd])
            if run.count > context * 2 + 2 {
                run.prefix(context).forEach { rows.append(.line($0)) }
                rows.append(.fold(count: run.count - context * 2, index: foldIndex))
                foldIndex += 1
                run.suffix(context).forEach { rows.append(.line($0)) }
            } else {
                run.forEach { rows.append(.line($0)) }
            }
            i = runEnd
        }
        return rows
    }
}
