import Foundation
import CoreFoundation

enum TextDecoder {

    static func decode(_ data: Data) -> String? {
        if data.isEmpty { return "" }

        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            return String(data: data.subdata(in: 3..<data.count), encoding: .utf8)
        }
        if data.count >= 2 && data[0] == 0xFF && data[1] == 0xFE {
            return String(data: data.subdata(in: 2..<data.count), encoding: .utf16LittleEndian)
        }
        if data.count >= 2 && data[0] == 0xFE && data[1] == 0xFF {
            return String(data: data.subdata(in: 2..<data.count), encoding: .utf16BigEndian)
        }

        if let text = String(data: data, encoding: .utf8) {
            if !text.contains("\u{FFFD}") {
                return text
            }
        }

        // GB18030 / GBK: the most common encoding of Chinese TXT novels
        let gbRaw = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let text = String(data: data, encoding: String.Encoding(rawValue: gbRaw)) {
            let broken = text.filter { $0 == "\u{FFFD}" }.count
            if broken == 0 || broken * 200 < max(1, text.count) {
                return text
            }
        }

        if let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return String(data: data, encoding: .utf8)
    }
}
