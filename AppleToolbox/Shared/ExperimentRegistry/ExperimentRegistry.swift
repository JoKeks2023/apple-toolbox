import Foundation

/// All experiments, one file per category (Registry+<Category>.swift).
enum ExperimentRegistry {
    static let all: [ExperimentDescriptor] = ExperimentCategory.allCases.flatMap { experiments(in: $0) }

    static func experiments(in category: ExperimentCategory) -> [ExperimentDescriptor] {
        switch category {
        case .security: security
        case .location: location
        case .sensors: sensors
        case .input: input
        case .connectivity: connectivity
        case .networking: networking
        case .nfc: nfc
        case .home: home
        case .camera: camera
        case .spatial: spatial
        case .audio: audio
        case .ai: ai
        case .maps: maps
        case .wallet: wallet
        case .health: health
        case .system: system
        case .platform: platform
        case .developer: developer
        }
    }

    static func descriptor(for id: String) -> ExperimentDescriptor? { all.first { $0.id == id } }
}
