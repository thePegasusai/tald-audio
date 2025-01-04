#ifndef TALD_UNIA_DSP_KERNEL_HPP
#define TALD_UNIA_DSP_KERNEL_HPP

#include <vector>      // C++20
#include <memory>      // C++20
#include <simd>        // C++20
#include <Accelerate/Accelerate.h> // macOS SDK

// Global constants for DSP configuration
constexpr int MAX_CHANNELS = 8;
constexpr int SIMD_VECTOR_SIZE = 8;
constexpr int DSP_ALIGNMENT = 16;
constexpr int CACHE_LINE_SIZE = 64;
constexpr size_t MAX_BUFFER_SIZE = 8192;
constexpr double MIN_SAMPLE_RATE = 44100.0;
constexpr double MAX_SAMPLE_RATE = 384000.0;

namespace tald {
namespace dsp {

/**
 * @brief Allocates cache-line aligned memory for SIMD operations
 * @param size Memory size in bytes
 * @param alignment Required memory alignment (must be power of 2)
 * @return Aligned memory pointer or nullptr on failure
 */
[[nodiscard]]
void* alignedMalloc(size_t size, size_t alignment) {
    if ((alignment & (alignment - 1)) != 0) {
        return nullptr; // Alignment must be power of 2
    }
    
    if (alignment < DSP_ALIGNMENT) {
        alignment = DSP_ALIGNMENT;
    }
    
    void* ptr = nullptr;
    #ifdef __APPLE__
        if (posix_memalign(&ptr, alignment, size) != 0) {
            return nullptr;
        }
    #else
        ptr = aligned_alloc(alignment, size);
    #endif
    
    if (ptr) {
        memset(ptr, 0, size);
    }
    return ptr;
}

/**
 * @brief Safely frees aligned memory
 * @param ptr Pointer to aligned memory
 */
void alignedFree(void* ptr) noexcept {
    if (ptr) {
        free(ptr);
    }
}

/**
 * @brief Abstract base class for DSP kernel implementations
 * Provides SIMD-optimized audio processing with hardware acceleration support
 */
class alignas(DSP_ALIGNMENT) DSPKernel {
public:
    /**
     * @brief Constructs DSP kernel with audio configuration
     * @param sampleRate Audio sample rate (Hz)
     * @param channels Number of audio channels
     * @throws std::invalid_argument if parameters are out of valid range
     */
    DSPKernel(double sampleRate, int channels) 
        : inputBuffer(nullptr)
        , outputBuffer(nullptr)
        , bufferSize(0)
        , numChannels(channels)
        , sampleRate(sampleRate)
        , isProcessing(false)
        , bypass(false)
        , fftSetup(nullptr)
    {
        if (sampleRate < MIN_SAMPLE_RATE || sampleRate > MAX_SAMPLE_RATE) {
            throw std::invalid_argument("Sample rate out of valid range");
        }
        
        if (channels <= 0 || channels > MAX_CHANNELS) {
            throw std::invalid_argument("Invalid channel count");
        }

        // Allocate aligned buffers
        inputBuffer = static_cast<float*>(alignedMalloc(MAX_BUFFER_SIZE * channels * sizeof(float), CACHE_LINE_SIZE));
        outputBuffer = static_cast<float*>(alignedMalloc(MAX_BUFFER_SIZE * channels * sizeof(float), CACHE_LINE_SIZE));
        
        if (!inputBuffer || !outputBuffer) {
            alignedFree(inputBuffer);
            alignedFree(outputBuffer);
            throw std::runtime_error("Failed to allocate aligned buffers");
        }

        // Initialize processing buffer with aligned allocator
        processingBuffer.resize(MAX_BUFFER_SIZE * channels);
        
        // Initialize FFT setup for Accelerate framework
        fftSetup = vDSP_create_fftsetup(std::bit_width(static_cast<unsigned int>(MAX_BUFFER_SIZE)), kFFTRadix2);
        
        // Allocate temporary buffer for processing
        tempBuffer = std::make_unique<float[]>(MAX_BUFFER_SIZE * channels);
    }

    virtual ~DSPKernel() {
        if (fftSetup) {
            vDSP_destroy_fftsetup(fftSetup);
        }
        alignedFree(inputBuffer);
        alignedFree(outputBuffer);
    }

    // Prevent copying
    DSPKernel(const DSPKernel&) = delete;
    DSPKernel& operator=(const DSPKernel&) = delete;

    /**
     * @brief Process audio samples using SIMD operations
     * @param input Input audio buffer
     * @param output Output audio buffer
     * @param frameCount Number of frames to process
     */
    virtual void process(float* input, float* output, size_t frameCount) noexcept = 0;

    /**
     * @brief Reset kernel state and clear buffers
     */
    virtual void reset() noexcept = 0;

    /**
     * @brief Set processing parameter
     * @param parameterID Parameter identifier
     * @param value Parameter value
     */
    virtual void setParameter(int parameterID, float value) noexcept = 0;

protected:
    float* inputBuffer;                    // SIMD-aligned input buffer
    float* outputBuffer;                   // SIMD-aligned output buffer
    size_t bufferSize;                     // Current buffer size
    int numChannels;                       // Number of audio channels
    double sampleRate;                     // Audio sample rate
    std::vector<float> processingBuffer;   // Intermediate processing buffer
    bool isProcessing;                     // Processing state flag
    std::atomic<bool> bypass;              // Bypass processing flag
    vDSP_Length fftSetup;                  // Accelerate FFT configuration
    std::unique_ptr<float[]> tempBuffer;   // Temporary processing buffer

    /**
     * @brief Verify buffer alignment for SIMD operations
     * @param ptr Buffer pointer to check
     * @return true if properly aligned
     */
    [[nodiscard]]
    bool isBufferAligned(const void* ptr) const noexcept {
        return (reinterpret_cast<std::uintptr_t>(ptr) % DSP_ALIGNMENT) == 0;
    }
};

} // namespace dsp
} // namespace tald

#endif // TALD_UNIA_DSP_KERNEL_HPP