import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads all of an image file's metadata for the Photo Info popover.
///
/// Known keys go into fixed sections with readable labels and values.
/// Everything else goes into "More" sections, one per ImageIO dictionary,
/// so nothing readable is hidden. Binary values are counted, not shown.
public enum PhotoInfoReader {
    /// Nil if the file is missing or not a readable image.
    public static func read(at url: URL) -> PhotoInfo? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [String: Any]
        else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        return info(fromProperties: properties, typeIdentifier: CGImageSourceGetType(source) as String?,
                    fileSize: values?.fileSize, fileCreated: values?.creationDate,
                    fileModified: values?.contentModificationDate)
    }

    /// Builds the info from ImageIO's property dictionary. File dates show
    /// in `timeZone`, with its offset.
    public static func info(fromProperties properties: [String: Any], typeIdentifier: String? = nil,
                            fileSize: Int? = nil, fileCreated: Date? = nil, fileModified: Date? = nil,
                            timeZone: TimeZone = .current) -> PhotoInfo {
        var builder = Builder(properties)
        let coordinate = builder.coordinate()
        var sections = [
            builder.camera(),
            builder.exposure(),
            builder.lens(),
            builder.image(typeIdentifier: typeIdentifier, fileSize: fileSize),
            builder.dates(fileCreated: fileCreated, fileModified: fileModified, timeZone: timeZone),
            builder.location(coordinate),
        ]
        sections += builder.remaining()
        return PhotoInfo(sections: sections, coordinate: coordinate, skippedBinaryCount: builder.skippedBinary)
    }
}

// MARK: - Building sections

private let top = ""
private let exif = kCGImagePropertyExifDictionary as String
private let exifAux = kCGImagePropertyExifAuxDictionary as String
private let tiff = kCGImagePropertyTIFFDictionary as String
private let gps = kCGImagePropertyGPSDictionary as String

/// Hands out values by dictionary and key, remembering which were used so
/// the rest can go into "More" sections.
private struct Builder {
    /// Top-level values under "", then each nested dictionary by name.
    private var dictionaries: [String: [String: Any]] = [:]
    private var used: [String: Set<String>] = [:]
    private(set) var skippedBinary = 0

    init(_ properties: [String: Any]) {
        var topLevel: [String: Any] = [:]
        for (key, value) in properties {
            if let nested = value as? [String: Any], key.hasPrefix("{") {
                dictionaries[key] = nested
            } else {
                topLevel[key] = value
            }
        }
        dictionaries[top] = topLevel
        // Shown via the file's own size instead.
        markUsed(top, kCGImagePropertyFileSize as String)
    }

    private mutating func markUsed(_ dictionary: String, _ key: String) {
        used[dictionary, default: []].insert(key)
    }

    /// The value, marked as used.
    private mutating func take(_ dictionary: String, _ key: CFString) -> Any? {
        let key = key as String
        guard let value = dictionaries[dictionary]?[key] else { return nil }
        markUsed(dictionary, key)
        return value
    }

    private mutating func string(_ dictionary: String, _ key: CFString) -> String? {
        take(dictionary, key).flatMap(Format.plain)?.nonEmpty
    }

    private mutating func number(_ dictionary: String, _ key: CFString) -> Double? {
        Format.number(take(dictionary, key))
    }

    mutating func camera() -> PhotoInfo.Section {
        var rows: [PhotoInfo.Row] = []
        rows.add("Make", string(tiff, kCGImagePropertyTIFFMake))
        rows.add("Model", string(tiff, kCGImagePropertyTIFFModel))
        rows.add("Software", string(tiff, kCGImagePropertyTIFFSoftware))
        let serial = string(exif, kCGImagePropertyExifBodySerialNumber)
        let auxSerial = string(exifAux, kCGImagePropertyExifAuxSerialNumber)
        rows.add("Serial number", serial ?? auxSerial)
        rows.add("Owner", string(exif, kCGImagePropertyExifCameraOwnerName))
        rows.add("Artist", string(tiff, kCGImagePropertyTIFFArtist))
        rows.add("Copyright", string(tiff, kCGImagePropertyTIFFCopyright))
        return PhotoInfo.Section("Camera", rows)
    }

