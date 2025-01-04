#!/bin/bash

# TALD UNIA iOS Build Script
# Version: 1.0.0
# Purpose: Production build script with optimized settings for audio processing and AI features

# Enable strict error handling
set -euo pipefail
IFS=$'\n\t'

# Import bootstrap utilities
source "$(dirname "$0")/bootstrap.sh"

# Global variables
WORKSPACE_PATH="../TALDUnia.xcworkspace"
PROJECT_PATH="../TALDUnia.xcodeproj"
SCHEME_NAME="TALDUnia"
CONFIGURATION="Release"
ARCHIVE_PATH="../build/TALDUnia.xcarchive"
BUILD_THREADS="$(sysctl -n hw.ncpu)"
DERIVED_DATA_PATH="../DerivedData"
PODS_CACHE_PATH="../PodsCache"

# Build flags for optimized audio processing
AUDIO_BUILD_FLAGS=(
    "ENABLE_BITCODE=NO"
    "SWIFT_OPTIMIZATION_LEVEL=-O"
    "GCC_OPTIMIZATION_LEVEL=3"
    "ENABLE_NS_ASSERTIONS=NO"
    "SWIFT_COMPILATION_MODE=wholemodule"
    "METAL_ENABLE_DEBUG_INFO=NO"
    "ENABLE_TESTABILITY=NO"
    "VALIDATE_PRODUCT=YES"
    "DEBUG_INFORMATION_FORMAT=dwarf-with-dsym"
    "COMPILER_INDEX_STORE_ENABLE=NO"
    "SWIFT_PARALLEL_COMPILATION_JOBS=${BUILD_THREADS}"
    "METAL_FAST_MATH=YES"
    "CLANG_OPTIMIZATION_PROFILE_FILE=$(pwd)/OptimizationProfiles/audio_processing.profdata"
)

# Check environment and dependencies
check_environment() {
    echo "Checking build environment..."
    
    # Source bootstrap checks
    check_prerequisites
    validate_hardware_config
    
    # Verify Xcode installation
    if ! command -v xcodebuild &> /dev/null; then
        echo "Error: Xcode command line tools not found"
        exit 1
    fi
    
    # Verify CocoaPods installation
    setup_cocoapods
    
    echo "Environment check completed successfully"
}

# Clean build artifacts
clean_build() {
    echo "Cleaning build artifacts..."
    
    # Remove DerivedData
    rm -rf "${DERIVED_DATA_PATH}"
    
    # Clean Xcode build
    xcodebuild clean \
        -workspace "${WORKSPACE_PATH}" \
        -scheme "${SCHEME_NAME}" \
        -configuration "${CONFIGURATION}" \
        || { echo "Error: Failed to clean Xcode build"; exit 1; }
    
    # Clean CocoaPods cache
    rm -rf "${PODS_CACHE_PATH}"
    
    echo "Clean completed successfully"
}

# Build dependencies
build_dependencies() {
    echo "Building dependencies..."
    
    # Install CocoaPods
    pod install \
        --repo-update \
        --verbose \
        || { echo "Error: Failed to install pods"; exit 1; }
    
    echo "Dependencies built successfully"
}

# Build project with optimizations
build_project() {
    echo "Building project..."
    
    # Join build flags
    local BUILD_SETTINGS="${AUDIO_BUILD_FLAGS[*]}"
    
    # Build for release
    xcodebuild build \
        -workspace "${WORKSPACE_PATH}" \
        -scheme "${SCHEME_NAME}" \
        -configuration "${CONFIGURATION}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        -parallelizeTargets \
        -jobs "${BUILD_THREADS}" \
        ${BUILD_SETTINGS} \
        || { echo "Error: Build failed"; exit 1; }
    
    # Archive build
    xcodebuild archive \
        -workspace "${WORKSPACE_PATH}" \
        -scheme "${SCHEME_NAME}" \
        -configuration "${CONFIGURATION}" \
        -archivePath "${ARCHIVE_PATH}" \
        ${BUILD_SETTINGS} \
        || { echo "Error: Archive failed"; exit 1; }
    
    echo "Build completed successfully"
}

# Main build process
main() {
    echo "Starting TALD UNIA build process..."
    
    # Execute build steps
    check_environment
    clean_build
    build_dependencies
    build_project
    
    echo "Build process completed successfully"
}

# Execute main function
main