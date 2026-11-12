import SwiftUI

/// Text drawn with an original 5×7 dot-matrix font. Used for big numbers and
/// short words. VoiceOver reads the plain text.
struct DotMatrixText: View {
    let text: String
    var dotSize: CGFloat = 4
    var color: Color = Theme.primary
    @Environment(\.colorScheme) private var colorScheme // redraw on appearance change

    var body: some View {
        let gap = dotSize * 0.45
        let cell = dotSize + gap
        let glyphs = text.uppercased().map(DotFont.glyph)
        let columns = glyphs.reduce(0) { $0 + $1.width } + max(0, glyphs.count - 1)
        Canvas { context, _ in
            var x = 0
            for glyph in glyphs {
                for (row, bits) in glyph.rows.enumerated() {
                    for (column, on) in bits.enumerated() where on {
                        let rect = CGRect(x: CGFloat(x + column) * cell, y: CGFloat(row) * cell, width: dotSize, height: dotSize)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                x += glyph.width + 1
            }
        }
        .frame(width: max(0, CGFloat(columns) * cell - gap), height: 7 * cell - gap)
        .id(colorScheme)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// A ring of dots. Idle: grey with one red dot at the top. Active: fills
/// clockwise with the progress, the leading dot in red.
struct DotRing: View {
    var progress: Double
    var isActive: Bool
    var diameter: CGFloat
    var dotCount = 72
    var dotSize: CGFloat = 5
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in draw(in: &context, size: size) }
        .frame(width: diameter, height: diameter)
        .id(colorScheme)
        .accessibilityHidden(true)
    }

    // Kept out of the Canvas closure, with explicit types, so older Swift
    // compilers can type-check it quickly.
    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let centerX: CGFloat = size.width / 2
        let centerY: CGFloat = size.height / 2
        let radius: CGFloat = diameter / 2 - dotSize
        let filled: Int = isActive ? min(dotCount, Int(progress * Double(dotCount))) : 0
        let head: Int = isActive ? min(filled, dotCount - 1) : 0
        let step: Double = 2 * Double.pi / Double(dotCount)
        for index in 0..<dotCount {
            let angle: Double = Double(index) * step - Double.pi / 2
            let x: CGFloat = centerX + radius * CGFloat(cos(angle))
            let y: CGFloat = centerY + radius * CGFloat(sin(angle))
            let isHead: Bool = index == head && (!isActive || filled < dotCount)
            let color: Color = dotColor(index: index, filled: filled, isHead: isHead)
            let side: CGFloat = isHead ? dotSize * 1.35 : dotSize
            let rect = CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    private func dotColor(index: Int, filled: Int, isHead: Bool) -> Color {
        if isHead { return Theme.accent }
        return index < filled ? Theme.primary : Theme.dotOff
    }
}

enum DotFont {
    struct Glyph: Sendable {
        let rows: [[Bool]]
        var width: Int { rows.first?.count ?? 0 }
    }

    static func glyph(_ character: Character) -> Glyph {
        glyphs[character] ?? glyphs[" "]!
    }

    private static let glyphs: [Character: Glyph] = raw.mapValues { rows in
        Glyph(rows: rows.map { $0.map { $0 == "#" } })
    }

    // "#" = dot. Glyphs are 5 wide unless noted.
    private static let raw: [Character: [String]] = [
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "D": ["###..", "#..#.", "#...#", "#...#", "#...#", "#..#.", "###.."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
        ".": [".", ".", ".", ".", ".", ".", "#"],                       // 1 wide
        ",": ["..", "..", "..", "..", "..", ".#", "#."],                // 2 wide
        "-": ["...", "...", "...", "###", "...", "...", "..."],         // 3 wide
        "%": ["##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##"],
        " ": ["...", "...", "...", "...", "...", "...", "..."],         // 3 wide
    ]
}