    mutating func exposure() -> PhotoInfo.Section {
        var rows: [PhotoInfo.Row] = []
        rows.add("Shutter speed", number(exif, kCGImagePropertyExifExposureTime).map(Format.shutter))
        rows.add("Aperture", number(exif, kCGImagePropertyExifFNumber).map { "f/\(Format.decimal($0, digits: 1))" })
        rows.add("ISO", number(exif, kCGImagePropertyExifISOSpeedRatings).map { Format.decimal($0) })
        rows.add("Exposure bias", number(exif, kCGImagePropertyExifExposureBiasValue).map(Format.bias))
        rows.add("Program", number(exif, kCGImagePropertyExifExposureProgram).map(Format.program))
        rows.add("Metering", number(exif, kCGImagePropertyExifMeteringMode).map(Format.metering))
        rows.add("Flash", number(exif, kCGImagePropertyExifFlash).map(Format.flash))
        rows.add("White balance", number(exif, kCGImagePropertyExifWhiteBalance)
            .map { $0 == 0 ? "Auto" : $0 == 1 ? "Manual" : Format.decimal($0) })
        return PhotoInfo.Section("Exposure", rows)
    }

    mutating func lens() -> PhotoInfo.Section {
        var rows: [PhotoInfo.Row] = []
        let model = string(exif, kCGImagePropertyExifLensModel)
        let auxModel = string(exifAux, kCGImagePropertyExifAuxLensModel)
        rows.add("Lens", model ?? auxModel)
        rows.add("Lens make", string(exif, kCGImagePropertyExifLensMake))
        rows.add("Focal length", number(exif, kCGImagePropertyExifFocalLength).map { "\(Format.decimal($0, digits: 1)) mm" })
        rows.add("35 mm equivalent", number(exif, kCGImagePropertyExifFocalLenIn35mmFilm).map { "\(Format.decimal($0)) mm" })
        return PhotoInfo.Section("Lens", rows)
    }

