// UIKit Latest
import UIKit
// SwiftUI Latest
import SwiftUI
// os.log Latest
import os.log

/// Scene delegate class managing scene lifecycle and window configuration for TALD UNIA iOS application
@available(iOS 13.0, *)
public class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    // MARK: - Properties
    
    public var window: UIWindow?
    private var stateRestorationActivity: NSUserActivity?
    private var windowConfigurationWorkItem: DispatchWorkItem?
    private let signposter = OSSignposter()
    
    // MARK: - Scene Lifecycle
    
    public func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UISceneConnectionOptions) {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("SceneConfiguration", id: signpostID)
        
        defer {
            signposter.endInterval("SceneConfiguration", state)
        }
        
        guard let windowScene = (scene as? UIWindowScene) else {
            os_log(.error, "Failed to cast scene to UIWindowScene")
            return
        }
        
        // Configure window with error handling
        let windowResult = configureWindow(windowScene)
        switch windowResult {
        case .success(let configuredWindow):
            self.window = configuredWindow
            
            // Configure root view
            let mainView = MainView()
                .environment(\.colorScheme, .light)
                .environment(\.sizeCategory, .large)
            
            // Create hosting controller
            let hostingController = UIHostingController(rootView: mainView)
            configuredWindow.rootViewController = hostingController
            
            // Make window visible with animation
            UIView.transition(with: configuredWindow,
                            duration: 0.3,
                            options: .transitionCrossDissolve,
                            animations: {
                configuredWindow.makeKeyAndVisible()
            })
            
            // Set up state restoration
            setupStateRestoration(session: session)
            
        case .failure(let error):
            os_log(.error, "Window configuration failed: %{public}@", error.localizedDescription)
        }
    }
    
    public func sceneDidDisconnect(_ scene: UIScene) {
        let signpostID = signposter.makeSignpostID()
        signposter.emitEvent("SceneDisconnect", id: signpostID)
        
        // Save state
        saveState()
        
        // Cancel any pending configuration
        windowConfigurationWorkItem?.cancel()
        windowConfigurationWorkItem = nil
        
        // Clear window reference
        window = nil
    }
    
    public func sceneDidBecomeActive(_ scene: UIScene) {
        let signpostID = signposter.makeSignpostID()
        signposter.emitEvent("SceneActive", id: signpostID)
        
        // Resume UI updates
        window?.layer.speed = 1.0
        
        // Configure active state
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Start monitoring
        startPerformanceMonitoring()
    }
    
    public func sceneWillResignActive(_ scene: UIScene) {
        let signpostID = signposter.makeSignpostID()
        signposter.emitEvent("SceneInactive", id: signpostID)
        
        // Pause UI updates
        window?.layer.speed = 0.0
        
        // Configure inactive state
        UIApplication.shared.isIdleTimerDisabled = false
        
        // Stop monitoring
        stopPerformanceMonitoring()
    }
    
    public func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        return stateRestorationActivity
    }
    
    // MARK: - Private Methods
    
    private func configureWindow(_ windowScene: UIWindowScene) -> Result<UIWindow, Error> {
        // Create window with scene
        let window = UIWindow(windowScene: windowScene)
        
        // Configure window properties
        window.backgroundColor = .systemBackground
        window.tintColor = UIColor(Colors.primary)
        
        // Configure accessibility
        window.accessibilityViewIsModal = false
        window.accessibilityIgnoresInvertColors = true
        
        // Configure UI style
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        
        return .success(window)
    }
    
    private func setupStateRestoration(session: UISceneSession) {
        // Create state restoration activity
        let activity = NSUserActivity(activityType: "com.taldunia.scene.restoration")
        activity.title = "TALD UNIA Scene State"
        activity.userInfo = ["sessionID": session.persistentIdentifier]
        activity.isEligibleForHandoff = false
        activity.isEligibleForSearch = false
        activity.isEligibleForPublicIndexing = false
        
        stateRestorationActivity = activity
    }
    
    private func saveState() {
        guard let activity = stateRestorationActivity else { return }
        
        // Save current UI state
        if let window = window,
           let hostingController = window.rootViewController as? UIHostingController<MainView> {
            activity.addUserInfoEntries(from: [
                "rootViewState": hostingController.rootView
            ])
        }
        
        activity.becomeCurrent()
    }
    
    private func startPerformanceMonitoring() {
        // Monitor UI performance
        let signpostID = signposter.makeSignpostID()
        signposter.beginInterval("UIPerformance", id: signpostID)
    }
    
    private func stopPerformanceMonitoring() {
        // Stop performance monitoring
        let signpostID = signposter.makeSignpostID()
        signposter.endInterval("UIPerformance", id: signpostID)
    }
}