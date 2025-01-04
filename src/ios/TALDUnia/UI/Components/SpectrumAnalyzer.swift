//
// SpectrumAnalyzer.swift
// TALD UNIA Audio System
//
// High-performance real-time spectrum analyzer with Metal-accelerated rendering
// and accessibility support for the TALD UNIA iOS application.
//
// Dependencies:
// - SwiftUI (Latest) - UI framework integration
// - Metal (Latest) - Hardware-accelerated rendering
// - MetalKit (Latest) - Metal view and resource management
// - Combine (Latest) - Reactive updates for real-time visualization

import SwiftUI
import Metal
import MetalKit
import Combine

// MARK: - Constants

private let kDefaultBarCount: Int = 128
private let kMaxFrequency: Float = 20000
private let kMinFrequency: Float = 20
private let kUpdateInterval: TimeInterval = 0.016 // ~60 FPS
private let kDefaultBarSpacing: Float = 2.0
private let kMaxBufferCount: Int = 3
private let kPeakHoldTime: TimeInterval = 2.0
private let kMinimumPowerThreshold: Float = -80.0

// MARK: - SpectrumAnalyzer Implementation

@MainActor
public final class SpectrumAnalyzer: NSObject {
    
    // MARK: - Properties
    
    private let fftProcessor: FFTProcessor
    private let device: MTLDevice
    private var pipelineState: MTLRenderPipelineState
    private var vertexBuffers: [MTLBuffer]
    private var currentBufferIndex: UInt = 0
    private var magnitudes: [Float]
    private var peakHolds: [Float]
    private var updateTimer: Timer?
    
    public private(set) var isActive: Bool = false
    public private(set) var processingLoad: Double = 0
    public private(set) var bufferStatus: UInt = 0
    
    private let reducedMotion: Bool
    private let isPowerEfficient: Bool
    
    // MARK: - Initialization
    
    public init(fftProcessor: FFTProcessor,
                reducedMotion: Bool = false,
                isPowerEfficient: Bool = false) throws {
        
        // Initialize Metal device
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            throw AppError.hardwareError(
                reason: "Metal device initialization failed",
                severity: .critical,
                context: ErrorContext()
            )
        }
        self.device = metalDevice
        
        // Store configuration
        self.fftProcessor = fftProcessor
        self.reducedMotion = reducedMotion
        self.isPowerEfficient = isPowerEfficient
        
        // Initialize arrays
        self.magnitudes = Array(repeating: 0, count: kDefaultBarCount)
        self.peakHolds = Array(repeating: 0, count: kDefaultBarCount)
        
        // Initialize vertex buffers
        self.vertexBuffers = []
        
        // Create pipeline state
        let library = try device.makeDefaultLibrary()
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        super.init()
        
        // Set up vertex buffers
        try setupVertexBuffers()
    }
    
    // MARK: - Public Interface
    
    public func startAnalyzer() {
        guard !isActive else { return }
        
        isActive = true
        
        // Start update timer
        let interval = isPowerEfficient ? kUpdateInterval * 2 : kUpdateInterval
        updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateSpectrum()
        }
    }
    
    public func stopAnalyzer() {
        guard isActive else { return }
        
        isActive = false
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Reset state
        magnitudes = Array(repeating: 0, count: kDefaultBarCount)
        peakHolds = Array(repeating: 0, count: kDefaultBarCount)
        processingLoad = 0
        bufferStatus = 0
    }
    
    @MainActor
    public func updateSpectrum(_ magnitudes: [Float], processingLoad: Double, bufferStatus: UInt) {
        guard isActive else { return }
        
        // Update metrics
        self.processingLoad = processingLoad
        self.bufferStatus = bufferStatus
        
        // Apply SIMD optimization for dB conversion
        var dbMagnitudes = [Float](repeating: 0, count: magnitudes.count)
        vDSP_vdbcon(magnitudes,
                    1,
                    [20.0],
                    &dbMagnitudes,
                    1,
                    vDSP_Length(magnitudes.count),
                    1)
        
        // Update peak holds
        for i in 0..<dbMagnitudes.count {
            if dbMagnitudes[i] > peakHolds[i] {
                peakHolds[i] = dbMagnitudes[i]
            } else {
                // Decay peak holds
                peakHolds[i] = max(dbMagnitudes[i],
                                 peakHolds[i] - Float(kUpdateInterval / kPeakHoldTime))
            }
        }
        
        // Update vertex buffer
        updateVertexBuffer(with: dbMagnitudes)
        
        // Update accessibility
        updateAccessibilityDescription()
    }
    
    // MARK: - Private Methods
    
    private func setupVertexBuffers() throws {
        // Create multiple vertex buffers for triple buffering
        for _ in 0..<kMaxBufferCount {
            guard let buffer = device.makeBuffer(length: MemoryLayout<Float>.stride * kDefaultBarCount,
                                               options: .storageModeShared) else {
                throw AppError.hardwareError(
                    reason: "Failed to create vertex buffer",
                    severity: .error,
                    context: ErrorContext()
                )
            }
            vertexBuffers.append(buffer)
        }
    }
    
    private func updateVertexBuffer(with magnitudes: [Float]) {
        // Use triple buffering to avoid synchronization issues
        currentBufferIndex = (currentBufferIndex + 1) % UInt(kMaxBufferCount)
        let buffer = vertexBuffers[Int(currentBufferIndex)]
        
        // Copy magnitude data to vertex buffer
        let bufferPointer = buffer.contents().assumingMemoryBound(to: Float.self)
        magnitudes.withUnsafeBufferPointer { ptr in
            memcpy(bufferPointer, ptr.baseAddress, MemoryLayout<Float>.stride * magnitudes.count)
        }
    }
    
    private func updateAccessibilityDescription() {
        let description = "Spectrum Analyzer showing frequency content from \(Int(kMinFrequency))Hz to \(Int(kMaxFrequency))Hz"
        accessibilityLabel = description
        accessibilityValue = "Processing load: \(Int(processingLoad * 100))%"
    }
}

// MARK: - Metal Rendering Extension

extension SpectrumAnalyzer: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle view resize
    }
    
    public func draw(in view: MTKView) {
        guard isActive,
              let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        // Configure render pass
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffers[Int(currentBufferIndex)],
                              offset: 0,
                              index: 0)
        
        // Draw spectrum
        encoder.drawPrimitives(type: .triangleStrip,
                             vertexStart: 0,
                             vertexCount: kDefaultBarCount * 2)
        
        // Draw peak holds if not in reduced motion mode
        if !reducedMotion {
            encoder.setVertexBuffer(vertexBuffers[Int((currentBufferIndex + 1) % UInt(kMaxBufferCount))],
                                  offset: 0,
                                  index: 1)
            encoder.drawPrimitives(type: .lineStrip,
                                 vertexStart: 0,
                                 vertexCount: kDefaultBarCount)
        }
        
        encoder.endEncoding()
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        
        commandBuffer.commit()
    }
}