    mutating func image(typeIdentifier: String?, fileSize: Int?) -> PhotoInfo.Section {
        var rows: [PhotoInfo.Row] = []
        let width = number(top, kCGImagePropertyPixelWidth)
        let height = number(top, kCGImagePropertyPixelHeight)
        if let width, let height {
            rows.add("Size", "\(Format.decimal(width)) × \(Format.decimal(height)) pixels")
        }
        let orientation = number(top, kCGImagePropertyOrientation)
        let tiffOrientation = number(tiff, kCGImagePropertyTIFFOrientation)
        rows.add("Orientation", (orientation ?? tiffOrientation).map(Format.orientation))
        rows.add("Color profile", string(top, kCGImagePropertyProfileName))
        rows.add("Color model", string(top, kCGImagePropertyColorModel))
        rows.add("Bit depth", number(top, kCGImagePropertyDepth).map { "\(Format.decimal($0)) bits per channel" })
        let dpiWidth = number(top, kCGImagePropertyDPIWidth)
        let dpiHeight = number(top, kCGImagePropertyDPIHeight)
        // TIFF repeats the resolution with a unit code; show it once.
        let xResolution = number(tiff, kCGImagePropertyTIFFXResolution)
        let yResolution = number(tiff, kCGImagePropertyTIFFYResolution)
        let unit = number(tiff, kCGImagePropertyTIFFResolutionUnit)
        if let dpiWidth, let dpiHeight {
            rows.add("Resolution", "\(Format.decimal(dpiWidth)) × \(Format.decimal(dpiHeight)) dpi")
        } else if let xResolution, let yResolution {
            let suffix = unit == 3 ? "pixels per cm" : "dpi"
            rows.add("Resolution", "\(Format.decimal(xResolution)) × \(Format.decimal(yResolution)) \(suffix)")
        }
        rows.add("Color space", number(exif, kCGImagePropertyExifColorSpace).map(Format.colorSpace))
        rows.add("File type", typeIdentifier.map { UTType($0)?.localizedDescription ?? $0 })
        rows.add("File size", fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) })
        return PhotoInfo.Section("Image", rows)
    }

    mutating func dates(fileCreated: Date?, fileModified: Date?, timeZone: TimeZone) -> PhotoInfo.Section {
        var rows: [PhotoInfo.Row] = []
        func date(_ dictionary: String, _ key: CFString, offset: CFString) -> String? {
            guard let text = string(dictionary, key) else { return nil }
            return Format.exifDate(text, offset: string(exif, offset))
        }
        rows.add("Taken", date(exif, kCGImagePropertyExifDateTimeOriginal, offset: kCGImagePropertyExifOffsetTimeOriginal))
        rows.add("Digitized", date(exif, kCGImagePropertyExifDateTimeDigitized, offset: kCGImagePropertyExifOffsetTimeDigitized))
        rows.add("Modified", date(tiff, kCGImagePropertyTIFFDateTime, offset: kCGImagePropertyExifOffsetTime))
        rows.add("File created", fileCreated.map { PhotoInfo.format($0, timeZone) })
        rows.add("File modified", fileModified.map { PhotoInfo.format($0, timeZone) })
        return PhotoInfo.Section("Dates", rows)
    }

    mutating func coordinate() -> Coordinate? {
        func signed(_ key: CFString, _ refKey: CFString, negative: String) -> Double? {
            guard let value = number(gps, key) else { return nil }
            let ref = string(gps, refKey)?.uppercased()
            return ref == nil ? value : (ref == negative ? -abs(value) : abs(value))
        }
        let latitude = signed(kCGImagePropertyGPSLatitude, kCGImagePropertyGPSLatitudeRef, negative: "S")
        let longitude = signed(kCGImagePropertyGPSLongitude, kCGImagePropertyGPSLongitudeRef, negative: "W")
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    mutating func location(_ coordinate: Coordinate?) -> PhotoInfo.Section {
        var rows: [PhotoInfo.Row] = []
        rows.add("Coordinates", coordinate?.formatted)
        if let altitude = number(gps, kCGImagePropertyGPSAltitude) {
            let below = number(gps, kCGImagePropertyGPSAltitudeRef) == 1
            rows.add("Altitude", "\(Format.decimal(below ? -altitude : altitude, digits: 1)) m")
        }
        if let direction = number(gps, kCGImagePropertyGPSImgDirection) {
            let ref = string(gps, kCGImagePropertyGPSImgDirectionRef)?.uppercased()
            let north = ref == "M" ? " (magnetic north)" : ref == "T" ? " (true north)" : ""
            rows.add("Direction", "\(Format.decimal(direction))°\(north)")
        }
        if let speed = number(gps, kCGImagePropertyGPSSpeed) {
            let unit = switch string(gps, kCGImagePropertyGPSSpeedRef)?.uppercased() {
            case "M": "mph"
            case "N": "knots"
            default: "km/h"
            }
            rows.add("Speed", "\(Format.decimal(speed, digits: 1)) \(unit)")
        }
        rows.add("Accuracy", number(gps, kCGImagePropertyGPSHPositioningError)
            .map { "± \(Format.decimal($0, digits: 1)) m" })
        let day = string(gps, kCGImagePropertyGPSDateStamp)
        let time = string(gps, kCGImagePropertyGPSTimeStamp)
        if let day, let time {
            rows.add("GPS time", "\(day.replacingOccurrences(of: ":", with: "-")) \(time) UTC")
        }
        return PhotoInfo.Section("Location", rows)
    }

    /// One "More" section per dictionary, with every value not yet shown.
    mutating func remaining() -> [PhotoInfo.Section] {
        let order: [String] = [top, exif, tiff, gps, exifAux]
        let names = order + dictionaries.keys.filter { !order.contains($0) }.sorted()
        var sections: [PhotoInfo.Section] = []
        for name in names {
            guard let dictionary = dictionaries[name] else { continue }
            let unused = dictionary.filter { !(used[name]?.contains($0.key) ?? false) }
            var rows: [PhotoInfo.Row] = []
            flatten(unused, prefix: "", into: &rows)
            sections.append(PhotoInfo.Section("More: \(Format.dictionaryName(name))", rows))
        }
        return sections
    }

    private mutating func flatten(_ dictionary: [String: Any], prefix: String, into rows: inout [PhotoInfo.Row]) {
        for key in dictionary.keys.sorted() {
            let label = prefix + Format.label(forKey: key)
            if let nested = dictionary[key] as? [String: Any] {
                flatten(nested, prefix: label + " › ", into: &rows)
            } else if let value = dictionary[key].flatMap(Format.plain) {
                rows.append(PhotoInfo.Row(label, value))
            } else {
                skippedBinary += 1
            }
        }
    }
}

