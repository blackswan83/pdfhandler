//
//  PDFService.swift
//  PDFHandler
//
//  PDF document parsing and content extraction
//

import Foundation
import PDFKit
import AppKit

actor PDFService {

    // MARK: - Document Analysis

    func analyzeDocument(_ pdf: PDFDocument) -> DocumentMetadata {
        let pageCount = pdf.pageCount

        // Check if document has selectable text
        var hasText = false
        var totalTextLength = 0

        for i in 0..<min(pageCount, 5) { // Check first 5 pages
            if let page = pdf.page(at: i),
               let text = page.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasText = true
                totalTextLength += text.count
            }
        }

        // Determine if it's likely a scanned document
        let isScanned = !hasText || (totalTextLength < 100 && pageCount > 0)

        // Extract metadata from PDF attributes
        let attributes = pdf.documentAttributes ?? [:]

        return DocumentMetadata(
            title: attributes[PDFDocumentAttribute.titleAttribute] as? String,
            author: attributes[PDFDocumentAttribute.authorAttribute] as? String,
            subject: attributes[PDFDocumentAttribute.subjectAttribute] as? String,
            keywords: parseKeywords(attributes[PDFDocumentAttribute.keywordsAttribute]),
            creationDate: attributes[PDFDocumentAttribute.creationDateAttribute] as? Date,
            modificationDate: attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date,
            pageCount: pageCount,
            hasText: hasText,
            isScanned: isScanned
        )
    }

    // MARK: - Content Extraction

    func extractContent(from pdf: PDFDocument, options: ConversionOptions) async throws -> ParsedPDFContent {
        let metadata = analyzeDocument(pdf)
        var pages: [ParsedPage] = []

        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }

            let parsedPage = try await extractPageContent(
                page: page,
                pageNumber: pageIndex + 1,
                options: options
            )
            pages.append(parsedPage)
        }

        return ParsedPDFContent(
            pages: pages,
            metadata: metadata,
            requiresOCR: metadata.isScanned && options.performOCR
        )
    }

    private func extractPageContent(
        page: PDFPage,
        pageNumber: Int,
        options: ConversionOptions
    ) async throws -> ParsedPage {
        let rawText = page.string ?? ""
        var elements: [PageElement] = []
        var images: [PDFImage] = []

        // Extract text elements with structure detection
        if !rawText.isEmpty {
            elements = parseTextStructure(rawText)
        }

        // Extract images if requested
        if options.extractImages {
            images = extractImages(from: page, pageNumber: pageNumber)
        }

        // Extract links
        let links = extractLinks(from: page)
        for link in links {
            elements.append(.link(text: link.text, url: link.url))
        }

        return ParsedPage(
            pageNumber: pageNumber,
            elements: elements,
            images: images,
            rawText: rawText,
            ocrText: nil,
            ocrConfidence: nil
        )
    }

    // MARK: - Text Structure Detection

    private func parseTextStructure(_ text: String) -> [PageElement] {
        var elements: [PageElement] = []
        let lines = text.components(separatedBy: .newlines)

        var currentParagraph: [String] = []
        var inList = false
        var listItems: [String] = []
        var isNumberedList = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty {
                // End of paragraph
                if !currentParagraph.isEmpty {
                    let paragraphText = currentParagraph.joined(separator: " ")

                    // Check if it's a heading
                    if let heading = detectHeading(paragraphText) {
                        elements.append(heading)
                    } else {
                        elements.append(.paragraph(text: paragraphText))
                    }
                    currentParagraph = []
                }

                if inList {
                    if isNumberedList {
                        elements.append(.numberedList(items: listItems))
                    } else {
                        elements.append(.bulletList(items: listItems))
                    }
                    listItems = []
                    inList = false
                }
                continue
            }

            // Check for bullet list
            if let bulletItem = detectBulletItem(trimmedLine) {
                if inList && isNumberedList {
                    elements.append(.numberedList(items: listItems))
                    listItems = []
                }
                inList = true
                isNumberedList = false
                listItems.append(bulletItem)
                continue
            }

            // Check for numbered list
            if let numberedItem = detectNumberedItem(trimmedLine) {
                if inList && !isNumberedList {
                    elements.append(.bulletList(items: listItems))
                    listItems = []
                }
                inList = true
                isNumberedList = true
                listItems.append(numberedItem)
                continue
            }

            // Check for horizontal rule
            if isHorizontalRule(trimmedLine) {
                if !currentParagraph.isEmpty {
                    elements.append(.paragraph(text: currentParagraph.joined(separator: " ")))
                    currentParagraph = []
                }
                elements.append(.horizontalRule)
                continue
            }

            // Regular text line
            if inList {
                // Continuation of list item or end of list
                if trimmedLine.hasPrefix("  ") || trimmedLine.hasPrefix("\t") {
                    // Continuation of previous list item
                    if !listItems.isEmpty {
                        listItems[listItems.count - 1] += " " + trimmedLine.trimmingCharacters(in: .whitespaces)
                    }
                } else {
                    // End of list
                    if isNumberedList {
                        elements.append(.numberedList(items: listItems))
                    } else {
                        elements.append(.bulletList(items: listItems))
                    }
                    listItems = []
                    inList = false
                    currentParagraph.append(trimmedLine)
                }
            } else {
                currentParagraph.append(trimmedLine)
            }
        }

        // Handle remaining content
        if !currentParagraph.isEmpty {
            let paragraphText = currentParagraph.joined(separator: " ")
            if let heading = detectHeading(paragraphText) {
                elements.append(heading)
            } else {
                elements.append(.paragraph(text: paragraphText))
            }
        }

        if inList && !listItems.isEmpty {
            if isNumberedList {
                elements.append(.numberedList(items: listItems))
            } else {
                elements.append(.bulletList(items: listItems))
            }
        }

        return elements
    }

    private func detectHeading(_ text: String) -> PageElement? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Heuristics for heading detection:
        // 1. Short lines (typically < 100 chars)
        // 2. No ending punctuation (except ? or !)
        // 3. Title case or ALL CAPS
        // 4. Certain patterns (Chapter X, Section Y, etc.)

        guard trimmed.count < 100 else { return nil }
        guard !trimmed.hasSuffix(".") && !trimmed.hasSuffix(",") else { return nil }

        // Check for chapter/section patterns
        let chapterPattern = #"^(Chapter|Section|Part)\s+\d+"#
        if trimmed.range(of: chapterPattern, options: .regularExpression, range: nil, locale: nil) != nil {
            return .heading(level: 1, text: trimmed)
        }

        // Check for numbered headings (1. Title, 1.1 Subtitle)
        let numberedPattern = #"^\d+(\.\d+)*\.?\s+[A-Z]"#
        if trimmed.range(of: numberedPattern, options: .regularExpression) != nil {
            let dotCount = trimmed.prefix(10).filter { $0 == "." }.count
            let level = min(dotCount + 1, 6)
            return .heading(level: level, text: trimmed)
        }

        // All caps short text is likely a heading
        if trimmed.count < 50 && trimmed == trimmed.uppercased() && trimmed.contains(" ") {
            return .heading(level: 2, text: trimmed)
        }

        return nil
    }

    private func detectBulletItem(_ line: String) -> String? {
        let bulletPatterns = ["• ", "· ", "- ", "* ", "○ ", "■ ", "□ ", "► ", "‣ "]

        for pattern in bulletPatterns {
            if line.hasPrefix(pattern) {
                return String(line.dropFirst(pattern.count))
            }
        }

        return nil
    }

    private func detectNumberedItem(_ line: String) -> String? {
        let pattern = #"^(\d+[\.\)]\s+|[a-zA-Z][\.\)]\s+|[ivxIVX]+[\.\)]\s+)"#

        if let range = line.range(of: pattern, options: .regularExpression) {
            return String(line[range.upperBound...])
        }

        return nil
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        let patterns = ["---", "***", "___", "==="]

        for pattern in patterns {
            if stripped.hasPrefix(pattern) && stripped.count >= 3 {
                let char = pattern.first!
                return stripped.allSatisfy { $0 == char }
            }
        }

        return false
    }

    // MARK: - Image Extraction

    private func extractImages(from page: PDFPage, pageNumber: Int) -> [PDFImage] {
        var images: [PDFImage] = []

        // Get page dictionary and resources
        // Note: This requires accessing the CGPDFPage directly
        guard let cgPage = page.pageRef else { return images }

        if let resources = cgPage.dictionary?["Resources"],
           case let .dictionary(resourceDict) = resources,
           let xObject = resourceDict["XObject"],
           case let .dictionary(xObjectDict) = xObject {

            var imageIndex = 0
            for (_, value) in xObjectDict {
                if case let .stream(stream) = value {
                    if let subtype = stream.dictionary?["Subtype"],
                       case let .name(name) = subtype,
                       name == "Image" {

                        // Extract image bounds (approximate)
                        let bounds = page.bounds(for: .mediaBox)

                        let pdfImage = PDFImage(
                            pageNumber: pageNumber,
                            imageIndex: imageIndex,
                            bounds: bounds,
                            imageData: nil // Will be extracted during conversion
                        )
                        images.append(pdfImage)
                        imageIndex += 1
                    }
                }
            }
        }

        return images
    }

    // Alternative simpler image extraction using PDFKit
    func extractImagesSimple(from page: PDFPage, pageNumber: Int) -> [NSImage] {
        var images: [NSImage] = []

        // Render the page to find image regions
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0 // Higher resolution

        let size = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )

        let image = NSImage(size: size)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: size))

            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)

            page.draw(with: .mediaBox, to: context)
        }

        image.unlockFocus()
        images.append(image)

        return images
    }

    // MARK: - Link Extraction

    private func extractLinks(from page: PDFPage) -> [(text: String, url: String)] {
        var links: [(text: String, url: String)] = []

        for annotation in page.annotations {
            if let linkAnnotation = annotation as? PDFAnnotation,
               linkAnnotation.type == "Link" {

                if let action = linkAnnotation.action as? PDFActionURL,
                   let url = action.url {
                    // Try to get the text under the annotation
                    let bounds = linkAnnotation.bounds
                    let selection = page.selection(for: bounds)
                    let text = selection?.string ?? url.absoluteString

                    links.append((text: text, url: url.absoluteString))
                }
            }
        }

        return links
    }

    // MARK: - Table Detection

    func detectTables(in text: String) -> [Table] {
        var tables: [Table] = []

        // Look for patterns that indicate tabular data
        let lines = text.components(separatedBy: .newlines)
        var potentialTableLines: [String] = []
        var inTable = false

        for line in lines {
            let tabCount = line.filter { $0 == "\t" }.count
            let pipeCount = line.filter { $0 == "|" }.count

            // Heuristic: lines with multiple tabs or pipes might be table rows
            if tabCount >= 2 || pipeCount >= 2 {
                if !inTable {
                    inTable = true
                    potentialTableLines = []
                }
                potentialTableLines.append(line)
            } else if inTable {
                // End of potential table
                if potentialTableLines.count >= 2 {
                    if let table = parseTableLines(potentialTableLines) {
                        tables.append(table)
                    }
                }
                inTable = false
                potentialTableLines = []
            }
        }

        // Handle table at end of text
        if inTable && potentialTableLines.count >= 2 {
            if let table = parseTableLines(potentialTableLines) {
                tables.append(table)
            }
        }

        return tables
    }

    private func parseTableLines(_ lines: [String]) -> Table? {
        guard !lines.isEmpty else { return nil }

        // Determine delimiter (tab or pipe)
        let firstLine = lines[0]
        let delimiter: Character = firstLine.contains("|") ? "|" : "\t"

        var rows: [[String]] = []

        for line in lines {
            let cells = line
                .split(separator: delimiter, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            if !cells.isEmpty {
                rows.append(cells)
            }
        }

        guard rows.count >= 2 else { return nil }

        // First row is likely headers
        let headers = rows[0]
        let dataRows = Array(rows.dropFirst())

        // Determine if table is complex (irregular columns, merged cells, etc.)
        let columnCounts = rows.map { $0.count }
        let isComplex = Set(columnCounts).count > 1

        return Table(
            headers: headers,
            rows: dataRows,
            isComplex: isComplex
        )
    }

    // MARK: - Utilities

    private func parseKeywords(_ value: Any?) -> [String] {
        if let keywords = value as? [String] {
            return keywords
        } else if let keywordString = value as? String {
            return keywordString
                .components(separatedBy: CharacterSet(charactersIn: ",;"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return []
    }
}

// MARK: - CGPDFDictionary Extensions

extension CGPDFDictionaryRef {
    subscript(key: String) -> PDFObject? {
        var object: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(self, key, &object),
              let obj = object else {
            return nil
        }
        return PDFObject(obj)
    }
}

enum PDFObject {
    case null
    case boolean(Bool)
    case integer(Int)
    case real(CGFloat)
    case name(String)
    case string(String)
    case array([PDFObject])
    case dictionary([String: PDFObject])
    case stream(PDFStream)

    init(_ object: CGPDFObjectRef) {
        let type = CGPDFObjectGetType(object)

        switch type {
        case .null:
            self = .null

        case .boolean:
            var value: CGPDFBoolean = 0
            CGPDFObjectGetValue(object, .boolean, &value)
            self = .boolean(value != 0)

        case .integer:
            var value: CGPDFInteger = 0
            CGPDFObjectGetValue(object, .integer, &value)
            self = .integer(value)

        case .real:
            var value: CGPDFReal = 0
            CGPDFObjectGetValue(object, .real, &value)
            self = .real(value)

        case .name:
            var value: UnsafePointer<CChar>?
            CGPDFObjectGetValue(object, .name, &value)
            self = .name(value.map { String(cString: $0) } ?? "")

        case .string:
            var value: CGPDFStringRef?
            CGPDFObjectGetValue(object, .string, &value)
            if let str = value,
               let cfString = CGPDFStringCopyTextString(str) {
                self = .string(cfString as String)
            } else {
                self = .string("")
            }

        case .array:
            var value: CGPDFArrayRef?
            CGPDFObjectGetValue(object, .array, &value)
            if let arr = value {
                var objects: [PDFObject] = []
                let count = CGPDFArrayGetCount(arr)
                for i in 0..<count {
                    var obj: CGPDFObjectRef?
                    if CGPDFArrayGetObject(arr, i, &obj), let o = obj {
                        objects.append(PDFObject(o))
                    }
                }
                self = .array(objects)
            } else {
                self = .array([])
            }

        case .dictionary:
            var value: CGPDFDictionaryRef?
            CGPDFObjectGetValue(object, .dictionary, &value)
            if let dict = value {
                self = .dictionary(PDFObject.parseDictionary(dict))
            } else {
                self = .dictionary([:])
            }

        case .stream:
            var value: CGPDFStreamRef?
            CGPDFObjectGetValue(object, .stream, &value)
            if let stream = value {
                self = .stream(PDFStream(stream))
            } else {
                self = .stream(PDFStream())
            }

        @unknown default:
            self = .null
        }
    }

    static func parseDictionary(_ dict: CGPDFDictionaryRef) -> [String: PDFObject] {
        var result: [String: PDFObject] = [:]

        CGPDFDictionaryApplyBlock(dict, { key, object, _ in
            let keyString = String(cString: key)
            result[keyString] = PDFObject(object)
            return true
        }, nil)

        return result
    }
}

struct PDFStream {
    var dictionary: [String: PDFObject]?
    var data: Data?

    init() {
        self.dictionary = nil
        self.data = nil
    }

    init(_ stream: CGPDFStreamRef) {
        if let dict = CGPDFStreamGetDictionary(stream) {
            self.dictionary = PDFObject.parseDictionary(dict)
        }

        var format: CGPDFDataFormat = .raw
        if let data = CGPDFStreamCopyData(stream, &format) {
            self.data = data as Data
        }
    }
}
