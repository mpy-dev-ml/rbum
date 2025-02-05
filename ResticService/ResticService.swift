//
//  ResticService.swift
//  ResticService
//
//  Created by Matthew Yeager on 05/02/2025.
//

import Foundation
import Core
import os.log
import Security

// MARK: - Restic XPC Error Domain
enum ResticXPCErrorDomain {
    static let name = "dev.mpy.rBUM.ResticService"
    
    enum Code: Int {
        case securityValidationFailed
        case auditSessionInvalid
        case bookmarkValidationFailed
        case accessDenied
        case timeout
    }
}

// MARK: - Restic Service Implementation
final class ResticService: BaseService, ResticXPCProtocol {
    // MARK: - Properties
    private let queue: DispatchQueue
    private let allowedBundleIdentifier = "dev.mpy.rBUM"
    
    // MARK: - Interface Version
    static var interfaceVersion: Int { 1 }
    
    // MARK: - Initialization
    init() {
        let queue = DispatchQueue(label: "dev.mpy.rBUM.resticservice", qos: .userInitiated)
        let logger = OSLogger(category: "ResticService")
        self.queue = queue
        super.init(logger: logger)
    }
    
    // MARK: - Security Validation
    private func validateClient() throws {
        guard let client = NSXPCConnection.current()?.effectiveUserIdentifier else {
            logger.error("Failed to get client identifier",
                        file: #file,
                        function: #function,
                        line: #line)
            throw makeError(.securityValidationFailed)
        }
        
        // Validate client's code signing
        let requirement = "anchor apple generic and identifier \"\(allowedBundleIdentifier)\""
        guard let connection = NSXPCConnection.current() else {
            logger.error("No XPC connection available",
                        file: #file,
                        function: #function,
                        line: #line)
            throw makeError(.securityValidationFailed)
        }
        
        let pid = connection.processIdentifier
        
        // Create the security requirement
        var requirementRef: SecRequirement?
        var status = SecRequirementCreateWithString(requirement as CFString, [], &requirementRef)
        guard status == errSecSuccess, let requirement = requirementRef else {
            logger.error("Failed to create security requirement",
                        file: #file,
                        function: #function,
                        line: #line)
            throw makeError(.securityValidationFailed)
        }
        
        // Validate the client's code
        guard let codeRef = SecCodeCreateWithAuditToken(pid),
              SecCodeCheckValidityWithErrors(codeRef, [], requirement, nil) == errSecSuccess else {
            logger.error("Client validation failed",
                        file: #file,
                        function: #function,
                        line: #line)
            throw makeError(.securityValidationFailed)
        }
    }
    
    private func validateAuditSession(_ auditSessionId: au_asid_t) throws {
        guard let connection = NSXPCConnection.current(),
              connection.auditSessionIdentifier == auditSessionId else {
            logger.error("Audit session validation failed",
                        file: #file,
                        function: #function,
                        line: #line)
            throw makeError(.auditSessionInvalid)
        }
    }
    
    // MARK: - ResticXPCProtocol Implementation
    func validateInterface(completion: @escaping ([String: Any]?) -> Void) {
        queue.async {
            do {
                try self.validateClient()
                completion(["version": Self.interfaceVersion])
            } catch {
                completion(self.errorDictionary(error))
            }
        }
    }
    
    func executeCommand(_ command: String,
                       arguments: [String],
                       environment: [String: String],
                       workingDirectory: String,
                       bookmarks: [String: NSData],
                       timeout: TimeInterval,
                       auditSessionId: au_asid_t,
                       completion: @escaping ([String: Any]?) -> Void) {
        queue.async {
            do {
                try self.validateClient()
                try self.validateAuditSession(auditSessionId)
                try self.validateBookmarks(bookmarks)
                
                // Create and configure process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                process.environment = environment
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                // Start process with timeout
                let timeoutWorkItem = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                        completion(self.errorDictionary(self.makeError(.timeout)))
                    }
                }
                
                self.queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
                
                try process.run()
                process.waitUntilExit()
                
                // Cancel timeout if process completed
                timeoutWorkItem.cancel()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                if process.terminationStatus == 0 {
                    completion([
                        "output": String(data: outputData, encoding: .utf8) ?? "",
                        "error": String(data: errorData, encoding: .utf8) ?? "",
                        "status": process.terminationStatus
                    ])
                } else {
                    let error = NSError(domain: ResticXPCErrorDomain.name,
                                      code: Int(process.terminationStatus),
                                      userInfo: [
                                        NSLocalizedDescriptionKey: String(data: errorData, encoding: .utf8) ?? "Unknown error"
                                      ])
                    completion(self.errorDictionary(error))
                }
            } catch {
                completion(self.errorDictionary(error))
            }
        }
    }
    
    func ping(auditSessionId: au_asid_t, completion: @escaping (Bool) -> Void) {
        queue.async {
            do {
                try self.validateClient()
                try self.validateAuditSession(auditSessionId)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }
    
    func validateAccess(bookmarks: [String: NSData],
                       auditSessionId: au_asid_t,
                       completion: @escaping ([String: Any]?) -> Void) {
        queue.async {
            do {
                try self.validateClient()
                try self.validateAuditSession(auditSessionId)
                try self.validateBookmarks(bookmarks)
                completion(["valid": true])
            } catch {
                completion(self.errorDictionary(error))
            }
        }
    }
    
    // MARK: - Security Helpers
    private func SecCodeCreateWithAuditToken(_ pid: pid_t) -> SecCode? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        return status == errSecSuccess ? code : nil
    }
    
    // MARK: - Helper Methods
    private func validateBookmarks(_ bookmarks: [String: NSData]) throws {
        for (_, bookmark) in bookmarks {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark as Data,
                                   options: .withSecurityScope,
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &isStale) else {
                throw makeError(.bookmarkValidationFailed)
            }
            
            if isStale {
                throw makeError(.bookmarkValidationFailed)
            }
            
            guard url.startAccessingSecurityScopedResource() else {
                throw makeError(.accessDenied)
            }
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    private func makeError(_ code: ResticXPCErrorDomain.Code) -> NSError {
        return NSError(domain: ResticXPCErrorDomain.name,
                      code: code.rawValue,
                      userInfo: nil)
    }
    
    private func errorDictionary(_ error: Error) -> [String: Any] {
        return [
            "error": true,
            "domain": (error as NSError).domain,
            "code": (error as NSError).code,
            "description": error.localizedDescription
        ]
    }
}
