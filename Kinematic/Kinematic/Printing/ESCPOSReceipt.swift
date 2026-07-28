// ESC/POS receipt builder for 58mm Bluetooth thermal printers.
//
// Produces a `Data` blob of ESC/POS commands sized for a 58mm head:
// 384 printable dots / 12-dot Font A glyphs = 32 characters per line.
// Everything is emitted as ASCII / CP437 (ESC t 0) because the cheap
// van-sales printers we target don't carry a Devanagari codepage — the
// rupee sign is rendered as the ASCII string "Rs." and any stray
// non-ASCII glyph is transliterated / dropped so the printer never
// prints a garbage byte.
//
// Layout (32 cols):
//   [center][bold]  COMPANY NAME
//   [center]        address line (optional)
//   [center]        GSTIN: ....... (optional)
//   --------------------------------
//   Bill No: ....        (left)
//   Date: ....           (left)
//   Bill To: outlet      (left)
//   --------------------------------
//   Item name .........  Rs.####.##   <- name left, amount right, word-wrapped
//     <qty> x Rs.<rate>                <- qty x rate detail line
//   --------------------------------
//                 SUBTOTAL  Rs.####.##  (right)
//                     CGST  Rs.####.##  (right)
//                     SGST  Rs.####.##  (right)
//   [bold]           TOTAL  Rs.####.##  (right)
//   --------------------------------
//   [center]        Thank you!
//   <feed> <cut>

import Foundation

/// A single printable line on the bill.
struct ReceiptLineItem {
    let name: String
    let qty: Int
    let unitPrice: Double
    let amount: Double
}

/// Everything the receipt needs. Built by the caller from the loaded order.
struct ReceiptBill {
    let companyName: String
    /// Optional seller address line printed under the company name.
    var address: String? = nil
    /// Optional seller GSTIN. Left blank when the model doesn't carry it.
    var gstin: String? = nil
    /// Customer / outlet the bill is made out to.
    let outletName: String?
    /// Human-facing bill / order number.
    let billNo: String
    /// Pre-formatted date string (caller formats to taste).
    let date: String
    let items: [ReceiptLineItem]
    let subtotal: Double
    let cgst: Double
    let sgst: Double
    let grandTotal: Double
    /// Footer line under the totals. Defaults to a friendly thank-you.
    var footer: String = "Thank you!"
}

enum ESCPOSReceipt {

    /// Printable width for 58mm Font A.
    static let width = 32

    // MARK: - Command bytes

    private enum Cmd {
        static let esc: UInt8 = 0x1B
        static let gs: UInt8  = 0x1D
        static let lf: UInt8  = 0x0A
    }

    // MARK: - Public entry point

    /// Render the bill to a stream of ESC/POS bytes ready to write to the printer.
    static func build(_ bill: ReceiptBill) -> Data {
        var d = Data()

        // ESC @  — initialise / reset the printer to a known state.
        d.append(contentsOf: [Cmd.esc, 0x40])
        // ESC t 0 — select character code table CP437 (USA / standard Europe).
        d.append(contentsOf: [Cmd.esc, 0x74, 0x00])
        // ESC M 0 — select Font A (12x24), the 32-char-per-line font.
        d.append(contentsOf: [Cmd.esc, 0x4D, 0x00])

        // ── Header ────────────────────────────────────────────────────────────
        center(&d)
        bold(&d, true)
        line(&d, bill.companyName.uppercased())
        bold(&d, false)
        if let addr = trimmedNonEmpty(bill.address) {
            for l in wrap(addr, width: width) { line(&d, l) }
        }
        if let gstin = trimmedNonEmpty(bill.gstin) {
            line(&d, "GSTIN: \(gstin)")
        }

        // ── Meta ──────────────────────────────────────────────────────────────
        left(&d)
        divider(&d)
        line(&d, "Bill No: \(bill.billNo)")
        line(&d, "Date: \(bill.date)")
        if let outlet = trimmedNonEmpty(bill.outletName) {
            for l in wrap("Bill To: \(outlet)", width: width) { line(&d, l) }
        }

        // ── Items ─────────────────────────────────────────────────────────────
        divider(&d)
        for item in bill.items {
            appendItem(&d, item)
        }

        // ── Totals ────────────────────────────────────────────────────────────
        divider(&d)
        line(&d, totalRow("SUBTOTAL", bill.subtotal))
        line(&d, totalRow("CGST", bill.cgst))
        line(&d, totalRow("SGST", bill.sgst))
        bold(&d, true)
        line(&d, totalRow("TOTAL", bill.grandTotal))
        bold(&d, false)
        divider(&d)

        // ── Footer ────────────────────────────────────────────────────────────
        center(&d)
        if let f = trimmedNonEmpty(bill.footer) {
            for l in wrap(f, width: width) { line(&d, l) }
        }
        left(&d)

        // Feed a few lines so the tear-off / cut clears the print head, then cut.
        // ESC d 4 — feed 4 lines.
        d.append(contentsOf: [Cmd.esc, 0x64, 0x04])
        // GS V 0 — full cut.
        d.append(contentsOf: [Cmd.gs, 0x56, 0x00])

        return d
    }

