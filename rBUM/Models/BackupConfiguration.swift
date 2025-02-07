//
//  BackupConfiguration.swift
//  rBUM
//
//  First created: 6 February 2025
//  Last updated: 6 February 2025
//
//  First created: 6 February 2025
//  Last updated: 6 February 2025
//
import Core
import Foundation

/// Represents a backup configuration
struct BackupConfiguration: Codable, Equatable, Identifiable {
    /// Unique identifier for the configuration
    let id: UUID

    /// Name of the backup configuration
    let name: String

    /// Optional description of what this backup does
    let description: String?

    /// Whether this backup configuration is enabled
    let enabled: Bool

    /// Schedule for running the backup
    let schedule: BackupSchedule?

    /// Source locations to backup
    let sources: [BackupSource]

    /// Paths to exclude from backup
    let excludedPaths: [String]

    /// Tags for organizing backups
    let tags: [BackupTag]

    /// Creates a new backup configuration
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - name: Name of the backup configuration
    ///   - description: Optional description
    ///   - enabled: Whether the backup is enabled
    ///   - schedule: Optional backup schedule
    ///   - sources: Source locations to backup
    ///   - excludedPaths: Paths to exclude
    ///   - tags: Tags for organization
    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        enabled: Bool = true,
        schedule: BackupSchedule? = nil,
        sources: [BackupSource] = [],
        excludedPaths: [String] = [],
        tags: [BackupTag] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.enabled = enabled
        self.schedule = schedule
        self.sources = sources
        self.excludedPaths = excludedPaths
        self.tags = tags
    }
}
