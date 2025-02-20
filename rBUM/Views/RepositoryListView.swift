import SwiftUI

struct RepositoryListView: View {
    @StateObject private var viewModel: RepositoryListViewModel
    @State private var showAddSheet = false
    @State private var showingDeleteAlert = false
    @State private var repositoryToDelete: Repository?
    private let credentialsManager: KeychainCredentialsManagerProtocol
    private let creationService: RepositoryCreationServiceProtocol

    init(
        credentialsManager: KeychainCredentialsManagerProtocol,
        creationService: RepositoryCreationServiceProtocol
    ) {
        self.credentialsManager = credentialsManager
        self.creationService = creationService
        _viewModel = StateObject(wrappedValue: RepositoryListViewModel())
    }

    var body: some View {
        NavigationStack {
            List(viewModel.repositories) { repository in
                NavigationLink(destination: RepositoryDetailView(repository: repository)) {
                    RepositoryRowView(repository: repository)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        repositoryToDelete = repository
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Repositories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add Repository", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                // Refresh repositories when sheet is dismissed
                Task {
                    await viewModel.loadRepositories()
                }
            } content: {
                NavigationStack {
                    RepositoryCreationView(
                        creationService: creationService,
                        credentialsManager: credentialsManager
                    )
                }
            }
            .alert("Delete Repository", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let repository = repositoryToDelete {
                        Task {
                            await viewModel.deleteRepository(repository)
                        }
                    }
                }
            } message: {
                if let repository = repositoryToDelete {
                    Text("Are you sure you want to delete '\(repository.name)'? This cannot be undone.")
                }
            }
            .task {
                await viewModel.loadRepositories()
            }
        }
    }
}

private struct RepositoryRowView: View {
    let repository: Repository

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(repository.name)
                .font(.headline)

            Text(repository.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

struct RepositoryListView_Previews: PreviewProvider {
    static var previews: some View {
        RepositoryListView(
            credentialsManager: PreviewCredentialsManager(),
            creationService: PreviewRepositoryCreationService()
        )
    }
}

// MARK: - Preview Helpers

private class PreviewCredentialsManager: KeychainCredentialsManagerProtocol {
    func retrieve(forId _: String) async throws -> RepositoryCredentials {
        RepositoryCredentials(repositoryPath: "/mock/path", password: "mock-password")
    }

    func list() async throws -> [(repositoryId: String, credentials: RepositoryCredentials)] {
        [
            ("mock-id", RepositoryCredentials(repositoryPath: "/mock/path", password: "mock-password")),
        ]
    }

    func store(_: RepositoryCredentials, forRepositoryId _: String) throws {
        // No-op for preview
    }

    func retrieve(forRepositoryId _: String) throws -> RepositoryCredentials? {
        // Return mock credentials for preview
        RepositoryCredentials(repositoryPath: "/mock/path", password: "mock-password")
    }

    func delete(forId _: String) throws {
        // No-op for preview
    }
}

private class PreviewRepositoryCreationService: RepositoryCreationServiceProtocol {
    func createRepository(name: String, path: String, password _: String) async throws -> Repository {
        // Return mock repository for preview
        Repository(name: name, path: path)
    }

    func importRepository(name: String, path: String, password _: String) async throws -> Repository {
        // Return mock repository for preview
        Repository(name: name, path: path)
    }
}
