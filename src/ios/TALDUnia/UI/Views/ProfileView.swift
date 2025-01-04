// SwiftUI Latest
import SwiftUI

/// Main view for secure profile management interface with comprehensive accessibility support
@MainActor
struct ProfileView: View {
    // MARK: - View Model
    
    @StateObject private var viewModel: ProfileViewModel
    
    // MARK: - View State
    
    @State private var isAddingProfile = false
    @State private var editingProfile: Profile? = nil
    @State private var showingDeleteAlert = false
    @State private var showingErrorAlert = false
    @State private var profileToDelete: Profile? = nil
    @State private var isBackingUp = false
    @State private var showingBackupAlert = false
    @State private var backupURL: URL? = nil
    
    // MARK: - Environment
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // MARK: - Initialization
    
    init(viewModel: ProfileViewModel = ProfileViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                profileList
                    .navigationTitle("Audio Profiles")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                isAddingProfile = true
                            } label: {
                                Image(systemName: "plus")
                                    .accessibilityLabel("Add Profile")
                            }
                        }
                    }
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
            }
        }
        .sheet(isPresented: $isAddingProfile) {
            profileEditor(nil)
        }
        .sheet(item: $editingProfile) { profile in
            profileEditor(profile)
        }
        .alert("Delete Profile", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    Task {
                        await viewModel.deleteProfile(profile)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this profile? This action cannot be undone.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
        .alert("Backup Complete", isPresented: $showingBackupAlert) {
            Button("OK", role: .cancel) {}
            if let url = backupURL {
                Button("Share") {
                    let activityVC = UIActivityViewController(
                        activityItems: [url],
                        applicationActivities: nil
                    )
                    UIApplication.shared.windows.first?.rootViewController?
                        .present(activityVC, animated: true)
                }
            }
        } message: {
            Text("Profile backup has been created successfully.")
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    viewModel.loadProfiles()
                }
            }
        }
    }
    
    // MARK: - Profile List
    
    private var profileList: some View {
        List {
            ForEach(viewModel.profiles) { profile in
                ProfileRow(profile: profile)
                    .contextMenu {
                        Button {
                            editingProfile = profile
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button {
                            Task {
                                isBackingUp = true
                                let result = await viewModel.backupProfile(profile)
                                isBackingUp = false
                                
                                switch result {
                                case .success(let url):
                                    backupURL = url
                                    showingBackupAlert = true
                                case .failure(let error):
                                    viewModel.error = error
                                    showingErrorAlert = true
                                }
                            }
                        } label: {
                            Label("Backup", systemImage: "arrow.up.doc")
                        }
                        
                        Button(role: .destructive) {
                            profileToDelete = profile
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            profileToDelete = profile
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            editingProfile = profile
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Profile: \(profile.name)")
                    .accessibilityHint("Double tap to view options")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadProfiles()
        }
    }
    
    // MARK: - Profile Editor
    
    private func profileEditor(_ profile: Profile?) -> some View {
        NavigationView {
            ProfileEditorView(
                profile: profile,
                onSave: { name, preferences in
                    Task {
                        if let profile = profile {
                            // Update existing profile
                            var updatedProfile = profile
                            updatedProfile.name = name
                            _ = await viewModel.updateProfile(updatedProfile)
                        } else {
                            // Create new profile
                            _ = await viewModel.createProfile(
                                name: name,
                                preferences: preferences
                            )
                        }
                        isAddingProfile = false
                        editingProfile = nil
                    }
                },
                onCancel: {
                    isAddingProfile = false
                    editingProfile = nil
                }
            )
        }
    }
}

// MARK: - Profile Row

private struct ProfileRow: View {
    let profile: Profile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(profile.name)
                .font(.headline)
            
            HStack {
                Text("Last modified: ")
                    .foregroundColor(.secondary)
                Text(profile.lastModified, style: .date)
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
            
            if profile.isBackedUp {
                Label("Backed up", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
}