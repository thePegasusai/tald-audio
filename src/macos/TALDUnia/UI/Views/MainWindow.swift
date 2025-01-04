//
// MainWindow.swift
// TALD UNIA
//
// Thread-safe main window controller with performance monitoring and error handling
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+
import AppKit // macOS 13.0+

// MARK: - Constants

private let WINDOW_MIN_WIDTH: CGFloat = 800.0
private let WINDOW_MIN_HEIGHT: CGFloat = 600.0
private let SIDEBAR_WIDTH: CGFloat = 220.0
private let ANIMATION_DURATION: Double = 0.3
private let MAX_HISTORY_ITEMS: Int = 50

// MARK: - Main Window Implementation

@available(macOS 13.0, *)
@MainActor
public class MainWindow: NSObject {
    // MARK: - Properties
    
    private let window: NSWindow
    @State private var selectedTab: String = "audio"
    @State private var isFullScreen: Bool = false
    @StateObject private var performanceMonitor = PerformanceMetrics()
    @StateObject private var navigationController = NavigationController()
    @StateObject private var errorHandler = WindowErrorHandler()
    private let viewModelCoordinator: ViewModelCoordinator
    
    // MARK: - Initialization
    
    public override init() {
        // Create and configure main window
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WINDOW_MIN_WIDTH, height: WINDOW_MIN_HEIGHT),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Initialize coordinator
        self.viewModelCoordinator = ViewModelCoordinator()
        
        super.init()
        
        // Configure window
        window.title = "TALD UNIA Audio System"
        window.minSize = NSSize(width: WINDOW_MIN_WIDTH, height: WINDOW_MIN_HEIGHT)
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        // Configure content view
        window.contentView = NSHostingView(
            rootView: makeWindowLayout()
                .environmentObject(performanceMonitor)
                .environmentObject(navigationController)
                .environmentObject(errorHandler)
        )
        
        // Setup error handling
        setupErrorHandling()
        
        // Start performance monitoring
        startPerformanceMonitoring()
    }
    
    // MARK: - Layout Construction
    
    @ViewBuilder
    private func makeWindowLayout() -> some View {
        NavigationSplitView {
            // Sidebar navigation
            makeNavigationSidebar()
                .frame(minWidth: SIDEBAR_WIDTH, maxWidth: SIDEBAR_WIDTH)
                .background(Colors.surface)
        } detail: {
            // Main content area
            makeContentArea()
                .background(Colors.background)
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    @ViewBuilder
    private func makeNavigationSidebar() -> some View {
        List(selection: $selectedTab) {
            NavigationLink(value: "audio") {
                Label("Audio Control", systemImage: "waveform")
            }
            
            NavigationLink(value: "profile") {
                Label("Profiles", systemImage: "person.crop.circle")
            }
            
            NavigationLink(value: "visualization") {
                Label("Visualization", systemImage: "waveform.circle")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("TALD UNIA")
    }
    
    @ViewBuilder
    private func makeContentArea() -> some View {
        TabView(selection: $selectedTab) {
            // Audio Control View
            AudioControlView(viewModel: viewModelCoordinator.audioControlViewModel)
                .tag("audio")
                .tabItem {
                    Label("Audio Control", systemImage: "waveform")
                }
            
            // Profile View
            ProfileView(viewModel: viewModelCoordinator.profileViewModel)
                .tag("profile")
                .tabItem {
                    Label("Profiles", systemImage: "person.crop.circle")
                }
            
            // Visualization View
            VisualizationView(viewModel: viewModelCoordinator.visualizationViewModel)
                .tag("visualization")
                .tabItem {
                    Label("Visualization", systemImage: "waveform.circle")
                }
        }
        .padding()
    }
    
    // MARK: - Error Handling
    
    private func setupErrorHandling() {
        errorHandler.onError = { [weak self] error in
            guard let self = self else { return }
            
            // Log error
            Logger.shared.error(
                error,
                context: "MainWindow",
                metadata: [
                    "view": self.selectedTab,
                    "isFullScreen": String(self.isFullScreen)
                ]
            )
            
            // Show error alert
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Error"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.beginSheetModal(for: self.window)
            }
        }
    }
    
    // MARK: - Performance Monitoring
    
    private func startPerformanceMonitoring() {
        performanceMonitor.startMonitoring { [weak self] metrics in
            // Update window title with performance info
            self?.window.title = String(
                format: "TALD UNIA - CPU: %.1f%% | Memory: %.1f MB | Latency: %.1fms",
                metrics.cpuUsage * 100,
                metrics.memoryUsage,
                metrics.audioLatency * 1000
            )
            
            // Log performance warnings
            if metrics.audioLatency > AudioConstants.TARGET_LATENCY {
                Logger.shared.log(
                    "High audio latency detected",
                    severity: .warning,
                    context: "MainWindow",
                    metadata: ["latency": String(metrics.audioLatency)]
                )
            }
        }
    }
}

// MARK: - Window Delegate

extension MainWindow: NSWindowDelegate {
    public func windowWillEnterFullScreen(_ notification: Notification) {
        isFullScreen = true
    }
    
    public func windowWillExitFullScreen(_ notification: Notification) {
        isFullScreen = false
    }
    
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Cleanup before closing
        performanceMonitor.stopMonitoring()
        viewModelCoordinator.cleanup()
        return true
    }
}