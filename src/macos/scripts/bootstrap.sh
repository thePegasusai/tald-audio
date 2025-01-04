#!/bin/bash

# TALD UNIA Audio System - macOS Development Environment Bootstrap Script
# Version: 1.0.0
# Description: Sets up the development environment for TALD UNIA audio processing system
# Requirements: macOS 12.0+, Xcode 14.0+, 16GB+ RAM, 100GB+ free disk space

# Enable strict error handling
set -euo pipefail

# Global constants
readonly REQUIRED_XCODE_VERSION="14.0"
readonly REQUIRED_MACOS_VERSION="12.0"
readonly MIN_RAM_GB=16
readonly MIN_DISK_SPACE_GB=100
readonly PROJECT_DIR="$(pwd)/.."
readonly LOG_FILE="${PROJECT_DIR}/logs/bootstrap_$(date +%Y%m%d_%H%M%S).log"
readonly ERROR_LOG_FILE="${PROJECT_DIR}/logs/bootstrap_error_$(date +%Y%m%d_%H%M%S).log"

# Create logs directory if it doesn't exist
mkdir -p "${PROJECT_DIR}/logs"

# Setup logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${ERROR_LOG_FILE}" >&2)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

check_system_requirements() {
    log "Checking system requirements..."
    
    # Check macOS version
    if [[ $(sw_vers -productVersion) < "${REQUIRED_MACOS_VERSION}" ]]; then
        error "macOS ${REQUIRED_MACOS_VERSION} or higher is required"
        return 1
    }
    
    # Check RAM
    local total_ram_gb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
    if [[ ${total_ram_gb} -lt ${MIN_RAM_GB} ]]; then
        error "Minimum ${MIN_RAM_GB}GB RAM required, found ${total_ram_gb}GB"
        return 1
    }
    
    # Check disk space
    local free_space_gb=$(df -g . | awk 'NR==2 {print $4}')
    if [[ ${free_space_gb} -lt ${MIN_DISK_SPACE_GB} ]]; then
        error "Minimum ${MIN_DISK_SPACE_GB}GB free disk space required, found ${free_space_gb}GB"
        return 1
    }
    
    # Check Xcode installation
    if ! xcode-select -p &>/dev/null; then
        error "Xcode must be installed"
        return 1
    }
    
    local xcode_version=$(xcodebuild -version | grep "Xcode" | cut -d' ' -f2)
    if [[ "${xcode_version}" < "${REQUIRED_XCODE_VERSION}" ]]; then
        error "Xcode ${REQUIRED_XCODE_VERSION} or higher is required"
        return 1
    }
    
    # Check processor capabilities
    if ! sysctl -n machdep.cpu.features | grep -q "AVX2"; then
        error "Processor must support AVX2 instructions"
        return 1
    }
    
    log "System requirements check passed"
    return 0
}

install_homebrew_dependencies() {
    log "Installing Homebrew dependencies..."
    
    # Install/update Homebrew
    if ! command -v brew &>/dev/null; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew update
    
    # Install required packages
    brew install cmake@3.26
    brew install llvm@15
    brew install python@3.11
    brew install portaudio@19.7
    brew install juce
    brew install cuda
    
    # Link packages
    brew link cmake
    brew link llvm
    brew link python@3.11
    
    # Verify installations
    local packages=("cmake" "llvm" "python@3.11" "portaudio" "juce" "cuda")
    for package in "${packages[@]}"; do
        if ! brew list | grep -q "^${package}$"; then
            error "Failed to install ${package}"
            return 1
        fi
    done
    
    log "Homebrew dependencies installed successfully"
    return 0
}

setup_python_environment() {
    log "Setting up Python environment..."
    
    # Create virtual environment
    python3.11 -m venv "${PROJECT_DIR}/venv"
    source "${PROJECT_DIR}/venv/bin/activate"
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install required packages
    pip install tensorflow==2.13.0
    pip install torch==2.0.0
    pip install librosa
    pip install soundfile
    pip install pytest
    pip install jupyter
    
    # Verify installations
    if ! python3 -c "import tensorflow as tf; print(tf.__version__)" &>/dev/null; then
        error "TensorFlow installation failed"
        return 1
    fi
    
    log "Python environment setup completed"
    return 0
}

install_cocoapods() {
    log "Installing CocoaPods..."
    
    # Install CocoaPods if not present
    if ! command -v pod &>/dev/null; then
        sudo gem install cocoapods -v 1.12.0
    fi
    
    # Update CocoaPods repos
    pod repo update
    
    # Install pods from Podfile
    cd "${PROJECT_DIR}"
    pod install
    
    if [ $? -ne 0 ]; then
        error "CocoaPods installation failed"
        return 1
    fi
    
    log "CocoaPods installation completed"
    return 0
}

setup_swift_packages() {
    log "Setting up Swift packages..."
    
    cd "${PROJECT_DIR}"
    
    # Update packages
    swift package update
    
    # Build packages
    swift build
    
    if [ $? -ne 0 ]; then
        error "Swift package setup failed"
        return 1
    fi
    
    log "Swift packages setup completed"
    return 0
}

configure_build_environment() {
    log "Configuring build environment..."
    
    # Set up code signing
    if ! security find-identity -v -p codesigning &>/dev/null; then
        error "No valid code signing certificates found"
        return 1
    }
    
    # Configure audio settings
    defaults write com.apple.coreaudiod "Audio HAL Debug" -bool true
    
    # Set up development team
    if [ -f "${PROJECT_DIR}/project.pbxproj" ]; then
        local team_id=$(security find-identity -v -p codesigning | grep "Developer ID" | head -n 1 | cut -d'"' -f2)
        /usr/libexec/PlistBuddy -c "Set :DEVELOPMENT_TEAM ${team_id}" "${PROJECT_DIR}/project.pbxproj"
    fi
    
    log "Build environment configuration completed"
    return 0
}

main() {
    log "Starting TALD UNIA development environment setup..."
    
    # Create backup of existing configuration
    if [ -d "${PROJECT_DIR}/venv" ]; then
        mv "${PROJECT_DIR}/venv" "${PROJECT_DIR}/venv_backup_$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Run setup steps
    check_system_requirements || exit 1
    install_homebrew_dependencies || exit 1
    setup_python_environment || exit 1
    install_cocoapods || exit 1
    setup_swift_packages || exit 1
    configure_build_environment || exit 1
    
    log "Setup completed successfully!"
    log "Log file: ${LOG_FILE}"
    log "Error log file: ${ERROR_LOG_FILE}"
    
    # Generate setup report
    {
        echo "TALD UNIA Setup Report"
        echo "====================="
        echo "Date: $(date)"
        echo "macOS Version: $(sw_vers -productVersion)"
        echo "Xcode Version: $(xcodebuild -version | head -n 1)"
        echo "Python Version: $(python3 --version)"
        echo "CMake Version: $(cmake --version | head -n 1)"
        echo "LLVM Version: $(llvm-config --version)"
    } > "${PROJECT_DIR}/logs/setup_report_$(date +%Y%m%d_%H%M%S).txt"
    
    return 0
}

# Execute main function
main