    // MARK: - Item rendering

    /// Name on the left, amount right-aligned, word-wrapped; then a
    /// "<qty> x Rs.<rate>" detail line indented under it.
    private static func appendItem(_ d: inout Data, _ item: ReceiptLineItem) {
        let amount = money(item.amount)
        // Reserve room on the right for the amount + a one-space gap.
        let leftWidth = max(1, width - amount.count - 1)
        let nameChunks = wrap(sanitize(item.name), width: leftWidth)

        if nameChunks.isEmpty {
            line(&d, padRightAmount("", amount))
        } else {
            for (i, chunk) in nameChunks.enumerated() {
                if i == nameChunks.count - 1 {
                    line(&d, padRightAmount(chunk, amount))
                } else {
                    line(&d, chunk)
                }
            }
        }

        // Detail line: "  3 x Rs.412.00"
        line(&d, "  \(item.qty) x \(money(item.unitPrice))")
    }

    /// Left text padded with spaces so `amount` sits flush against the right edge.
    private static func padRightAmount(_ leftText: String, _ amount: String) -> String {
        let leftRoom = max(0, width - amount.count)
        let padded = leftText.count >= leftRoom
            ? String(leftText.prefix(leftRoom))
            : leftText + String(repeating: " ", count: leftRoom - leftText.count)
        return padded + amount
    }

    /// A right-aligned "LABEL  Rs.####.##" totals row.
    private static func totalRow(_ label: String, _ value: Double) -> String {
        let text = "\(label)  \(money(value))"
        guard text.count < width else { return String(text.suffix(width)) }
        return String(repeating: " ", count: width - text.count) + text
    }

    // MARK: - Text primitives

    private static func divider(_ d: inout Data) {
        line(&d, String(repeating: "-", count: width))
    }

    /// Append one already-sanitised text line followed by LF.
    private static func line(_ d: inout Data, _ text: String) {
        d.append(encode(text))
        d.append(Cmd.lf)
    }

    private static func center(_ d: inout Data) { d.append(contentsOf: [Cmd.esc, 0x61, 0x01]) }
    private static func left(_ d: inout Data)   { d.append(contentsOf: [Cmd.esc, 0x61, 0x00]) }

    private static func bold(_ d: inout Data, _ on: Bool) {
        d.append(contentsOf: [Cmd.esc, 0x45, on ? 0x01 : 0x00])
    }

    // MARK: - Encoding helpers

    /// Format a rupee amount as ASCII "Rs.1,234.00" with Indian grouping.
    private static let amountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_IN")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func money(_ value: Double) -> String {
        let v = value.isFinite ? value : 0
        let s = amountFormatter.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
        return "Rs.\(s)"
    }

    /// Transliterate to printable ASCII: rupee sign -> "Rs.", strip diacritics,
    /// so the printer's CP437 table never receives a byte it can't render.
    private static func sanitize(_ text: String) -> String {
        let deRupee = text.replacingOccurrences(of: "\u{20B9}", with: "Rs.")
        let folded = deRupee.folding(options: [.diacriticInsensitive, .widthInsensitive],
                                     locale: Locale(identifier: "en_US"))
        return folded
    }

    /// Encode a line to ASCII bytes, lossily replacing anything left over.
    private static func encode(_ text: String) -> Data {
        let clean = sanitize(text)
        if let ascii = clean.data(using: .ascii, allowLossyConversion: true) {
            return ascii
        }
        // Last resort: keep only 7-bit code points.
        return Data(clean.unicodeScalars.map { $0.isASCII ? UInt8($0.value) : 0x3F }) // '?'
    }

    // MARK: - Word wrap

    /// Greedy word-wrap to `width` columns. Long single words are hard-split.
    static func wrap(_ text: String, width: Int) -> [String] {
        guard width > 0 else { return [text] }
        let words = sanitize(text).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var lines: [String] = []
        var current = ""
        for word in words {
            var w = word
            // Hard-split a word longer than the line.
            while w.count > width {
                if current.isEmpty {
                    lines.append(String(w.prefix(width)))
                    w = String(w.dropFirst(width))
                } else {
                    lines.append(current)
                    current = ""
                }
            }
            if current.isEmpty {
                current = w
            } else if current.count + 1 + w.count <= width {
                current += " " + w
            } else {
                lines.append(current)
                current = w
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private static func trimmedNonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
