//
//  ResticCommandServiceProtocol.swift
//  rBUM
//
//  First created: 6 February 2025
//  Last updated: 6 February 2025
//
//  First created: 6 February 2025
//  Last updated: 6 February 2025
//
import Foundation

/// Protocol for executing Restic commands
public protocol ResticCommandServiceProtocol {
    /// Initialize a new repository
    /// - Parameter credentials: Credentials for repository access
    /// - Throws: SecurityError if initialization fails
    func initRepository(credentials: RepositoryCredentials) async throws

    /// Create a new backup
    /// - Parameters:
    ///   - paths: Paths to backup
    ///   - repository: Target repository
    ///   - credentials: Repository credentials
    ///   - tags: Optional tags for the backup
    /// - Throws: SecurityError if backup fails
    func createBackup(
        paths: [URL],
        to repository: Repository,
        credentials: RepositoryCredentials,
        tags: [String]?
    ) async throws

    /// List snapshots in a repository
    /// - Parameters:
    ///   - repository: Repository to list snapshots from
    ///   - credentials: Repository credentials
    /// - Returns: Array of snapshots
    /// - Throws: SecurityError if listing fails
    func listSnapshots(in repository: Repository, credentials: RepositoryCredentials) async throws -> [Snapshot]

    /// Restore a snapshot
    /// - Parameters:
    ///   - snapshot: Snapshot to restore
    ///   - repository: Source repository
    ///   - credentials: Repository credentials
    ///   - path: Path to restore to
    /// - Throws: SecurityError if restore fails
    func restoreSnapshot(
        _ snapshot: Snapshot,
        from repository: Repository,
        credentials: RepositoryCredentials,
        to path: URL
    ) async throws

    /// Delete a snapshot
    /// - Parameters:
    ///   - snapshot: Snapshot to delete
    ///   - repository: Source repository
    ///   - credentials: Repository credentials
    /// - Throws: SecurityError if deletion fails
    func deleteSnapshot(
        _ snapshot: Snapshot,
        from repository: Repository,
        credentials: RepositoryCredentials
    ) async throws
}
