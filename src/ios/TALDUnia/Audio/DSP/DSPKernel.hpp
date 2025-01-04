//
// DSPKernel.hpp
// TALD UNIA Audio System
//
// Abstract base class for high-performance DSP kernels with SIMD optimization
// and thread-safe processing capabilities.
//
// External Dependencies:
// - AudioToolbox (Latest) - Core audio processing and buffer management
// - Accelerate (Latest) - SIMD-optimized DSP operations

#ifndef DSPKernel_hpp
#define DSPKernel_hpp

#include <AudioToolbox/AudioToolbox.h>
#include <Accelerate/Accelerate.h>
#include <atomic>
#include <memory>

// Maximum number of frames that can be processed in a single slice
constexpr size_t kMaxFramesPerSlice = 4096;

// Maximum number of supported audio channels
constexpr int kMaxChannels = 8;

// SIMD memory alignment requirement in bytes
constexpr size_t kSIMDAlignmentBytes = 16;

// Default sample rate for initialization
constexpr double kDefaultSampleRate = 48000.0;

// Minimum buffer size for processing
constexpr size_t kMinBufferSize = 64;

/**
 * @class DSPKernel
 * @brief Thread-safe abstract base class for implementing high-performance DSP algorithms
 *        with SIMD optimization support.
 *
 * Provides a foundation for implementing digital signal processing kernels with:
 * - SIMD-optimized processing capabilities
 * - Thread-safe operation
 * - Efficient buffer management
 * - Performance monitoring
 * - Dynamic bypass control
 */
class DSPKernel {
public:
    /**
     * @brief Constructor initializing DSP kernel with SIMD-aligned memory
     */
    DSPKernel() 
        : processingBuffer(nullptr)
        , maxFrames(0)
        , isInitialized(false)
        , sampleRate(kDefaultSampleRate)
        , channelCount(0)
        , isBypassed(false)
        , isProcessing(false)
        , simdAlignedBuffer(nullptr)
        , bufferCapacity(0) {
    }

    /**
     * @brief Virtual destructor for proper cleanup of derived classes
     */
    virtual ~DSPKernel() {
        cleanup();
    }

    /**
     * @brief Initialize the DSP kernel with specified audio parameters
     * @param sampleRate The sample rate in Hz
     * @param channelCount Number of audio channels
     * @return true if initialization successful, false otherwise
     */
    virtual bool initialize(double sampleRate, int channelCount) = 0;

    /**
     * @brief Process audio data using SIMD optimization
     * @param inBuffer Input audio buffer
     * @param outBuffer Output audio buffer
     * @param frameCount Number of frames to process
     */
    virtual void process(float* inBuffer, float* outBuffer, size_t frameCount) = 0;

    /**
     * @brief Reset the kernel state while maintaining SIMD alignment
     */
    virtual void reset() = 0;

    /**
     * @brief Clean up resources with proper SIMD memory handling
     */
    virtual void cleanup() = 0;

    /**
     * @brief Thread-safe method to set the bypass state
     * @param shouldBypass True to bypass processing, false for normal operation
     */
    void setBypassed(bool shouldBypass) {
        std::atomic_store(&isBypassed, shouldBypass);
    }

protected:
    // SIMD-aligned processing buffer
    float* processingBuffer;
    
    // Maximum number of frames that can be processed
    size_t maxFrames;
    
    // Initialization state flag
    bool isInitialized;
    
    // Current sample rate
    double sampleRate;
    
    // Number of audio channels
    int channelCount;
    
    // Bypass state flag
    std::atomic<bool> isBypassed;
    
    // Processing state flag for thread safety
    std::atomic<bool> isProcessing;
    
    // SIMD-aligned buffer for intermediate processing
    float* simdAlignedBuffer;
    
    // Current buffer capacity
    size_t bufferCapacity;

private:
    // Prevent copying and assignment
    DSPKernel(const DSPKernel&) = delete;
    DSPKernel& operator=(const DSPKernel&) = delete;
};

#endif /* DSPKernel_hpp */