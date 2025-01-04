#!/bin/bash

# TALD UNIA Audio System Build Script
# Version: 1.0.0
# Dependencies:
# - xcodebuild (14.0+)
# - xcpretty (0.3.0)

set -euo pipefail

# Global Configuration
PROJECT_DIR=$(pwd)/..
BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA_PATH="$BUILD_DIR/DerivedData"
CONFIGURATION="Release"
SCHEME="TALDUnia"
OPTIMIZATION_LEVEL="-O3"
VECTORIZATION_FLAGS="-fvectorize -fslp-vectorize"
AUDIO_OPTIMIZATION_FLAGS="-march=native -mtune=native"
BUILD_THREADS=$(sysctl -n hw.ncpu)

# Performance Monitoring Variables
declare -A BUILD_METRICS
BUILD_START_TIME=$(date +%s)

setup_build_environment() {
    echo "Setting up build environment with optimizations..."
    
    # Validate CPU architecture and capabilities
    if [[ $(sysctl -n machdep.cpu.brand_string) =~ "Apple" ]]; then
        AUDIO_OPTIMIZATION_FLAGS+=" -mcpu=apple-latest"
    else
        AUDIO_OPTIMIZATION_FLAGS+=" -mavx2 -mfma"
    fi
    
    # Create and clean build directories
    mkdir -p "$BUILD_DIR" "$DERIVED_DATA_PATH"
    rm -rf "$DERIVED_DATA_PATH"/*
    
    # Verify Xcode installation
    if ! command -v xcodebuild &> /dev/null; then
        echo "Error: Xcode build tools not found" >&2
        return 1
    fi
    
    # Configure environment variables
    export DEVELOPER_DIR="$(xcode-select -p)"
    export XCODE_XCCONFIG_FILE="$BUILD_DIR/optimization.xcconfig"
    
    # Create optimization configuration
    cat > "$XCODE_XCCONFIG_FILE" << EOF
ONLY_ACTIVE_ARCH = NO
ENABLE_TESTABILITY = NO
GCC_OPTIMIZATION_LEVEL = 3
LLVM_LTO = YES
SWIFT_OPTIMIZATION_LEVEL = -O
SWIFT_COMPILATION_MODE = wholemodule
OTHER_CFLAGS = $(echo $OPTIMIZATION_LEVEL $VECTORIZATION_FLAGS $AUDIO_OPTIMIZATION_FLAGS)
OTHER_SWIFT_FLAGS = -cross-module-optimization
EOF
    
    return 0
}

build_dependencies() {
    echo "Building dependencies with optimizations..."
    
    # Configure parallel build settings
    export MAKEFLAGS="-j$BUILD_THREADS"
    
    # Build Swift package dependencies
    xcodebuild \
        -resolvePackageDependencies \
        -workspace "$PROJECT_DIR/TALDUnia.xcworkspace" \
        -scheme "$SCHEME" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        | xcpretty
    
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "Error: Failed to resolve dependencies" >&2
        return 1
    fi
    
    return 0
}

build_application() {
    echo "Building TALD UNIA application with audio optimizations..."
    
    local build_command=(
        xcodebuild
        -workspace "$PROJECT_DIR/TALDUnia.xcworkspace"
        -scheme "$SCHEME"
        -configuration "$CONFIGURATION"
        -derivedDataPath "$DERIVED_DATA_PATH"
        -parallelizeTargets
        COMPILER_INDEX_STORE_ENABLE=NO
        BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
    )
    
    # Execute build with performance monitoring
    if ! "${build_command[@]}" | xcpretty; then
        echo "Error: Application build failed" >&2
        return 1
    fi
    
    # Record build metrics
    BUILD_METRICS["build_duration"]=$(($(date +%s) - BUILD_START_TIME))
    BUILD_METRICS["optimization_level"]="$OPTIMIZATION_LEVEL"
    
    return 0
}

run_verification() {
    echo "Running build verification..."
    
    local app_path="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/TALDUnia.app"
    
    # Verify binary optimizations
    if ! otool -l "$app_path/Contents/MacOS/TALDUnia" | grep -q "LC_VERSION_MIN_MACOS"; then
        echo "Error: Binary verification failed" >&2
        return 1
    fi
    
    # Validate audio processing capabilities
    if ! "$app_path/Contents/MacOS/TALDUnia" --verify-audio-processing &> /dev/null; then
        echo "Error: Audio processing verification failed" >&2
        return 1
    fi
    
    # Generate verification report
    cat > "$BUILD_DIR/build_report.txt" << EOF
Build Verification Report
------------------------
Build Duration: ${BUILD_METRICS["build_duration"]}s
Optimization Level: ${BUILD_METRICS["optimization_level"]}
CPU Architecture: $(sysctl -n machdep.cpu.brand_string)
Build Date: $(date)
EOF
    
    return 0
}

main() {
    local exit_code=0
    
    echo "Starting TALD UNIA build process..."
    
    # Execute build pipeline with error handling
    if ! setup_build_environment; then
        echo "Error: Environment setup failed" >&2
        exit_code=1
    elif ! build_dependencies; then
        echo "Error: Dependency build failed" >&2
        exit_code=1
    elif ! build_application; then
        echo "Error: Application build failed" >&2
        exit_code=1
    elif ! run_verification; then
        echo "Error: Verification failed" >&2
        exit_code=1
    fi
    
    # Output build summary
    if [[ $exit_code -eq 0 ]]; then
        echo "Build completed successfully in ${BUILD_METRICS["build_duration"]}s"
        echo "Build artifacts available at: $BUILD_DIR"
    else
        echo "Build failed. Check logs for details." >&2
    fi
    
    return $exit_code
}

# Execute main function
main "$@"