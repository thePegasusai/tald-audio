//
// DSPKernel.mm
// TALD UNIA Audio System
//
// High-performance DSP kernel implementation with SIMD optimization,
// thread safety, and real-time monitoring capabilities.
//
// External Dependencies:
// - AudioToolbox (Latest) - Core audio functionality
// - Accelerate (Latest) - SIMD-optimized DSP operations
// - atomic (C++20) - Thread-safe operations

#import "DSPKernel.hpp"
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#import <dispatch/dispatch.h>
#import <mach/mach_time.h>

// High-priority queue for audio processing
static dispatch_queue_t processingQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

// Performance monitoring constants
static const uint64_t kPerformanceMonitoringInterval = 1000; // milliseconds
static const float kMaxAcceptableLatency = 10.0f; // milliseconds
static const float kTargetProcessingLoad = 0.4f; // 40% target CPU load

class DSPKernelImpl : public DSPKernel {
public:
    DSPKernelImpl() 
        : processingStartTime(0)
        , currentLatency(0.0f)
        , processingLoad(0.0f)
        , performanceMonitoringEnabled(true) {
        // Initialize NEON SIMD support
        simdChunkSize = kSIMDAlignmentBytes / sizeof(float);
    }

    bool initialize(double inSampleRate, int inChannelCount) override {
        if (inSampleRate <= 0 || inChannelCount <= 0 || inChannelCount > kMaxChannels) {
            return false;
        }

        // Store parameters
        sampleRate = inSampleRate;
        channelCount = inChannelCount;

        // Calculate buffer sizes
        maxFrames = kMaxFramesPerSlice;
        bufferCapacity = maxFrames * channelCount;

        // Allocate SIMD-aligned processing buffer
        posix_memalign(reinterpret_cast<void**>(&simdAlignedBuffer), 
                      kSIMDAlignmentBytes,
                      bufferCapacity * sizeof(float));
        
        if (!simdAlignedBuffer) {
            cleanup();
            return false;
        }

        // Initialize atomic state
        isInitialized = true;
        std::atomic_store(&isProcessing, false);
        std::atomic_store(&isBypassed, false);

        // Initialize performance monitoring
        currentLatency.store(0.0f);
        processingLoad.store(0.0f);
        
        return true;
    }

    void process(float* inBuffer, float* outBuffer, size_t frameCount) override {
        if (!isInitialized || frameCount > maxFrames || std::atomic_load(&isBypassed)) {
            // Pass through audio if not initialized or bypassed
            if (inBuffer != outBuffer) {
                memcpy(outBuffer, inBuffer, frameCount * channelCount * sizeof(float));
            }
            return;
        }

        // Ensure exclusive access to processing
        bool expected = false;
        if (!isProcessing.compare_exchange_strong(expected, true)) {
            return;
        }

        // Start performance monitoring
        uint64_t startTime = mach_absolute_time();

        // Process in SIMD chunks
        size_t remainingFrames = frameCount;
        size_t offset = 0;

        while (remainingFrames >= simdChunkSize) {
            // Load data into SIMD registers
            float* simdInput = inBuffer + (offset * channelCount);
            float* simdOutput = outBuffer + (offset * channelCount);

            // NEON SIMD processing for each channel
            for (int channel = 0; channel < channelCount; ++channel) {
                vDSP_vsmul(simdInput + channel, 
                          channelCount,
                          &kProcessingGain, 
                          simdOutput + channel,
                          channelCount,
                          simdChunkSize);
            }

            offset += simdChunkSize;
            remainingFrames -= simdChunkSize;
        }

        // Process remaining frames
        if (remainingFrames > 0) {
            float* remainingInput = inBuffer + (offset * channelCount);
            float* remainingOutput = outBuffer + (offset * channelCount);

            for (size_t i = 0; i < remainingFrames * channelCount; ++i) {
                remainingOutput[i] = remainingInput[i] * kProcessingGain;
            }
        }

        // Update performance metrics
        uint64_t endTime = mach_absolute_time();
        updatePerformanceMetrics(startTime, endTime, frameCount);

        std::atomic_store(&isProcessing, false);
    }

    void reset() override {
        if (simdAlignedBuffer) {
            vDSP_vclr(simdAlignedBuffer, 1, bufferCapacity);
        }
        
        currentLatency.store(0.0f);
        processingLoad.store(0.0f);
        std::atomic_store(&isProcessing, false);
    }

    void cleanup() override {
        if (simdAlignedBuffer) {
            free(simdAlignedBuffer);
            simdAlignedBuffer = nullptr;
        }
        
        isInitialized = false;
        std::atomic_store(&isProcessing, false);
    }

    // Performance monitoring methods
    float getLatency() const {
        return currentLatency.load();
    }

    float getProcessingLoad() const {
        return processingLoad.load();
    }

private:
    void updatePerformanceMetrics(uint64_t startTime, uint64_t endTime, size_t frameCount) {
        if (!performanceMonitoringEnabled) return;

        // Convert to milliseconds
        static mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        
        uint64_t elapsedNano = (endTime - startTime) * timebase.numer / timebase.denom;
        float elapsedMs = static_cast<float>(elapsedNano) / 1000000.0f;

        // Update latency
        currentLatency.store(elapsedMs);

        // Calculate processing load
        float frameDuration = (frameCount / sampleRate) * 1000.0f;
        float load = elapsedMs / frameDuration;
        processingLoad.store(load);

        // Log if exceeding targets
        if (elapsedMs > kMaxAcceptableLatency || load > kTargetProcessingLoad) {
            NSLog(@"Performance warning - Latency: %.2fms, Load: %.1f%%", 
                  elapsedMs, load * 100.0f);
        }
    }

    // SIMD configuration
    vDSP_Length simdChunkSize;
    
    // Performance monitoring
    uint64_t processingStartTime;
    std::atomic<float> currentLatency;
    std::atomic<float> processingLoad;
    bool performanceMonitoringEnabled;

    // Processing parameters
    static constexpr float kProcessingGain = 1.0f;
};