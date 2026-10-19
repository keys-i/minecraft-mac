import Foundation
import zlib

struct NBT {
    private let data: Data
    private var offset = 0
    private var items = 0

    static func read(_ source: Data) throws -> [String: Any] {
        var data = source
        if data.starts(with:[0x1F,0x8B]) {
            guard data.count >= 18, data.count <= 16*1024*1024 else { throw AssetError.model }
            let expected = data.suffix(4).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset*8)) }
            guard expected > 0, expected <= 32*1024*1024 else { throw AssetError.model }
            var output = Data(count:expected)
            let count = data.count
            let valid = output.withUnsafeMutableBytes { destination in
                data.withUnsafeBytes { source in
                    var stream = z_stream()
                    stream.next_in = UnsafeMutablePointer(mutating:source.bindMemory(to:Bytef.self).baseAddress!)
                    stream.avail_in = uInt(count)
                    stream.next_out = destination.bindMemory(to:Bytef.self).baseAddress!
                    stream.avail_out = uInt(expected)
                    guard inflateInit2_(&stream,MAX_WBITS+16,zlibVersion(),Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return false }
                    defer { inflateEnd(&stream) }
                    return inflate(&stream,Z_FINISH) == Z_STREAM_END && stream.total_out == expected && stream.avail_in == 0
                }
            }
            guard valid else { throw AssetError.model }
            data = output
        }
        guard data.count <= 32*1024*1024 else { throw AssetError.model }
        var reader = NBT(data:data)
        guard try reader.integer(1) == 10 else { throw AssetError.model }
        _ = try reader.string()
        guard let result = try reader.value(10,depth:0) as? [String: Any], reader.offset == data.count else { throw AssetError.model }
        return result
    }

    private mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= data.count-offset else { throw AssetError.model }
        defer { offset += count }
        return data.subdata(in:offset..<(offset+count))
    }

    private mutating func integer(_ count: Int) throws -> UInt64 {
        try bytes(count).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    private mutating func length() throws -> Int {
        let count = Int(Int32(bitPattern:UInt32(try integer(4))))
        guard count >= 0, count <= 1_000_000 else { throw AssetError.model }
        return count
    }

    private mutating func string() throws -> String {
        let size = Int(try integer(2))
        guard let string = String(data:try bytes(size),encoding:.utf8) else { throw AssetError.model }
        return string
    }

    private mutating func value(_ type: Int, depth: Int) throws -> Any {
        items += 1
        guard depth < 64, items <= 1_000_000 else { throw AssetError.model }
        switch type {
        case 1: return Int(Int8(bitPattern:UInt8(try integer(1))))
        case 2: return Int(Int16(bitPattern:UInt16(try integer(2))))
        case 3: return Int(Int32(bitPattern:UInt32(try integer(4))))
        case 4: return Int64(bitPattern:try integer(8))
        case 5: return Float(bitPattern:UInt32(try integer(4)))
        case 6: return Double(bitPattern:try integer(8))
        case 7: return try bytes(length())
        case 8: return try string()
        case 9:
            let type = Int(try integer(1)), count = try length()
            guard type != 0 || count == 0 else { throw AssetError.model }
            return try (0..<count).map { _ in try value(type,depth:depth+1) }
        case 10:
            var result: [String: Any] = [:]
            while true {
                let type = Int(try integer(1))
                if type == 0 { return result }
                let name = try string()
                result[name] = try value(type,depth:depth+1)
            }
        case 11: return try (0..<length()).map { _ in Int(Int32(bitPattern:UInt32(try integer(4)))) }
        case 12: return try (0..<length()).map { _ in Int64(bitPattern:try integer(8)) }
        default: throw AssetError.model
        }
    }
}
