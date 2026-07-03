import Foundation

struct EPUBSpineItem {
    let html: String
    let baseURL: URL
}

struct EPUBMetadata {
    let title: String
    let author: String
    let coverData: Data?
    let spineItems: [EPUBSpineItem]
    let tocItems: [TOCItem]
}

enum EPUBParserError: Error {
    case notAnEPUB
    case missingOPF
    case missingSpine
    case xmlParseError
}

final class EPUBParser: NSObject {

    func parse(fileURL: URL) throws -> EPUBMetadata {
        let unzipDir = try unzip(epubURL: fileURL)
        defer { try? FileManager.default.removeItem(at: unzipDir) }

        let opfURL = try findOPF(in: unzipDir)
        return try parseOPF(opfURL: opfURL, epubRoot: opfURL.deletingLastPathComponent(), metadataOnly: false)
    }

    func parseMetadataOnly(fileURL: URL) throws -> EPUBMetadata {
        let unzipDir = try unzip(epubURL: fileURL)
        defer { try? FileManager.default.removeItem(at: unzipDir) }

        let opfURL = try findOPF(in: unzipDir)
        return try parseOPF(opfURL: opfURL, epubRoot: opfURL.deletingLastPathComponent(), metadataOnly: true)
    }

    // MARK: - Unzip

