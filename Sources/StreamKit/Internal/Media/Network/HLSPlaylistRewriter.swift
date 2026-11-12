import Foundation

enum HLSPlaylistRewriter {
    static func rewrite(_ data: Data, playlistURL: URL) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PlaybackFailure(code: .unsupportedFormat, message: "The media playlist is not valid UTF-8.")
        }

        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                lines.append(line)
                continue
            }
            if trimmed.hasPrefix("#") {
                lines.append(try rewriteURIAttributes(in: line, baseURL: playlistURL))
                continue
            }
            if let rewritten = try rewriteURL(trimmed, baseURL: playlistURL) {
                lines.append(line.replacingOccurrences(of: trimmed, with: rewritten))
            } else {
                lines.append(line)
            }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func rewriteURIAttributes(in line: String, baseURL: URL) throws -> String {
        guard let regex = try? NSRegularExpression(pattern: #"URI=\"([^\"]+)\""#) else { return line }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = regex.matches(in: line, range: range).reversed()
        var result = line
        for match in matches {
            guard let valueRange = Range(match.range(at: 1), in: result) else { continue }
            let value = String(result[valueRange])
            guard let rewritten = try rewriteURL(value, baseURL: baseURL) else { continue }
            result.replaceSubrange(valueRange, with: rewritten)
        }
        return result
    }

    private static func rewriteURL(_ value: String, baseURL: URL) throws -> String? {
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme)
        else { return nil }
        guard scheme == "https" else {
            throw PlaybackFailure(
                code: .authentication,
                message: "Authenticated media cannot load resources over an insecure connection."
            )
        }
        return try AuthenticatedMediaResourceLoader.assetURL(for: url).absoluteString
    }
}
