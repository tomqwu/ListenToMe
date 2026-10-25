import Foundation

/// One stored passage vector, quantized to 8 bits per dimension with a per-vector scale. A
/// 300-dimension vector costs about 310 bytes, so a year of meetings stays a few megabytes.
struct StoredChunkVector: Sendable, Equatable {
    let ordinal: Int
    let fingerprint: UInt64
    let model: String
    let scale: Float
    let values: [Int8]

    init(ordinal: Int, model: String, scale: Float, values: [Int8], fingerprint: UInt64 = 0) {
        self.fingerprint = fingerprint
        self.ordinal = ordinal; self.model = model; self.scale = scale; self.values = values
    }

    init(ordinal: Int, vector: HistoryVector, fingerprint: UInt64 = 0) {
        let peak = vector.values.reduce(Float(0)) { max($0, abs($1)) }
        let scale = peak > 0 ? 127 / peak : 1
        self.init(ordinal: ordinal, model: vector.model, scale: scale,
                  values: vector.values.map { Int8(clamping: Int(($0 * scale).rounded())) }, fingerprint: fingerprint)
    }

    /// Cosine similarity with a unit query vector (stored vectors were unit length before
    /// quantization, so dividing by the scale restores them).
    func similarity(_ query: [Float]) -> Float {
        guard query.count == values.count, scale > 0 else { return 0 }
        var dot: Float = 0
        for index in values.indices { dot += Float(values[index]) * query[index] }
        return dot / scale
    }

    var byteCount: Int { values.count + model.utf8.count + 24 }
}

/// The vectors of one conversation and the fingerprint of the text they were computed from.
struct StoredRecordVectors: Sendable, Equatable {
    let fingerprint: UInt64
    let chunks: [StoredChunkVector]
    var byteCount: Int { chunks.reduce(16) { $0 + $1.byteCount } }
}

/// A compact binary encoding: JSON would triple the size and the decoding time of every search.
/// Layout: "LTMI", format byte, fingerprint (UInt64 LE), count (UInt32 LE), then per chunk the
/// ordinal (UInt32), passage fingerprint (UInt64), model tag (UInt8 length + UTF-8), scale (Float32 bits), dimension (UInt16)
/// and that many Int8 values.
enum HistoryIndexFile {
    static let magic = Array("LTMI".utf8)
    static let format: UInt8 = 2

    static func encode(_ record: StoredRecordVectors) -> Data {
        var data = Data(magic)
        data.append(format)
        append(record.fingerprint, to: &data)
        append(UInt32(record.chunks.count), to: &data)
        for chunk in record.chunks {
            append(UInt32(chunk.ordinal), to: &data)
            append(chunk.fingerprint, to: &data)
            let tag = Array(chunk.model.utf8.prefix(255))
            data.append(UInt8(tag.count))
            data.append(contentsOf: tag)
            append(chunk.scale.bitPattern, to: &data)
            append(UInt16(chunk.values.count), to: &data)
            data.append(contentsOf: chunk.values.map { UInt8(bitPattern: $0) })
        }
        return data
    }

    /// Nil for anything that is not a complete file in this format: a damaged file is rebuilt,
    /// never trusted.
    static func decode(_ data: Data) -> StoredRecordVectors? {
        var reader = Reader(bytes: [UInt8](data))
        guard reader.take(4) == magic, reader.byte() == format,
              let fingerprint = reader.integer(UInt64.self),
              let count = reader.integer(UInt32.self) else { return nil }
        var chunks: [StoredChunkVector] = []
        for _ in 0..<count {
            guard let ordinal = reader.integer(UInt32.self),
                  let passageFingerprint = reader.integer(UInt64.self), let length = reader.byte(),
                  let tagBytes = reader.take(Int(length)), let model = String(bytes: tagBytes, encoding: .utf8),
                  let scaleBits = reader.integer(UInt32.self), let dimension = reader.integer(UInt16.self),
                  let raw = reader.take(Int(dimension)) else { return nil }
            chunks.append(StoredChunkVector(ordinal: Int(ordinal), model: model, scale: Float(bitPattern: scaleBits),
                                            values: raw.map { Int8(bitPattern: $0) }, fingerprint: passageFingerprint))
        }
        return reader.atEnd ? StoredRecordVectors(fingerprint: fingerprint, chunks: chunks) : nil
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        var atEnd: Bool { offset == bytes.count }

        mutating func take(_ count: Int) -> [UInt8]? {
            guard count >= 0, offset + count <= bytes.count else { return nil }
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }

        mutating func byte() -> UInt8? { take(1)?.first }

        mutating func integer<T: FixedWidthInteger>(_ type: T.Type) -> T? {
            guard let raw = take(MemoryLayout<T>.size) else { return nil }
            return raw.reversed().reduce(T(0)) { ($0 << 8) | T($1) }
        }
    }
}