    private func unzip(epubURL: URL) throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        let data = try Data(contentsOf: epubURL)
        try extractZIP(data: data, to: dest)
        return dest
    }

    // MARK: - ZIP extraction (minimal PKZip reader)

    private func extractZIP(data: Data, to destDir: URL) throws {
        let bytes = [UInt8](data)
        let count = bytes.count

        // Parse Central Directory for correct sizes (handles data descriptors)
        guard let eocdPos = findEOCD(bytes: bytes, count: count) else { return }

        let cdOffset = int32LE(bytes, eocdPos + 16)
        let cdCount  = int16LE(bytes, eocdPos + 8)

        var cdPos = cdOffset
        for _ in 0..<cdCount {
            guard cdPos + 46 <= count,
                  bytes[cdPos] == 0x50, bytes[cdPos+1] == 0x4B,
                  bytes[cdPos+2] == 0x01, bytes[cdPos+3] == 0x02 else { break }

            let compression      = UInt16(bytes[cdPos+10]) | (UInt16(bytes[cdPos+11]) << 8)
            let compressedSize   = int32LE(bytes, cdPos + 20)
            let uncompressedSize = int32LE(bytes, cdPos + 24)
            let fnLen            = int16LE(bytes, cdPos + 28)
            let extraLen         = int16LE(bytes, cdPos + 30)
            let commentLen       = int16LE(bytes, cdPos + 32)
            let lhOffset         = int32LE(bytes, cdPos + 42)

            let fnStart = cdPos + 46
            let fnEnd   = fnStart + fnLen
            guard fnEnd <= count else { break }

            let fnBytes = Array(bytes[fnStart..<fnEnd])
            let filename = String(bytes: fnBytes, encoding: .utf8)
                        ?? String(bytes: fnBytes, encoding: .isoLatin1)
                        ?? ""

            cdPos += 46 + fnLen + extraLen + commentLen

            guard !filename.isEmpty, !filename.hasSuffix("/") else { continue }

            // Seek to local header to find actual data offset
            guard lhOffset + 30 <= count,
                  bytes[lhOffset] == 0x50, bytes[lhOffset+1] == 0x4B,
                  bytes[lhOffset+2] == 0x03, bytes[lhOffset+3] == 0x04 else { continue }

            let lhFnLen    = int16LE(bytes, lhOffset + 26)
            let lhExtraLen = int16LE(bytes, lhOffset + 28)
            let dataStart  = lhOffset + 30 + lhFnLen + lhExtraLen
            let dataEnd    = dataStart + compressedSize
            guard dataEnd <= count else { continue }

            let fileURL = destDir.appendingPathComponent(filename)
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let compressedData = Data(bytes[dataStart..<dataEnd])
            let fileData: Data
            if compression == 8 {
                fileData = try rawInflate(compressedData, outputSize: uncompressedSize)
            } else {
                fileData = compressedData
            }
            try fileData.write(to: fileURL)
        }
    }

    private func findEOCD(bytes: [UInt8], count: Int) -> Int? {
        var i = count - 22
        while i >= 0 {
            if bytes[i] == 0x50, bytes[i+1] == 0x4B, bytes[i+2] == 0x05, bytes[i+3] == 0x06 { return i }
            i -= 1
        }
        return nil
    }

    private func int32LE(_ b: [UInt8], _ o: Int) -> Int {
        Int(UInt32(b[o]) | (UInt32(b[o+1]) << 8) | (UInt32(b[o+2]) << 16) | (UInt32(b[o+3]) << 24))
    }

    private func int16LE(_ b: [UInt8], _ o: Int) -> Int {
        Int(UInt16(b[o]) | (UInt16(b[o+1]) << 8))
    }

    // MARK: - Raw deflate (ZIP method 8, no zlib header/checksum wrapper)

    private func rawInflate(_ compressed: Data, outputSize: Int) throws -> Data {
        guard !compressed.isEmpty, outputSize > 0 else { return Data() }

        var output = Data(count: outputSize)
        var status = Int32(Z_DATA_ERROR)

        compressed.withUnsafeBytes { src in
            guard let srcBase = src.baseAddress else { return }
            output.withUnsafeMutableBytes { dst in
                guard let dstBase = dst.baseAddress else { return }
                var strm = z_stream()
                strm.next_in  = UnsafeMutablePointer<Bytef>(mutating: srcBase.assumingMemoryBound(to: Bytef.self))
                strm.avail_in = uInt(compressed.count)
                strm.next_out = dstBase.assumingMemoryBound(to: Bytef.self)
                strm.avail_out = uInt(outputSize)
                guard inflateInit2_(&strm, -15, "1.2.11", Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return }
                status = inflate(&strm, Z_FINISH)
                inflateEnd(&strm)
            }
        }

        guard status == Z_STREAM_END else {
            throw EPUBParserError.xmlParseError
        }
        return output
    }

    // MARK: - OPF location

    private func findOPF(in dir: URL) throws -> URL {
        let containerURL = dir.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw EPUBParserError.notAnEPUB
        }

        let parser = ContainerXMLParser()
        guard let opfRelPath = try parser.parse(url: containerURL) else {
            throw EPUBParserError.missingOPF
        }

        return dir.appendingPathComponent(opfRelPath)
    }

    // MARK: - OPF parsing

    private func parseOPF(opfURL: URL, epubRoot: URL, metadataOnly: Bool) throws -> EPUBMetadata {
        let parser = OPFParser()
        let result = try parser.parse(url: opfURL)

        var coverData: Data?
        if let coverHref = result.coverHref {
            coverData = try? Data(contentsOf: epubRoot.appendingPathComponent(coverHref))
        }

        if metadataOnly {
            return EPUBMetadata(
                title: result.title.isEmpty ? "Unknown" : result.title,
                author: result.author.isEmpty ? "Unknown" : result.author,
                coverData: coverData,
                spineItems: [],
                tocItems: []
            )
        }

        // Read spine HTML content now (before defer cleanup deletes unzipDir).
        // Images are embedded as base64 data URIs so no baseURL is needed after cleanup.
        let spineItems: [EPUBSpineItem] = result.spineHrefs.compactMap { href in
            let url = epubRoot.appendingPathComponent(href)
            guard let html = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let baseDir = url.deletingLastPathComponent()
            let embeddedHTML = embedImages(in: html, baseDir: baseDir)
            return EPUBSpineItem(html: embeddedHTML, baseURL: baseDir)
        }

        // Parse NCX for TOC
        var tocItems: [TOCItem] = []
        if let ncxHref = result.ncxHref {
            let ncxURL = epubRoot.appendingPathComponent(ncxHref)
            tocItems = (try? NCXParser().parse(url: ncxURL, spineHrefs: result.spineHrefs)) ?? []
        }
        if tocItems.isEmpty {
            tocItems = spineItems.enumerated().map { TOCItem(index: $0.offset, title: "Глава \($0.offset + 1)") }
        }

        return EPUBMetadata(
            title: result.title.isEmpty ? "Unknown" : result.title,
            author: result.author.isEmpty ? "Unknown" : result.author,
            coverData: coverData,
            spineItems: spineItems,
            tocItems: tocItems
        )
    }

    // Replace relative img src with base64 data URIs so images survive temp dir cleanup.
    private func embedImages(in html: String, baseDir: URL) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "src=[\"']([^\"']+)[\"']",
            options: .caseInsensitive
        ) else { return html }

        let nsHtml = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
        let mutableResult = NSMutableString(string: html)
        var lengthDelta = 0

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let originalRange = match.range(at: 1)
            let srcValue = nsHtml.substring(with: originalRange)

            if srcValue.hasPrefix("data:") || srcValue.hasPrefix("http") { continue }

            let cleanSrc = (srcValue.components(separatedBy: "#").first ?? srcValue)
                .removingPercentEncoding ?? srcValue
            if cleanSrc.isEmpty { continue }

            let imageURL = baseDir.appendingPathComponent(cleanSrc)
            guard let imageData = try? Data(contentsOf: imageURL) else { continue }

            let ext = imageURL.pathExtension.lowercased()
            let mimeType: String
            switch ext {
            case "png":  mimeType = "image/png"
            case "gif":  mimeType = "image/gif"
            case "svg":  mimeType = "image/svg+xml"
            case "webp": mimeType = "image/webp"
            default:     mimeType = "image/jpeg"
            }

            let dataURI = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
            let adjustedRange = NSRange(location: originalRange.location + lengthDelta,
                                        length: originalRange.length)
            mutableResult.replaceCharacters(in: adjustedRange, with: dataURI)
            lengthDelta += dataURI.utf16.count - originalRange.length
        }

        return mutableResult as String
    }
}

