import Foundation
import ImageIO

/// Reads the capture date from an image's metadata with ImageIO.
public enum ExifDateReader {
    /// Metadata fields tried in order. All three come from the image's own
    /// EXIF/TIFF metadata, so this is not a fallback to another date source.
    static var fields: [(dictionary: CFString, key: CFString)] {
        [
        (kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeOriginal),
        (kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeDigitized),
        (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFDateTime),
        ]
    }

    /// Returns the image's capture date, or nil if it has none or the file
    /// is not a readable image.
    public static func captureDate(at url: URL) -> LocalDateTime? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any]
        else { return nil }
        return captureDate(fromProperties: properties)
    }

    /// Picks the capture date out of an ImageIO properties dictionary.
    static func captureDate(fromProperties properties: [CFString: Any]) -> LocalDateTime? {
        for field in fields {
            guard let dictionary = properties[field.dictionary] as? [CFString: Any],
                  let value = dictionary[field.key] as? String,
                  let date = parse(value)
            else { continue }
            return date
        }
        return nil
    }

    /// Parses an EXIF date string, normally "yyyy:MM:dd HH:mm:ss".
    /// Also accepts "-" as the date separator and "T" before the time.
    /// Returns nil for blank or zeroed dates such as "0000:00:00 00:00:00".
    static func parse(_ text: String) -> LocalDateTime? {
        // Fixed layout: yyyy?MM?dd?HH:mm:ss, 19 characters.
        let chars = Array(text.trimmingCharacters(in: .whitespaces).utf8.prefix(19))
        guard chars.count == 19,
              [4, 7].allSatisfy({ chars[$0] == UInt8(ascii: ":") || chars[$0] == UInt8(ascii: "-") }),
              chars[10] == UInt8(ascii: " ") || chars[10] == UInt8(ascii: "T"),
              chars[13] == UInt8(ascii: ":"), chars[16] == UInt8(ascii: ":")
        else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let char = chars[index]
                guard char >= UInt8(ascii: "0"), char <= UInt8(ascii: "9") else { return nil }
                value = value * 10 + Int(char - UInt8(ascii: "0"))
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19)
        else { return nil }
        return LocalDateTime(year: year, month: month, day: day,
                             hour: hour, minute: minute, second: second)
    }
}