private extension [PhotoInfo.Row] {
    mutating func add(_ label: String, _ value: String?) {
        if let value { append(PhotoInfo.Row(label, value)) }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Formatting

/// Value formatting. Locale-independent, so tests are stable.
enum Format {
    /// Longest array shown as text; longer ones count as binary.
    static let maxArrayCount = 32

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    /// "2.8", "35", "0.0003".
    static func decimal(_ value: Double, digits: Int = 4) -> String {
        let formatter = decimalFormatter.copy() as! NumberFormatter
        formatter.maximumFractionDigits = digits
        let text = formatter.string(from: NSNumber(value: value)) ?? String(value)
        return text == "-0" ? "0" : text
    }

    /// A number from an NSNumber, or the first element of a number array
    /// (ImageIO stores ISO as an array).
    static func number(_ value: Any?) -> Double? {
        if let array = value as? [Any] { return number(array.first) }
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        return number.doubleValue
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Text for a simple value; nil for binary data and long arrays.
    static func plain(_ value: Any) -> String? {
        switch value {
        case let text as String:
            return text
        case let number as NSNumber:
            return isBoolean(number) ? (number.boolValue ? "Yes" : "No") : decimal(number.doubleValue)
        case let array as [Any]:
            guard array.count <= maxArrayCount else { return nil }
            let parts = array.compactMap(plain)
            return parts.count == array.count ? parts.joined(separator: ", ") : nil
        default:
            return nil
        }
    }

    /// "1/250 s", "0.5 s", "2 s".
    static func shutter(_ seconds: Double) -> String {
        guard seconds > 0 else { return "\(decimal(seconds)) s" }
        if seconds < 0.5 {
            return "1/\(decimal((1 / seconds).rounded(), digits: 0)) s"
        }
        return "\(decimal(seconds, digits: 1)) s"
    }

    /// "+0.7 EV", "−1 EV", "0 EV".
    static func bias(_ value: Double) -> String {
        let text = decimal(abs(value), digits: 1)
        if text == "0" { return "0 EV" }
        return "\(value < 0 ? "−" : "+")\(text) EV"
    }

    static func colorSpace(_ value: Double) -> String {
        switch Int(value) {
        case 1: "sRGB"
        case 65535: "Uncalibrated"
        default: decimal(value)
        }
    }

    static func program(_ value: Double) -> String {
        let names = [1: "Manual", 2: "Normal", 3: "Aperture priority", 4: "Shutter priority",
                     5: "Creative", 6: "Action", 7: "Portrait", 8: "Landscape"]
        return names[Int(value)] ?? "Not defined"
    }

    static func metering(_ value: Double) -> String {
        let names = [1: "Average", 2: "Center-weighted average", 3: "Spot", 4: "Multi-spot",
                     5: "Pattern", 6: "Partial"]
        return names[Int(value)] ?? (Int(value) == 255 ? "Other" : "Unknown")
    }

    /// Bit 0 says whether the flash fired.
    static func flash(_ value: Double) -> String {
        Int(value) & 1 == 1 ? "Fired" : "Did not fire"
    }

    /// EXIF orientation 1–8, as exiftool names them.
    static func orientation(_ value: Double) -> String {
        switch Int(value) {
        case 1: "Normal"
        case 2: "Mirrored horizontally"
        case 3: "Rotated 180°"
        case 4: "Mirrored vertically"
        case 5: "Mirrored horizontally, rotated 270° clockwise"
        case 6: "Rotated 90° clockwise"
        case 7: "Mirrored horizontally, rotated 90° clockwise"
        case 8: "Rotated 270° clockwise"
        default: decimal(value)
        }
    }

    /// "2025:11:03 10:00:00" → "2025-11-03 10:00:00", plus " +01:00" when
    /// the offset is known. Other text is returned as is.
    static func exifDate(_ text: String, offset: String?) -> String {
        var result = text
        if text.count >= 10, text.dropFirst(4).first == ":", text.dropFirst(7).first == ":" {
            let day = text.prefix(10).replacingOccurrences(of: ":", with: "-")
            result = day + text.dropFirst(10)
        }
        if let offset { result += " \(offset)" }
        return result
    }

    /// "{Exif}" → "EXIF", "{MakerApple}" → "Apple maker notes", "" → "File".
    static func dictionaryName(_ name: String) -> String {
        let known = ["": "File", exif: "EXIF", exifAux: "EXIF Aux", tiff: "TIFF", gps: "GPS",
                     kCGImagePropertyIPTCDictionary as String: "IPTC"]
        if let name = known[name] { return name }
        let bare = name.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        if bare.hasPrefix("Maker"), bare.count > 5 {
            return "\(bare.dropFirst(5)) maker notes"
        }
        return bare
    }

    /// "ExposureTime" → "Exposure Time", "ISOSpeedRatings" → "ISO Speed
    /// Ratings", "_PrivateKey" → "Private Key".
    static func label(forKey key: String) -> String {
        let characters = Array(key.trimmingCharacters(in: CharacterSet(charactersIn: "_")))
        var words: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let startsWord = character.isUppercase && current.count > 0
                && ((previous?.isLowercase ?? false) || (previous?.isNumber ?? false)
                    || (next?.isLowercase ?? false))
            if startsWord || character == "_" || character == " " {
                if !current.isEmpty { words.append(current) }
                current = character == "_" || character == " " ? "" : String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.joined(separator: " ")
    }
}
