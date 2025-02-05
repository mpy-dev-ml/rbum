//
//  SecurityService.swift
//  Core
//
//  Created by Matthew Yeager on 04/02/2025.
//

import Foundation
import AppKit

/// Service implementing security operations with sandbox compliance and XPC support
public final class SecurityService: SecurityServiceProtocol {
    private let logger: LoggerProtocol
    private let xpcService: ResticXPCServiceProtocol
    private var activeBookmarks: [URL: Data] = [:]
    private let bookmarkQueue = DispatchQueue(label: "dev.mpy.rBUM.security.bookmarks", attributes: .concurrent)
    
    /// Initialize the security service
    /// - Parameters:
    ///   - logger: Logger for tracking operations
    ///   - xpcService: XPC service for secure operations
    public init(logger: LoggerProtocol, xpcService: ResticXPCServiceProtocol) {
        self.logger = logger
        self.xpcService = xpcService
        setupNotifications()
    }
    
    private func setupNotifications() {
        logger.debug("Setting up security notifications",
                    file: #file,
                    function: #function,
                    line: #line)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func applicationWillTerminate(_ notification: Notification) {
        bookmarkQueue.sync(flags: .barrier) {
            activeBookmarks.removeAll()
        }
    }
    
    private func getActiveBookmark(for url: URL) -> Data? {
        bookmarkQueue.sync {
            activeBookmarks[url]
        }
    }
    
    private func setActiveBookmark(_ bookmark: Data, for url: URL) {
        bookmarkQueue.sync(flags: .barrier) {
            activeBookmarks[url] = bookmark
        }
    }
    
    private func removeActiveBookmark(for url: URL) {
        _ = bookmarkQueue.sync { activeBookmarks.removeValue(forKey: url) }
    }
    
    @MainActor
    public func requestPermission(for url: URL) async throws -> Bool {
        self.logger.debug("Requesting permission for: \(url.path)",
                         file: #file,
                         function: #function,
                         line: #line)
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.message = "Please grant access to this location"
        panel.prompt = "Grant Access"
        
        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow(contentRect: .zero,
                                                                                   styleMask: .borderless,
                                                                                   backing: .buffered,
                                                                                   defer: false))
        
        if response == .OK {
            self.logger.debug("Permission granted for: \(url.path)",
                            file: #file,
                            function: #function,
                            line: #line)
            return true
        } else {
            self.logger.debug("Permission denied for: \(url.path)",
                            file: #file,
                            function: #function,
                            line: #line)
            return false
        }
    }
    
    public func createBookmark(for url: URL) throws -> Data {
        self.logger.debug("Creating bookmark for: \(url.path)",
                         file: #file,
                         function: #function,
                         line: #line)
        
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                              includingResourceValuesForKeys: nil,
                                              relativeTo: nil)
            return bookmark
        } catch {
            throw SecurityError.bookmarkCreationFailed(error.localizedDescription)
        }
    }
    
    public func resolveBookmark(_ bookmark: Data) throws -> URL {
        self.logger.debug("Resolving bookmark",
                         file: #file,
                         function: #function,
                         line: #line)
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark,
                            options: .withSecurityScope,
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale)
            
            if isStale {
                self.logger.debug("Bookmark is stale",
                                file: #file,
                                function: #function,
                                line: #line)
                throw SecurityError.bookmarkStale("Bookmark needs to be recreated")
            }
            
            self.logger.debug("Bookmark resolved successfully",
                            file: #file,
                            function: #function,
                            line: #line)
            return url
            
        } catch {
            self.logger.error("Failed to resolve bookmark: \(error.localizedDescription)",
                            file: #file,
                            function: #function,
                            line: #line)
            throw SecurityError.bookmarkResolutionFailed(error.localizedDescription)
        }
    }
    
    public func startAccessing(_ url: URL) throws -> Bool {
        self.logger.debug("Starting access for: \(url.path)",
                         file: #file,
                         function: #function,
                         line: #line)
        return url.startAccessingSecurityScopedResource()
    }
    
    public func stopAccessing(_ url: URL) async throws {
        self.logger.debug("Stopping access for: \(url.path)",
                         file: #file,
                         function: #function,
                         line: #line)
        url.stopAccessingSecurityScopedResource()
    }
    
    public func validateAccess(to url: URL) async throws -> Bool {
        self.logger.debug("Validating access to: \(url.path)",
                         file: #file,
                         function: #function,
                         line: #line)
        
        do {
            let bookmark = try createBookmark(for: url)
            let resolvedURL = try resolveBookmark(bookmark)
            return resolvedURL.path == url.path
        } catch {
            return false
        }
    }
    
    public func persistAccess(to url: URL) async throws -> Data {
        self.logger.debug("Persisting access to: \(url.path)",
                         file: #file,
                         function: #function,
                         line: #line)
        
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        setActiveBookmark(bookmark, for: url)
        return bookmark
    }
    
    public func validateXPCService() async throws -> Bool {
        self.logger.debug("Validating XPC service",
                         file: #file,
                         function: #function,
                         line: #line)
        
        let isValid = try await xpcService.ping()
        if !isValid {
            self.logger.error("XPC service validation failed",
                            file: #file,
                            function: #function,
                            line: #line)
            throw SecurityError.xpcValidationFailed("Service ping returned false")
        }
        return isValid
    }
}
