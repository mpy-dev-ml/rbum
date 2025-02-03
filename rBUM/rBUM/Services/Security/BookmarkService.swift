//
//  BookmarkService.swift
//  rBUM
//
//  Created by Matthew Yeager on 01/02/2025.
//

import Foundation
import os

/// Protocol for managing security-scoped bookmarks
protocol BookmarkServiceProtocol {
    /// Create a security-scoped bookmark for a URL
    /// - Parameters:
    ///   - url: The URL to create a bookmark for
    ///   - timeout: Optional timeout for the operation
    /// - Returns: The bookmark data
    func createBookmark(for url: URL, timeout: TimeInterval) async throws -> Data
    
    /// Resolve a security-scoped bookmark
    /// - Parameters:
    ///   - bookmarkData: The bookmark data to resolve
    ///   - timeout: Optional timeout for the operation
    /// - Returns: Tuple containing the resolved URL and whether the bookmark is stale
    func resolveBookmark(_ bookmarkData: Data, timeout: TimeInterval) async throws -> (url: URL, isStale: Bool)
    
    /// Refresh a stale bookmark
    /// - Parameters:
    ///   - url: The URL to refresh the bookmark for
    ///   - timeout: Optional timeout for the operation
    /// - Returns: The new bookmark data
    func refreshBookmark(for url: URL, timeout: TimeInterval) async throws -> Data
    
    /// Restore persisted bookmarks
    /// - Parameter timeout: Optional timeout for the operation
    func restoreBookmarks(timeout: TimeInterval) async throws
    
    /// Stop accessing a security-scoped resource
    /// - Parameter url: The URL of the resource to stop accessing
    func stopAccessingResource(_ url: URL)
}

/// Service for managing security-scoped bookmarks
final class BookmarkService: BookmarkServiceProtocol {
    private let logger: Logger
    private let persistenceService: BookmarkPersistenceServiceProtocol
    private let fileManager: FileManager
    
    init(persistenceService: BookmarkPersistenceServiceProtocol = BookmarkPersistenceService(),
         fileManager: FileManager = .default) {
        self.persistenceService = persistenceService
        self.fileManager = fileManager
        self.logger = Logging.logger(for: .bookmarkService)
    }
    
    func createBookmark(for url: URL, timeout: TimeInterval = 30) async throws -> Data {
        logger.info("Creating bookmark for URL: \(url.path, privacy: .public)")
        return try await withTimeout(timeout) {
            do {
                let bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                try await self.persistenceService.persistBookmark(bookmarkData, forURL: url)
                return bookmarkData
            } catch {
                logger.error("Failed to create bookmark: \(error.localizedDescription, privacy: .public)")
                throw BookmarkError.creationFailed(error.localizedDescription)
            }
        }
    }
    
    func resolveBookmark(_ bookmarkData: Data, timeout: TimeInterval = 30) async throws -> (url: URL, isStale: Bool) {
        return try await withTimeout(timeout) {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData,
                                options: .withSecurityScope,
                                relativeTo: nil,
                                bookmarkDataIsStale: &isStale)
                
                if !url.startAccessingSecurityScopedResource() {
                    throw BookmarkError.resolutionFailed("Failed to start accessing resource")
                }
                
                return (url, isStale)
            } catch {
                logger.error("Failed to resolve bookmark: \(error.localizedDescription, privacy: .public)")
                throw BookmarkError.resolutionFailed(error.localizedDescription)
            }
        }
    }
    
    func refreshBookmark(for url: URL, timeout: TimeInterval = 30) async throws -> Data {
        return try await withTimeout(timeout) {
            do {
                let newBookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                try await persistenceService.persistBookmark(newBookmarkData, forURL: url)
                return newBookmarkData
            } catch {
                logger.error("Failed to refresh bookmark: \(error.localizedDescription, privacy: .public)")
                throw BookmarkError.refreshFailed(error.localizedDescription)
            }
        }
    }
    
    func restoreBookmarks(timeout: TimeInterval = 30) async throws {
        try await withTimeout(timeout) {
            do {
                let bookmarks = try await persistenceService.listBookmarks()
                for (url, bookmarkData) in bookmarks {
                    do {
                        let (resolvedURL, isStale) = try await resolveBookmark(bookmarkData)
                        if isStale {
                            _ = try await refreshBookmark(for: resolvedURL)
                        }
                    } catch {
                        logger.warning("Failed to restore bookmark for URL: \(url.path, privacy: .public)")
                        continue
                    }
                }
            } catch {
                logger.error("Failed to restore bookmarks: \(error.localizedDescription, privacy: .public)")
                throw BookmarkError.restorationFailed(error.localizedDescription)
            }
        }
    }
    
    func stopAccessingResource(_ url: URL) {
        if fileManager.isUbiquitousItem(at: url) {
            logger.debug("Skipping stop access for iCloud item: \(url.path, privacy: .public)")
            return
        }
        url.stopAccessingSecurityScopedResource()
        logger.debug("Stopped accessing resource: \(url.path, privacy: .public)")
    }
    
    private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw BookmarkError.operationTimeout
            }
            
            let result = try await group.next()
            group.cancelAll()
            return result ?? {
                throw BookmarkError.operationTimeout
            }()
        }
    }
}

/// Errors that can occur during bookmark operations
enum BookmarkError: LocalizedError {
    case creationFailed(String)
    case resolutionFailed(String)
    case refreshFailed(String)
    case restorationFailed(String)
    case operationTimeout
    
    var errorDescription: String? {
        switch self {
        case .creationFailed(let reason):
            return "Failed to create bookmark: \(reason)"
        case .resolutionFailed(let reason):
            return "Failed to resolve bookmark: \(reason)"
        case .refreshFailed(let reason):
            return "Failed to refresh bookmark: \(reason)"
        case .restorationFailed(let reason):
            return "Failed to restore bookmarks: \(reason)"
        case .operationTimeout:
            return "Operation timed out"
        }
    }
}
