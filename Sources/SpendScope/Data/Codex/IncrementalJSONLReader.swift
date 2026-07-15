import Foundation

struct JSONLLine: Equatable, Sendable {
    let data: Data
    let endOffset: Int64
}

struct JSONLReadBatch: Equatable, Sendable {
    let lines: [JSONLLine]
    let committedOffset: Int64
    let wasTruncated: Bool
}

enum IncrementalJSONLReaderError: Error, Equatable {
    case invalidChunkSize(Int)
    case invalidOffset(Int64)
    case invalidFileSize
    case offsetOverflow
}

struct IncrementalJSONLReader: Sendable {
    private let chunkSize: Int

    init(chunkSize: Int = 64 * 1_024) {
        self.chunkSize = chunkSize
    }

    func read(file url: URL, fromOffset requestedOffset: Int64) throws -> JSONLReadBatch {
        guard chunkSize > 0 else {
            throw IncrementalJSONLReaderError.invalidChunkSize(chunkSize)
        }
        guard requestedOffset >= 0 else {
            throw IncrementalJSONLReaderError.invalidOffset(requestedOffset)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes[.size] as? NSNumber)?.int64Value, size >= 0 else {
            throw IncrementalJSONLReaderError.invalidFileSize
        }
        guard size >= requestedOffset else {
            return JSONLReadBatch(lines: [], committedOffset: 0, wasTruncated: true)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(requestedOffset))

        var lines: [JSONLLine] = []
        var pending = Data()
        var absoluteChunkStart = requestedOffset
        var committedOffset = requestedOffset

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            var segmentStart = chunk.startIndex

            for index in chunk.indices where chunk[index] == 0x0A {
                pending.append(contentsOf: chunk[segmentStart..<index])
                let bytesThroughNewline = chunk.distance(from: chunk.startIndex, to: index) + 1
                let (endOffset, overflow) = absoluteChunkStart.addingReportingOverflow(Int64(bytesThroughNewline))
                guard !overflow else { throw IncrementalJSONLReaderError.offsetOverflow }

                lines.append(JSONLLine(data: pending, endOffset: endOffset))
                committedOffset = endOffset
                pending.removeAll(keepingCapacity: true)
                segmentStart = chunk.index(after: index)
            }

            pending.append(contentsOf: chunk[segmentStart..<chunk.endIndex])
            let (nextChunkStart, overflow) = absoluteChunkStart.addingReportingOverflow(Int64(chunk.count))
            guard !overflow else { throw IncrementalJSONLReaderError.offsetOverflow }
            absoluteChunkStart = nextChunkStart
        }

        return JSONLReadBatch(
            lines: lines,
            committedOffset: committedOffset,
            wasTruncated: false
        )
    }
}
