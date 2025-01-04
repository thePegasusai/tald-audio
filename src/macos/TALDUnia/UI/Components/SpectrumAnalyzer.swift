//
// SpectrumAnalyzer.swift
// TALD UNIA
//
// High-performance real-time spectrum analyzer with Metal acceleration
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+
import Metal // macOS 13.0+
import MetalKit // macOS 13.0+
import Accelerate // macOS 13.0+

// MARK: - Constants

private let kDefaultFFTSize: Int = 2048
private let kDefaultBands: Int = 128
private let kMinFrequency: Float = 20.0
private let kMaxFrequency: Float = 20000.0
private let kRefreshRate: Float = 60.0
private let kMaxLatency: Float = 10.0
private let kBufferPoolSize: Int = 3
private let kQualityScaleThreshold: Float = 0.8

// MARK: - Spectrum Analyzer Implementation

@available(macOS 13.0, *)
@MainActor
public class SpectrumAnalyzer: NSObject {
    
    // MARK: - Properties
    
    private let fftProcessor: FFTProcessor
    private let metalView: MTKView
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var bandFrequencies: [Float] = []
    private var bandMagnitudes: [Float] = []
    private let renderQueue: DispatchQueue
    private let bufferLock = NSLock()
    private var vertexBufferPool: [MTLBuffer] = []
    private var currentBufferIndex: Int = 0
    private var isProcessing: Bool = false
    
    // Performance monitoring
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: UInt = 0
    private var averageLatency: Double = 0
    
    // MARK: - Initialization
    
    public init(frame: CGRect, device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let metalDevice = device else {
            throw TALDError.configurationError(
                code: "NO_METAL_DEVICE",
                message: "No Metal device available",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "SpectrumAnalyzer",
                    additionalInfo: [:]
                )
            )
        }
        
        // Initialize FFT processor
        self.fftProcessor = try FFTProcessor(fftSize: kDefaultFFTSize)
        
        // Configure Metal view
        self.metalView = MTKView(frame: frame, device: metalDevice)
        self.metalView.colorPixelFormat = .bgra8Unorm
        self.metalView.preferredFramesPerSecond = Int(kRefreshRate)
        self.metalView.enableSetNeedsDisplay = true
        
        // Initialize render queue
        self.renderQueue = DispatchQueue(
            label: "com.tald.unia.spectrum.render",
            qos: .userInteractive
        )
        
        super.init()
        
        // Setup Metal resources
        try setupMetal(device: metalDevice)
        
        // Configure for ESS ES9038PRO DAC
        try configureHardwareOptimization()
        
        // Initialize frequency bands
        bandFrequencies = calculateBandFrequencies(bandCount: kDefaultBands)
        bandMagnitudes = Array(repeating: 0, count: kDefaultBands)
        
        metalView.delegate = self
    }
    
    // MARK: - Metal Setup
    
    private func setupMetal(device: MTLDevice) throws {
        // Create command queue
        guard let queue = device.makeCommandQueue() else {
            throw TALDError.configurationError(
                code: "COMMAND_QUEUE_FAILED",
                message: "Failed to create Metal command queue",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "SpectrumAnalyzer",
                    additionalInfo: [:]
                )
            )
        }
        self.commandQueue = queue
        
        // Create render pipeline
        let library = try device.makeDefaultLibrary()
        let vertexFunction = library.makeFunction(name: "spectrumVertex")
        let fragmentFunction = library.makeFunction(name: "spectrumFragment")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        // Initialize vertex buffer pool
        for _ in 0..<kBufferPoolSize {
            guard let buffer = device.makeBuffer(
                length: kDefaultBands * MemoryLayout<simd_float2>.stride,
                options: .storageModeShared
            ) else {
                throw TALDError.configurationError(
                    code: "BUFFER_ALLOCATION_FAILED",
                    message: "Failed to allocate Metal buffer",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "SpectrumAnalyzer",
                        additionalInfo: [:]
                    )
                )
            }
            vertexBufferPool.append(buffer)
        }
    }
    
    // MARK: - Hardware Optimization
    
    private func configureHardwareOptimization() throws {
        // Configure for ESS ES9038PRO DAC
        let config = DSPConfiguration(
            bufferSize: kDefaultFFTSize,
            channels: 2,
            sampleRate: Double(AudioConstants.SAMPLE_RATE),
            isOptimized: true,
            useHardwareAcceleration: true
        )
        
        try fftProcessor.configureHardware(config)
    }
    
    // MARK: - Spectrum Processing
    
    public func updateSpectrum(_ audioData: [Float]) {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        
        guard !isProcessing else { return }
        isProcessing = true
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Process FFT
        let result = fftProcessor.processSpectrum(
            audioData,
            &bandMagnitudes,
            frameCount: audioData.count
        )
        
        switch result {
        case .success(let spectralData):
            // Convert to decibels and apply band mapping
            AudioMathUtils.vectorizedLinearToDecibels(
                spectralData.magnitude,
                &bandMagnitudes,
                bandMagnitudes.count
            )
            
            // Update performance metrics
            let frameTime = CFAbsoluteTimeGetCurrent() - startTime
            updatePerformanceMetrics(frameTime: frameTime)
            
            metalView.setNeedsDisplay()
            
        case .failure(let error):
            print("Spectrum processing error: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    
    // MARK: - Rendering
    
    private func renderSpectrum(encoder: MTLRenderCommandEncoder) {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        
        // Get current buffer from pool
        let vertexBuffer = vertexBufferPool[currentBufferIndex]
        currentBufferIndex = (currentBufferIndex + 1) % kBufferPoolSize
        
        // Update vertex data
        let vertexData = vertexBuffer.contents().assumingMemoryBound(to: simd_float2.self)
        for i in 0..<bandMagnitudes.count {
            vertexData[i] = simd_float2(
                Float(i) / Float(bandMagnitudes.count - 1),
                bandMagnitudes[i]
            )
        }
        
        // Set render state
        encoder.setRenderPipelineState(pipelineState!)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Draw spectrum
        encoder.drawPrimitives(
            type: .lineStrip,
            vertexStart: 0,
            vertexCount: bandMagnitudes.count
        )
    }
    
    // MARK: - Performance Monitoring
    
    private func updatePerformanceMetrics(frameTime: CFTimeInterval) {
        frameCount += 1
        averageLatency = (averageLatency * Double(frameCount - 1) + frameTime) / Double(frameCount)
        
        if frameTime > Double(kMaxLatency) / 1000.0 {
            print("Warning: Frame time exceeded target latency: \(frameTime * 1000.0)ms")
        }
    }
}

// MARK: - MTKViewDelegate

extension SpectrumAnalyzer: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }
    
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
              ) else {
            return
        }
        
        renderSpectrum(encoder: renderEncoder)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - Utility Functions

private func calculateBandFrequencies(bandCount: Int) -> [Float] {
    var frequencies: [Float] = []
    let minLog = log10(kMinFrequency)
    let maxLog = log10(kMaxFrequency)
    let logStep = (maxLog - minLog) / Float(bandCount - 1)
    
    for i in 0..<bandCount {
        let logFreq = minLog + Float(i) * logStep
        frequencies.append(pow(10, logFreq))
    }
    
    return frequencies
}