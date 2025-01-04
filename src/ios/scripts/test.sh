#!/bin/bash

# TALD UNIA iOS Test Suite Runner
# Version: 1.0.0
# Dependencies:
# - xcodebuild (Latest) - Xcode command line tool for building and testing
# - xcpretty (0.3.0) - Test output formatting and report generation
# - junit2html (0.1.0) - Converting JUnit XML reports to HTML format

# Exit on any error
set -e

# Configuration
WORKSPACE="TALDUnia.xcworkspace"
SCHEME="TALDUnia"
CONFIGURATION="Debug"
DESTINATION="platform=iOS Simulator,name=iPhone 14 Pro"
TEST_TIMEOUT=3600
RETRY_COUNT=3
MIN_COVERAGE=80
TEST_RESULTS_DIR="test_results"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to validate test environment
validate_environment() {
    echo "Validating test environment..."
    
    # Check Xcode installation
    if ! command -v xcodebuild &> /dev/null; then
        echo -e "${RED}Error: xcodebuild not found. Please install Xcode.${NC}"
        exit 1
    fi
    
    # Check xcpretty installation
    if ! command -v xcpretty &> /dev/null; then
        echo -e "${YELLOW}Warning: xcpretty not found. Installing...${NC}"
        gem install xcpretty
    fi
    
    # Check junit2html installation
    if ! command -v junit2html &> /dev/null; then
        echo -e "${YELLOW}Warning: junit2html not found. Installing...${NC}"
        pip install junit2html
    fi
    
    # Verify simulator availability
    if ! xcrun simctl list devices | grep -q "iPhone 14 Pro"; then
        echo -e "${RED}Error: iPhone 14 Pro simulator not found.${NC}"
        exit 1
    fi
    
    # Check available disk space (minimum 10GB)
    available_space=$(df -k . | awk 'NR==2 {print $4}')
    if [ $available_space -lt 10485760 ]; then
        echo -e "${RED}Error: Insufficient disk space. At least 10GB required.${NC}"
        exit 1
    }
}

# Function to setup test environment
setup_test_environment() {
    echo "Setting up test environment..."
    
    # Clean build directory
    xcodebuild clean \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        | xcpretty
    
    # Create test results directory
    rm -rf "$TEST_RESULTS_DIR"
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Initialize code coverage
    echo "Setting up code coverage..."
    defaults write com.apple.dt.XCTest CodeCoverageEnabled -bool YES
}

# Function to run test suite with retry mechanism
run_test_suite() {
    local test_suite=$1
    local test_type=$2
    local attempt=1
    local success=false
    
    while [ $attempt -le $RETRY_COUNT ] && [ "$success" = false ]; do
        echo "Running $test_type tests (Attempt $attempt/$RETRY_COUNT)..."
        
        if xcodebuild test \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -destination "$DESTINATION" \
            -only-testing:"$test_suite" \
            -enableCodeCoverage YES \
            | tee /dev/tty \
            | xcpretty --report junit --output "$TEST_RESULTS_DIR/$test_type-report.xml"; then
            success=true
        else
            echo -e "${YELLOW}Test attempt $attempt failed. Retrying...${NC}"
            sleep 5
            ((attempt++))
        fi
    done
    
    if [ "$success" = false ]; then
        echo -e "${RED}Failed to run $test_type tests after $RETRY_COUNT attempts.${NC}"
        return 1
    fi
    
    return 0
}

# Function to generate test reports
generate_reports() {
    echo "Generating test reports..."
    
    # Convert JUnit reports to HTML
    for xml_report in "$TEST_RESULTS_DIR"/*-report.xml; do
        if [ -f "$xml_report" ]; then
            junit2html "$xml_report" "${xml_report%.xml}.html"
        fi
    done
    
    # Generate code coverage report
    xcodebuild test \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "$DESTINATION" \
        -enableCodeCoverage YES \
        -derivedDataPath "$TEST_RESULTS_DIR/DerivedData" \
        | xcpretty --report html --output "$TEST_RESULTS_DIR/coverage-report.html"
    
    # Check coverage threshold
    coverage=$(xcrun xccov view --report "$TEST_RESULTS_DIR/DerivedData/Logs/Test/*.xcresult" | grep "TALDUnia" | awk '{print $3}' | sed 's/%//')
    if [ -n "$coverage" ] && [ ${coverage%.*} -lt $MIN_COVERAGE ]; then
        echo -e "${RED}Error: Code coverage ${coverage}% is below minimum threshold of ${MIN_COVERAGE}%.${NC}"
        return 1
    fi
}

# Main execution
main() {
    echo "Starting TALD UNIA iOS test suite..."
    
    # Validate and setup environment
    validate_environment
    setup_test_environment
    
    # Run test suites
    run_test_suite "TALDUniaTests/AudioEngineTests" "audio-engine" || exit 1
    run_test_suite "TALDUniaTests/DSPProcessorTests" "dsp-processor" || exit 1
    run_test_suite "TALDUniaTests/AIEngineTests" "ai-engine" || exit 1
    
    # Generate reports
    generate_reports || exit 1
    
    echo -e "${GREEN}All tests completed successfully.${NC}"
}

# Execute main function with timeout
timeout $TEST_TIMEOUT main
exit_code=$?

if [ $exit_code -eq 124 ]; then
    echo -e "${RED}Error: Test execution timed out after ${TEST_TIMEOUT} seconds.${NC}"
    exit 1
elif [ $exit_code -ne 0 ]; then
    echo -e "${RED}Error: Test execution failed with exit code $exit_code.${NC}"
    exit $exit_code
fi

exit 0