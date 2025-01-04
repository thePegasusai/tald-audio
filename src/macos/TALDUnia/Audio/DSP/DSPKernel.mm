#include "DSPKernel.hpp"
#include <algorithm>
#include <cmath>
#include <numbers>

// Version comments for external dependencies
// Accelerate Framework: macOS SDK 14.0+
// C++20 STL: Apple Clang 15.0+

namespace tald {
namespace dsp {

namespace {
    // SIMD optimization constants
    constexpr size_t VECTOR_ALIGNMENT = 32;  // AVX2 alignment
    constexpr size_t DENORMAL_THRESHOLD = 1.0e-15;
    constexpr float MIN_GAIN_DB = -120.0f;
    constexpr float MAX_GAIN_DB = 12.0f;
}

class DSPKernelImpl final : public DSPKernel {
public:
    DSPKernelImpl(double sampleRate, int channels) 
        : DSPKernel(sampleRate, channels)
        , dspSetup(nullptr)
        , gainFactor(1.0f)
        , processingLock(false)
    {
        // Initialize Accelerate framework setup
        dspSetup = vDSP_create_fftsetup(std::bit_width(static_cast<unsigned int>(MAX_BUFFER_SIZE)), 
                                       kFFTRadix2);
        if (!dspSetup) {
            throw std::runtime_error("Failed to initialize vDSP setup");
        }

        // Configure CPU feature detection for SIMD
        setupSIMDSupport();
        
        // Initialize processing buffers with denormal protection
        initializeBuffers();
    }

    ~DSPKernelImpl() override {
        if (dspSetup) {
            vDSP_destroy_fftsetup(dspSetup);
        }
    }

    void process(float* input, float* output, size_t frameCount) noexcept override {
        if (!input || !output || frameCount == 0 || frameCount > MAX_BUFFER_SIZE) {
            return;
        }

        // Set processing flag atomically
        bool expected = false;
        if (!isProcessing.compare_exchange_strong(expected, true)) {
            return;
        }

        try {
            // Copy input to aligned buffer using vDSP
            vDSP_mmov(input, inputBuffer, frameCount, numChannels, 
                     frameCount, frameCount);

            // Process each channel with SIMD optimization
            for (int channel = 0; channel < numChannels; ++channel) {
                processChannel(channel, frameCount);
            }

            // Apply gain with hardware acceleration
            applyGain(frameCount);

            // Handle denormals
            preventDenormals(frameCount);

            // Copy to output buffer using vDSP
            vDSP_mmov(outputBuffer, output, frameCount, numChannels, 
                     frameCount, frameCount);
        }
        catch (...) {
            // Ensure processing flag is cleared on error
            isProcessing.store(false);
            throw;
        }

        isProcessing.store(false);
    }

    void reset() noexcept override {
        // Wait for any ongoing processing to complete
        while (isProcessing.load(std::memory_order_acquire)) {
            std::this_thread::yield();
        }

        // Clear buffers using vDSP
        vDSP_vclr(inputBuffer, 1, MAX_BUFFER_SIZE * numChannels);
        vDSP_vclr(outputBuffer, 1, MAX_BUFFER_SIZE * numChannels);
        
        // Reset processing state
        gainFactor = 1.0f;
        processingLock.store(false);
        
        // Reinitialize vDSP setup
        if (dspSetup) {
            vDSP_destroy_fftsetup(dspSetup);
            dspSetup = vDSP_create_fftsetup(std::bit_width(static_cast<unsigned int>(MAX_BUFFER_SIZE)), 
                                          kFFTRadix2);
        }
    }

    void setParameter(int parameterID, float value) noexcept override {
        // Acquire parameter lock
        bool expected = false;
        if (!processingLock.compare_exchange_strong(expected, true)) {
            return;
        }

        try {
            switch (parameterID) {
                case 0: // Gain parameter
                    setGain(value);
                    break;
                // Add additional parameter handlers here
                default:
                    break;
            }
        }
        catch (...) {
            processingLock.store(false);
            return;
        }

        processingLock.store(false);
    }

private:
    vDSP_Setup_t dspSetup;
    float gainFactor;
    std::atomic<bool> processingLock;
    
    void setupSIMDSupport() {
        // Configure CPU feature detection
        #if defined(__AVX2__)
            _MM_SET_FLUSH_ZERO_MODE(_MM_FLUSH_ZERO_ON);
            _MM_SET_DENORMALS_ZERO_MODE(_MM_DENORMALS_ZERO_ON);
        #endif
    }

    void initializeBuffers() {
        // Initialize buffers with small DC offset to prevent denormals
        const float dcOffset = 1.0e-25f;
        for (size_t i = 0; i < MAX_BUFFER_SIZE * numChannels; ++i) {
            inputBuffer[i] = dcOffset;
            outputBuffer[i] = dcOffset;
        }
    }

    void processChannel(int channel, size_t frameCount) {
        const size_t offset = channel * frameCount;
        
        // Apply SIMD-optimized processing
        if (frameCount >= SIMD_VECTOR_SIZE) {
            const size_t vectorCount = frameCount / SIMD_VECTOR_SIZE;
            const size_t remainder = frameCount % SIMD_VECTOR_SIZE;
            
            // Process SIMD vectors
            vDSP_vsmul(&inputBuffer[offset], 1, &gainFactor,
                      &outputBuffer[offset], 1, vectorCount * SIMD_VECTOR_SIZE);
            
            // Process remaining samples
            if (remainder > 0) {
                const size_t remainderOffset = offset + (vectorCount * SIMD_VECTOR_SIZE);
                vDSP_vsmul(&inputBuffer[remainderOffset], 1, &gainFactor,
                          &outputBuffer[remainderOffset], 1, remainder);
            }
        }
        else {
            // Direct processing for small buffer sizes
            vDSP_vsmul(&inputBuffer[offset], 1, &gainFactor,
                      &outputBuffer[offset], 1, frameCount);
        }
    }

    void applyGain(size_t frameCount) {
        if (std::abs(gainFactor - 1.0f) > DENORMAL_THRESHOLD) {
            vDSP_vsmul(outputBuffer, 1, &gainFactor,
                      outputBuffer, 1, frameCount * numChannels);
        }
    }

    void preventDenormals(size_t frameCount) {
        const float threshold = static_cast<float>(DENORMAL_THRESHOLD);
        const size_t totalSamples = frameCount * numChannels;
        
        // Use vDSP for vectorized comparison and replacement
        for (size_t i = 0; i < totalSamples; i += SIMD_VECTOR_SIZE) {
            const size_t vectorSize = std::min(SIMD_VECTOR_SIZE, totalSamples - i);
            vDSP_vthres(&outputBuffer[i], 1, &threshold,
                       &outputBuffer[i], 1, vectorSize);
        }
    }

    void setGain(float gainDB) {
        // Clamp gain to valid range
        gainDB = std::clamp(gainDB, MIN_GAIN_DB, MAX_GAIN_DB);
        
        // Convert dB to linear gain with denormal protection
        const float minGain = std::pow(10.0f, MIN_GAIN_DB / 20.0f);
        gainFactor = std::max(minGain, std::pow(10.0f, gainDB / 20.0f));
    }
};

// Factory function implementation
std::unique_ptr<DSPKernel> createDSPKernel(double sampleRate, int channels) {
    return std::make_unique<DSPKernelImpl>(sampleRate, channels);
}

} // namespace dsp
} // namespace tald