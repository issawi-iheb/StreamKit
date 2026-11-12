//
//  MediaTrack.swift
//  StreamKit
//
//  Created by Iheb on 13/10/2026.
//

import Foundation

/// The type of media track available for selection.
public enum MediaTrackType: Sendable, Equatable {
    case audio
    case subtitle
}

/// A selectable audio or subtitle track.
public struct MediaTrack: Identifiable, Sendable, Equatable {
    /// Stable identifier within the currently loaded media item.
    public let id: String

    /// The track's type.
    public let type: MediaTrackType

    /// The track's display name, if available.
    public let name: String

    /// The language code, if available.
    public let languageCode: String?

    /// Creates a media track.
    public init(
        id: String,
        type: MediaTrackType,
        name: String,
        languageCode: String?
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.languageCode = languageCode
    }
}
