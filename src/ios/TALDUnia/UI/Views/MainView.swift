// SwiftUI Latest
import SwiftUI
// Combine Latest
import Combine
// os.signpost Latest
import os.signpost

/// Root view container for the TALD UNIA iOS application with comprehensive accessibility support
@available(iOS 14.0, *)
@MainActor
public struct MainView: View {
    // MARK: - Constants
    
    private let kTabBarHeight: CGFloat = 49.0
    private let kSafeAreaPadding: CGFloat = 16.0
    private let kMemoryWarningThreshold: Float = 80.0
    private let kStateRestorationKey = "MainView.selectedTab"
    
    // MARK: - View State
    
    @State private var selectedTab: Int = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // MARK: - Performance Monitoring
    
    private let signposter = OSSignposter()
    
    // MARK: - Body
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            // Audio Control Tab
            AudioControlView()
                .tabItem {
                    Label("Audio", systemImage: "waveform")
                }
                .tag(0)
                .accessibilityLabel("Audio Controls")
            
            // Visualization Tab
            VisualizationView(viewModel: VisualizationViewModel())
                .tabItem {
                    Label("Visualization", systemImage: "waveform.circle")
                }
                .tag(1)
                .accessibilityLabel("Audio Visualization")
            
            // Profile Tab
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
                .tag(2)
                .accessibilityLabel("Profile Settings")
        }
        .accentColor(Colors.accent)
        .background(Colors.background)
        .onChange(of: scenePhase) { newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: selectedTab) { newTab in
            saveState(tab: newTab)
            updateAccessibility(for: newTab)
        }
        .onAppear {
            restoreState()
            setupNotifications()
        }
    }
    
    // MARK: - Private Methods
    
    @ViewBuilder
    private func makeTabBar() -> some View {
        HStack(spacing: kSafeAreaPadding) {
            Spacer()
            
            // Audio Controls Tab
            TabBarButton(
                title: "Audio",
                icon: "waveform",
                isSelected: selectedTab == 0
            ) {
                withAnimation {
                    selectedTab = 0
                }
            }
            
            // Visualization Tab
            TabBarButton(
                title: "Visualization",
                icon: "waveform.circle",
                isSelected: selectedTab == 1
            ) {
                withAnimation {
                    selectedTab = 1
                }
            }
            
            // Profile Tab
            TabBarButton(
                title: "Profile",
                icon: "person.circle",
                isSelected: selectedTab == 2
            ) {
                withAnimation {
                    selectedTab = 2
                }
            }
            
            Spacer()
        }
        .frame(height: kTabBarHeight)
        .background(Colors.surface)
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        let signpostID = signposter.makeSignpostID()
        
        switch newPhase {
        case .active:
            signposter.beginInterval("SceneActive", id: signpostID)
            restoreState()
            
        case .inactive:
            signposter.endInterval("SceneActive", id: signpostID)
            saveState(tab: selectedTab)
            
        case .background:
            handleMemoryWarning()
            
        @unknown default:
            break
        }
    }
    
    private func saveState(tab: Int) {
        UserDefaults.standard.set(tab, forKey: kStateRestorationKey)
    }
    
    private func restoreState() {
        if let savedTab = UserDefaults.standard.object(forKey: kStateRestorationKey) as? Int {
            selectedTab = savedTab
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            handleMemoryWarning()
        }
    }
    
    private func handleMemoryWarning() {
        let signpostID = signposter.makeSignpostID()
        signposter.beginInterval("MemoryWarning", id: signpostID)
        
        // Clear non-essential resources
        URLCache.shared.removeAllCachedResponses()
        
        signposter.endInterval("MemoryWarning", id: signpostID)
    }
    
    private func updateAccessibility(for tab: Int) {
        let announcement: String
        switch tab {
        case 0:
            announcement = "Audio Controls tab"
        case 1:
            announcement = "Visualization tab"
        case 2:
            announcement = "Profile Settings tab"
        default:
            announcement = "Selected tab \(tab + 1)"
        }
        
        UIAccessibility.post(
            notification: .screenChanged,
            argument: announcement
        )
    }
}

// MARK: - Supporting Views

private struct TabBarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption)
            }
        }
        .foregroundColor(isSelected ? Colors.accent : Colors.primary)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title) Tab")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Preview

#Preview {
    MainView()
}