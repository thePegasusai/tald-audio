// AVFoundation Latest
import AVFoundation
// Foundation Latest
import Foundation

/// Protocol defining audio session state change callbacks with power state notifications
public protocol AudioSessionDelegate: AnyObject {
    /// Called when audio session is interrupted
    func sessionInterrupted(_ session: AudioSession, type: AVAudioSession.InterruptionType, powerState: PowerMode)
    /// Called when audio route changes
    func sessionRouteChanged(_ session: AudioSession, reason: AVAudioSession.RouteChangeReason)
    /// Called when power mode changes
    func sessionPowerModeChanged(_ session: AudioSession, powerMode: PowerMode)
}

/// Power optimization modes for audio processing
public enum PowerMode {
    case highPerformance
    case balanced
    case powerEfficient
}

/// Hardware configuration for audio session
public struct HardwareConfiguration {
    let sampleRate: Double
    let bufferDuration: TimeInterval
    let ioBufferSize: Int
    let preferredLatency: TimeInterval
    let channelCount: Int
    
    static let `default` = HardwareConfiguration(
        sampleRate: Double(AudioConstants.sampleRate),
        bufferDuration: AudioConstants.maxLatency,
        ioBufferSize: AudioConstants.bufferSize,
        preferredLatency: AudioConstants.maxLatency,
        channelCount: AudioConstants.channelCount
    )
}

/// Manages the iOS audio session configuration and lifecycle with power optimization
public class AudioSession {
    // MARK: - Properties
    
    private let session = AVAudioSession.sharedInstance()
    public weak var delegate: AudioSessionDelegate?
    
    private(set) public var isActive = false
    private(set) public var currentPowerMode: PowerMode = .balanced
    private var hardwareConfig: HardwareConfiguration = .default
    
    private var notificationObservers: [NSObjectProtocol] = []
    
    // MARK: - Initialization
    
    public init() {
        setupNotificationObservers()
    }
    
    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    // MARK: - Public Methods
    
    /// Activates the audio session with power-efficient configuration
    public func activate(configuration: HardwareConfiguration = .default,
                        powerMode: PowerMode = .balanced) -> Result<Void, Error> {
        do {
            hardwareConfig = configuration
            currentPowerMode = powerMode
            
            // Configure audio session category and options
            try session.setCategory(
                .playAndRecord,
                mode: getAudioMode(for: powerMode),
                options: [.allowBluetoothA2DP, .allowAirPlay]
            )
            
            // Configure hardware-specific settings
            try session.setPreferredSampleRate(hardwareConfig.sampleRate)
            try session.setPreferredIOBufferDuration(hardwareConfig.bufferDuration)
            try session.setPreferredInputNumberOfChannels(hardwareConfig.channelCount)
            try session.setPreferredOutputNumberOfChannels(hardwareConfig.channelCount)
            
            // Activate the session
            try session.setActive(true)
            isActive = true
            
            return .success(())
        } catch {
            let context = ErrorContext(additionalInfo: [
                "powerMode": powerMode,
                "sampleRate": hardwareConfig.sampleRate,
                "bufferSize": hardwareConfig.ioBufferSize
            ])
            return .failure(AppError.audioInitializationFailed(reason: error.localizedDescription, context: context))
        }
    }
    
    /// Deactivates the audio session
    public func deactivate() -> Result<Void, Error> {
        do {
            try session.setActive(false)
            isActive = false
            return .success(())
        } catch {
            let context = ErrorContext()
            return .failure(AppError.audioError(reason: "Failed to deactivate session", context: context))
        }
    }
    
    /// Updates the power mode configuration
    public func updatePowerMode(_ mode: PowerMode) -> Result<Void, Error> {
        do {
            try session.setMode(getAudioMode(for: mode))
            currentPowerMode = mode
            delegate?.sessionPowerModeChanged(self, powerMode: mode)
            return .success(())
        } catch {
            let context = ErrorContext(additionalInfo: ["requestedMode": mode])
            return .failure(AppError.audioError(reason: "Failed to update power mode", context: context))
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        // Observe interruptions
        let interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
        
        // Observe route changes
        let routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
        
        notificationObservers = [interruptionObserver, routeChangeObserver]
    }
    
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        // Adjust power mode based on interruption
        let powerMode: PowerMode = type == .began ? .powerEfficient : currentPowerMode
        delegate?.sessionInterrupted(self, type: type, powerState: powerMode)
        
        if type == .ended {
            // Restore session if interruption ended
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    _ = activate(configuration: hardwareConfig, powerMode: currentPowerMode)
                }
            }
        }
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        // Update hardware configuration for new route
        let newRoute = session.currentRoute
        let outputs = newRoute.outputs
        
        // Optimize power mode for current route
        let newPowerMode = determinePowerMode(for: outputs)
        if newPowerMode != currentPowerMode {
            _ = updatePowerMode(newPowerMode)
        }
        
        delegate?.sessionRouteChanged(self, reason: reason)
    }
    
    private func getAudioMode(for powerMode: PowerMode) -> AVAudioSession.Mode {
        switch powerMode {
        case .highPerformance:
            return .measurement
        case .balanced:
            return .default
        case .powerEfficient:
            return .spokenAudio
        }
    }
    
    private func determinePowerMode(for outputs: [AVAudioSessionPortDescription]) -> PowerMode {
        // Determine optimal power mode based on output route
        if outputs.contains(where: { $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE }) {
            return .powerEfficient
        } else if outputs.contains(where: { $0.portType == .headphones || $0.portType == .builtInSpeaker }) {
            return .balanced
        } else {
            return .highPerformance
        }
    }
}