// MARK: - container.xml parser

private final class ContainerXMLParser: NSObject, XMLParserDelegate {
    private var opfPath: String?
    private var parseError: Error?

    func parse(url: URL) throws -> String? {
        let data = try Data(contentsOf: url)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
        if let error = parseError { throw error }
        return opfPath
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "rootfile" {
            opfPath = attributes["full-path"]
        }
    }
}

// MARK: - OPF parser result

private struct OPFResult {
    var title: String = ""
    var author: String = ""
    var coverHref: String?
    var spineHrefs: [String] = []
    var ncxHref: String?
}

private final class OPFParser: NSObject, XMLParserDelegate {
    private var result = OPFResult()
    private var manifest: [String: (href: String, mediaType: String)] = [:]
    private var spineIdRefs: [String] = []
    private var coverManifestId: String?

    private var currentElement = ""
    private var currentText = ""
    private var parseError: Error?

    func parse(url: URL) throws -> OPFResult {
        let data = try Data(contentsOf: url)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
        if let error = parseError { throw error }

        result.spineHrefs = spineIdRefs.compactMap { manifest[$0]?.href }

        if let coverId = coverManifestId {
            result.coverHref = manifest[coverId]?.href
        }

        // Find NCX by media-type
        for (_, item) in manifest {
            if item.mediaType == "application/x-dtbncx+xml" || item.href.hasSuffix(".ncx") {
                result.ncxHref = item.href
                break
            }
        }

        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attrs: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "item":
            if let id = attrs["id"], let href = attrs["href"] {
                let mediaType = attrs["media-type"] ?? ""
                manifest[id] = (href: href, mediaType: mediaType)
                if id == "cover-image" || id == "cover" || attrs["properties"] == "cover-image" {
                    coverManifestId = id
                }
            }
        case "itemref":
            if let idref = attrs["idref"] {
                spineIdRefs.append(idref)
            }
        case "meta":
            if attrs["name"] == "cover", let content = attrs["content"] {
                coverManifestId = content
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "dc:title", "title":
            if result.title.isEmpty { result.title = text }
        case "dc:creator", "creator":
            if result.author.isEmpty { result.author = text }
        default:
            break
        }
        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

// MARK: - NCX parser

private final class NCXParser: NSObject, XMLParserDelegate {
    private struct NavPoint {
        var title: String = ""
        var src: String = ""
    }

    private var navPoints: [NavPoint] = []
    private var currentNavPoint: NavPoint?
    private var inNavLabel = false
    private var inText = false
    private var textBuf = ""

    func parse(url: URL, spineHrefs: [String]) throws -> [TOCItem] {
        let data = try Data(contentsOf: url)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()

        return navPoints.enumerated().compactMap { (i, np) in
            guard !np.title.isEmpty else { return nil }
            // Match src filename to spine index
            let srcFile = np.src.components(separatedBy: "#").first ?? np.src
            let srcFilename = (srcFile as NSString).lastPathComponent
            let spineIndex = spineHrefs.firstIndex(where: { href in
                let hrefFilename = (href as NSString).lastPathComponent
                return hrefFilename == srcFilename
            }) ?? i
            return TOCItem(index: spineIndex, title: np.title)
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attrs: [String: String] = [:]) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        switch tag {
        case "navPoint":
            currentNavPoint = NavPoint()
        case "navLabel":
            inNavLabel = true
        case "text" where inNavLabel:
            inText = true
            textBuf = ""
        case "content":
            currentNavPoint?.src = attrs["src"] ?? ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { textBuf += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        switch tag {
        case "navLabel":
            inNavLabel = false
        case "text":
            inText = false
            currentNavPoint?.title = textBuf.trimmingCharacters(in: .whitespacesAndNewlines)
            textBuf = ""
        case "navPoint":
            if let np = currentNavPoint, !np.title.isEmpty {
                navPoints.append(np)
            }
            currentNavPoint = nil
        default:
            break
        }
    }
}
