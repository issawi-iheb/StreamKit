import Foundation

struct AuthenticatedMediaByteRange: Equatable, Sendable {
    let start: Int64
    let end: Int64?

    var headerValue: String {
        if let end {
            "bytes=\(start)-\(end)"
        } else {
            "bytes=\(start)-"
        }
    }

    static func make(
        requestedOffset: Int64,
        currentOffset: Int64,
        requestedLength: Int,
        requestsAllDataToEndOfResource: Bool
    ) throws -> Self? {
        let start = max(0, max(currentOffset, requestedOffset))

        if requestsAllDataToEndOfResource {
            return start > 0 ? Self(start: start, end: nil) : nil
        }

        guard requestedLength > 0,
              let length = Int64(exactly: requestedLength)
        else { return nil }

        let (end, overflow) = start.addingReportingOverflow(length - 1)
        guard !overflow else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "AVFoundation requested an invalid media byte range."
            )
        }
        return Self(start: start, end: end)
    }

    func validate(response: HTTPURLResponse) throws -> AuthenticatedMediaByteRangeResponse {
        guard response.statusCode == 206,
              let contentRange = Self.parseContentRange(
                response.value(forHTTPHeaderField: "Content-Range")
              ),
              contentRange.start == start,
              contentRange.end >= contentRange.start
        else {
            throw Self.invalidRangeResponse()
        }

        if let end {
            guard contentRange.end <= end else {
                throw Self.invalidRangeResponse()
            }
            if contentRange.end < end {
                guard let totalLength = contentRange.totalLength,
                      contentRange.end == totalLength - 1
                else {
                    throw Self.invalidRangeResponse()
                }
            }
        } else if let totalLength = contentRange.totalLength,
                  contentRange.end != totalLength - 1 {
            throw Self.invalidRangeResponse()
        }

        let (difference, subtractOverflow) = contentRange.end
            .subtractingReportingOverflow(contentRange.start)
        let (bodyLength, addOverflow) = difference.addingReportingOverflow(1)
        guard !subtractOverflow, !addOverflow else {
            throw Self.invalidRangeResponse()
        }
        return AuthenticatedMediaByteRangeResponse(bodyLength: bodyLength)
    }

    static func validateFullResponse(_ response: HTTPURLResponse) throws {
        guard response.statusCode == 200 else {
            throw invalidRangeResponse()
        }
    }

    private static func parseContentRange(
        _ value: String?
    ) -> (start: Int64, end: Int64, totalLength: Int64?)? {
        guard let value else { return nil }
        let parts = value.split(separator: " ", maxSplits: 1)
        guard parts.count == 2,
              parts[0].lowercased() == "bytes"
        else { return nil }

        let rangeAndTotal = parts[1].split(separator: "/", maxSplits: 1)
        guard rangeAndTotal.count == 2 else { return nil }
        let bounds = rangeAndTotal[0].split(separator: "-", maxSplits: 1)
        guard bounds.count == 2,
              let start = Int64(bounds[0]),
              let end = Int64(bounds[1]),
              end >= start
        else { return nil }

        let totalLength = rangeAndTotal[1] == "*" ? nil : Int64(rangeAndTotal[1])
        if let totalLength, (totalLength <= 0 || end >= totalLength) {
            return nil
        }
        return (start, end, totalLength)
    }

    private static func invalidRangeResponse() -> PlaybackFailure {
        PlaybackFailure(
            code: .network,
            message: "The media server returned a response that did not match the requested byte range."
        )
    }
}

struct AuthenticatedMediaByteRangeResponse: Equatable, Sendable {
    let bodyLength: Int64

    func remainingBytes(after deliveredBytes: Int64) -> Int64 {
        max(0, bodyLength - deliveredBytes)
    }
}
