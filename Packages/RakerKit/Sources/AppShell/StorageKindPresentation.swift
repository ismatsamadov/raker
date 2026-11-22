import DesignSystem
import ScanEngine
import SwiftUI

extension StorageKind {
    var title: String {
        switch self {
        case .apps: "Apps"
        case .installers: "Installers"
        case .archives: "Archives"
        case .media: "Photos, Video & Audio"
        case .documents: "Documents"
        case .developer: "Developer"
        case .other: "Other"
        }
    }

    var color: Color {
        switch self {
        case .apps: Palette.apps
        case .installers: Palette.installers
        case .archives: Palette.archives
        case .media: Palette.media
        case .documents: Palette.documents
        case .developer: Palette.developer
        case .other: Palette.other
        }
    }

    var symbol: String {
        switch self {
        case .apps: "app.dashed"
        case .installers: "shippingbox"
        case .archives: "archivebox"
        case .media: "photo.on.rectangle"
        case .documents: "doc.text"
        case .developer: "hammer"
        case .other: "square.grid.2x2"
        }
    }
}
