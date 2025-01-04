#!/bin/bash

# TALD UNIA iOS Development Environment Bootstrap Script
# Version: 1.0.0
# Purpose: Setup and validate development environment with enhanced security and performance optimizations

# Enable error handling and logging
set -euo pipefail
set -x

# Global variables
REQUIRED_XCODE_VERSION="14.0"
REQUIRED_RUBY_VERSION="3.2.0"
REQUIRED_IOS_VERSION="15.0"
REQUIRED_COCOAPODS_VERSION="1.14.0"
REQUIRED_SWIFTLINT_VERSION="0.52.0"
REQUIRED_DANGER_VERSION="9.0.0"
BUILD_CACHE_DIR="${HOME}/.tald_unia_cache"
SECURITY_AUDIT_LOG="${HOME}/.tald_unia_security_audit.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function with timestamp
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Security audit logging
log_security_audit() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$SECURITY_AUDIT_LOG"
}

check_prerequisites() {
    log "Checking prerequisites..."

    # Verify Xcode installation
    if ! command -v xcodebuild &> /dev/null; then
        error "Xcode not found. Please install Xcode from the App Store"
    fi

    XCODE_VERSION=$(xcodebuild -version | head -n1 | awk '{print $2}')
    if [[ "$XCODE_VERSION" < "$REQUIRED_XCODE_VERSION" ]]; then
        error "Xcode version $REQUIRED_XCODE_VERSION or higher is required (found $XCODE_VERSION)"
    }

    # Verify Ruby installation and version
    if ! command -v rbenv &> /dev/null; then
        error "rbenv not found. Please install rbenv first"
    fi

    if [[ "$(rbenv version | cut -d' ' -f1)" != "$REQUIRED_RUBY_VERSION" ]]; then
        log "Installing Ruby $REQUIRED_RUBY_VERSION..."
        rbenv install "$REQUIRED_RUBY_VERSION"
        rbenv global "$REQUIRED_RUBY_VERSION"
    fi

    # Verify development certificates
    if ! security find-identity -v -p codesigning | grep -q "Developer ID"; then
        warn "No valid development certificates found. Some features may be limited"
        log_security_audit "Missing development certificates"
    fi

    # Create and secure build cache directory
    if [[ ! -d "$BUILD_CACHE_DIR" ]]; then
        mkdir -p "$BUILD_CACHE_DIR"
        chmod 700 "$BUILD_CACHE_DIR"
    fi

    log "Prerequisites check completed"
}

install_ruby_dependencies() {
    log "Installing Ruby dependencies..."

    # Install bundler with version verification
    gem install bundler -v "2.4.0" --no-document || error "Failed to install bundler"

    # Configure bundler for parallel installation
    bundle config --global jobs 4
    bundle config --global path vendor/bundle

    # Install gems from Gemfile
    bundle install || error "Failed to install Ruby dependencies"

    log "Ruby dependencies installed successfully"
}

setup_cocoapods() {
    log "Setting up CocoaPods..."

    # Install CocoaPods if needed
    if ! command -v pod &> /dev/null || [[ "$(pod --version)" != "$REQUIRED_COCOAPODS_VERSION" ]]; then
        gem install cocoapods -v "$REQUIRED_COCOAPODS_VERSION" --no-document
    fi

    # Setup CocoaPods repo
    pod setup --verbose

    # Install pod dependencies with cache
    pod install --repo-update --verbose || error "Failed to install pod dependencies"

    log "CocoaPods setup completed"
}

setup_swift_packages() {
    log "Setting up Swift packages..."

    # Clear package cache if needed
    if [[ -d ~/Library/Caches/org.swift.swiftpm ]]; then
        rm -rf ~/Library/Caches/org.swift.swiftpm
    fi

    # Update Swift package dependencies
    swift package update || error "Failed to update Swift packages"
    swift package resolve || error "Failed to resolve Swift packages"

    log "Swift packages setup completed"
}

configure_development_environment() {
    log "Configuring development environment..."

    # Install SwiftLint
    if ! command -v swiftlint &> /dev/null; then
        brew install swiftlint
    fi

    # Install Danger
    if ! command -v danger &> /dev/null; then
        npm install -g danger
    fi

    # Configure Xcode build settings
    defaults write com.apple.dt.Xcode IDEBuildOperationMaxNumberOfConcurrentCompileTasks 8
    defaults write com.apple.dt.Xcode BuildSystemScheduleInherentlyParallelCommandsSerially -bool NO

    # Setup security audit logging
    touch "$SECURITY_AUDIT_LOG"
    chmod 600 "$SECURITY_AUDIT_LOG"

    log "Development environment configured successfully"
}

cleanup() {
    log "Performing cleanup..."
    
    # Remove temporary files
    rm -rf ~/Library/Developer/Xcode/DerivedData/*
    rm -rf ~/Library/Caches/CocoaPods/*
    
    # Clear old build cache entries
    find "$BUILD_CACHE_DIR" -type f -mtime +7 -delete

    log "Cleanup completed"
}

main() {
    log "Starting TALD UNIA iOS development environment setup..."

    # Create timestamp for audit
    log_security_audit "Bootstrap script started"

    # Execute setup steps
    check_prerequisites
    install_ruby_dependencies
    setup_cocoapods
    setup_swift_packages
    configure_development_environment
    cleanup

    log_security_audit "Bootstrap script completed successfully"
    log "TALD UNIA iOS development environment setup completed successfully"
}

# Execute main function
main