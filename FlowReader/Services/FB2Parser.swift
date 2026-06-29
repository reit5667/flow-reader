import Foundation

struct FB2Metadata {
    let title: String
    let author: String
    let coverData: Data?
}

struct FB2ParseResult {
    let metadata: FB2Metadata
    let html: String
    let tocItems: [TOCItem]
}

enum FB2ParserError: Error {
    case invalidFile
    case xmlParseError
}

final class FB2Parser: NSObject, XMLParserDelegate {

    func parse(fileURL: URL) throws -> FB2ParseResult {
        let data = try Data(contentsOf: fileURL)
        return try parseData(data)
    }

    // MARK: - State

    private var elementStack: [String] = []
    private var html = ""
    private var title = ""
    private var author = ""
    private var binaries: [String: Data] = [:]
    private var coverImageId: String?

    private var inTitleInfo = false
    private var inBookTitle = false
    private var inFirstName = false
    private var inLastName = false
    private var inBody = false
    private var inNote = false
    private var noteId: String?

    private var firstNameBuf = ""
    private var lastNameBuf = ""
    private var currentBinaryId: String?
    private var binaryBuf = ""

    // TOC tracking
    private var sectionDepth = 0
    private var sectionCounter = -1
    private var inSectionTitle = false
    private var sectionTitleRecorded = false
    private var sectionTitleBuf = ""
    private var tocItems: [TOCItem] = []

    private var parseError: Error?

    // MARK: - Parse

    private func parseData(_ data: Data) throws -> FB2ParseResult {
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()

        if let error = parseError { throw error }

        let coverData = coverImageId.flatMap { binaries[$0] }

        let fullHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { font-family: Georgia, serif; line-height: 1.6; padding: 16px; word-break: break-word; }
        h1, h2, h3 { font-weight: bold; margin: 1em 0 0.5em; }
        p { margin: 0.5em 0; text-indent: 1.5em; }
        em { font-style: italic; }
        strong { font-weight: bold; }
        .epigraph { margin: 1em 2em; font-style: italic; }
        .note-ref { font-size: 0.75em; vertical-align: super; }
        </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """

        return FB2ParseResult(
            metadata: FB2Metadata(title: title.isEmpty ? "Unknown" : title,
                                  author: author.isEmpty ? "Unknown" : author,
                                  coverData: coverData),
            html: fullHTML,
            tocItems: tocItems
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attrs: [String: String] = [:]) {
        let tag = localName(elementName)
        elementStack.append(tag)

        switch tag {
        case "title-info":
            inTitleInfo = true
        case "book-title" where inTitleInfo:
            inBookTitle = true
        case "first-name" where inTitleInfo:
            inFirstName = true
        case "last-name" where inTitleInfo:
            inLastName = true
        case "coverpage":
            break
        case "image" where elementStack.contains("coverpage"):
            let href = attrs["l:href"] ?? attrs["href"] ?? ""
            coverImageId = href.hasPrefix("#") ? String(href.dropFirst()) : href
        case "body":
            inBody = true
        case "section" where inBody:
            sectionDepth += 1
            if sectionDepth == 1 {
                sectionCounter += 1
                sectionTitleRecorded = false
                html += "<section id=\"fr-chapter-\(sectionCounter)\">"
            } else {
                html += "<section>"
            }
        case "title" where inBody:
            if sectionDepth == 1 && !sectionTitleRecorded {
                inSectionTitle = true
                sectionTitleBuf = ""
            }
            html += "<h2>"
        case "p" where inBody && !inNote:
            html += "<p>"
        case "emphasis" where inBody:
            html += "<em>"
        case "strong" where inBody:
            html += "<strong>"
        case "epigraph" where inBody:
            html += "<div class=\"epigraph\">"
        case "poem" where inBody:
            html += "<blockquote>"
        case "stanza" where inBody:
            html += "<p>"
        case "v" where inBody:
            break
        case "cite" where inBody:
            html += "<blockquote>"
        case "subtitle" where inBody:
            html += "<h3>"
        case "empty-line" where inBody:
            html += "<br>"
        case "a" where inBody:
            let href = attrs["l:href"] ?? attrs["href"] ?? ""
            let noteType = attrs["type"] ?? ""
            if noteType == "note" || href.hasPrefix("#") {
                inNote = true
                noteId = href.hasPrefix("#") ? String(href.dropFirst()) : href
                html += "<sup class=\"note-ref\">"
            } else {
                html += "<a href=\"\(escapeHTML(href))\">"
            }
        case "binary":
            if let id = attrs["id"] {
                currentBinaryId = id
                binaryBuf = ""
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentBinaryId != nil {
            binaryBuf += string
            return
        }

        if inBookTitle { title += string; return }
        if inFirstName { firstNameBuf += string; return }
        if inLastName { lastNameBuf += string; return }

        if inBody {
            if inSectionTitle { sectionTitleBuf += string }
            html += escapeHTML(string)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let tag = localName(elementName)
        _ = elementStack.popLast()

        switch tag {
        case "title-info":
            inTitleInfo = false
            let fn = firstNameBuf.trimmingCharacters(in: .whitespacesAndNewlines)
            let ln = lastNameBuf.trimmingCharacters(in: .whitespacesAndNewlines)
            author = [fn, ln].filter { !$0.isEmpty }.joined(separator: " ")
        case "book-title":
            inBookTitle = false
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        case "first-name":
            inFirstName = false
        case "last-name":
            inLastName = false
        case "body":
            inBody = false
        case "section":
            if inBody {
                sectionDepth -= 1
                html += "</section>"
            }
        case "title":
            if inBody {
                html += "</h2>"
                if inSectionTitle {
                    inSectionTitle = false
                    let t = sectionTitleBuf.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        tocItems.append(TOCItem(index: sectionCounter, title: t))
                        sectionTitleRecorded = true
                    }
                    sectionTitleBuf = ""
                }
            }
        case "p":
            if inBody && !inNote { html += "</p>" }
        case "emphasis":
            if inBody { html += "</em>" }
        case "strong":
            if inBody { html += "</strong>" }
        case "epigraph":
            if inBody { html += "</div>" }
        case "poem":
            if inBody { html += "</blockquote>" }
        case "stanza":
            if inBody { html += "</p>" }
        case "v":
            if inBody { html += "<br>" }
        case "cite":
            if inBody { html += "</blockquote>" }
        case "subtitle":
            if inBody { html += "</h3>" }
        case "a":
            if inNote {
                html += "</sup>"
                inNote = false
                noteId = nil
            } else if inBody {
                html += "</a>"
            }
        case "binary":
            if let id = currentBinaryId {
                let cleaned = binaryBuf.components(separatedBy: .whitespacesAndNewlines).joined()
                if let data = Data(base64Encoded: cleaned) {
                    binaries[id] = data
                }
                currentBinaryId = nil
                binaryBuf = ""
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        parseError = error
    }

    // MARK: - Helpers

    private func localName(_ name: String) -> String {
        name.components(separatedBy: ":").last ?? name
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
