import Foundation

public extension JSONDecoder {
    /// Decoder for daemon payloads: ISO 8601 timestamps with or without
    /// fractional seconds (FastAPI emits fractional).
    static var reachyDaemon: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            if let date = (try? Date(string, strategy: fractional)) ?? (try? Date(string, strategy: .iso8601)) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO 8601 date: \(string)"
            )
        }
        return decoder
    }
}
