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
        var offset = 0
        let bytes = [UInt8](data)
        let count = bytes.count

        while offset + 30 < count {
            guard bytes[offset] == 0x50, bytes[offset+1] == 0x4B,
                  bytes[offset+2] == 0x03, bytes[offset+3] == 0x04 else { break }

            let compression = UInt16(bytes[offset+8]) | (UInt16(bytes[offset+9]) << 8)
            let compressedSize = Int(UInt32(bytes[offset+18]) | (UInt32(bytes[offset+19]) << 8)
                | (UInt32(bytes[offset+20]) << 16) | (UInt32(bytes[offset+21]) << 24))
            let uncompressedSize = Int(UInt32(bytes[offset+22]) | (UInt32(bytes[offset+23]) << 8)
                | (UInt32(bytes[offset+24]) << 16) | (UInt32(bytes[offset+25]) << 24))
            let filenameLen = Int(UInt16(bytes[offset+26]) | (UInt16(bytes[offset+27]) << 8))
            let extraLen = Int(UInt16(bytes[offset+28]) | (UInt16(bytes[offset+29]) << 8))

            let filenameStart = offset + 30
            let filenameEnd = filenameStart + filenameLen
            guard filenameEnd <= count else { break }

            let filenameBytes = Array(bytes[filenameStart..<filenameEnd])
            guard let filename = String(bytes: filenameBytes, encoding: .utf8) else {
                offset = filenameEnd + extraLen + compressedSize
                continue
            }

            let dataStart = filenameEnd + extraLen
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= count else { break }

            if !filename.hasSuffix("/") {
                let fileURL = destDir.appendingPathComponent(filename)
                let parentDir = fileURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

                let compressedData = Data(bytes[dataStart..<dataEnd])
                let fileData: Data
                if compression == 8 {
                    fileData = try (compressedData as NSData).decompressed(using: .zlib) as Data
                    _ = uncompressedSize
                } else {
                    fileData = compressedData
                }
                try fileData.write(to: fileURL)
            }

            offset = dataEnd
        }
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

        // Read spine HTML content now (before defer cleanup deletes unzipDir)
        let spineItems: [EPUBSpineItem] = result.spineHrefs.compactMap { href in
            let url = epubRoot.appendingPathComponent(href)
            guard let html = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return EPUBSpineItem(html: html, baseURL: url.deletingLastPathComponent())
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
