#!/bin/bash

# TALD UNIA Audio System Test Suite
# Version: 1.0.0
# Comprehensive test execution script for macOS with ESS ES9038PRO DAC integration

# Exit on any error
set -e

# Global constants
readonly TEST_SCHEME="TALDUnia"
readonly TEST_DESTINATION="platform=macOS"
readonly BUILD_CONFIG="Debug"
readonly DERIVED_DATA_PATH="./DerivedData"
readonly HARDWARE_CONFIG="/etc/tald/hardware/es9038pro.conf"
readonly PERFORMANCE_THRESHOLDS="/etc/tald/thresholds/performance.json"
readonly TEST_PARALLELISM=4
readonly RETRY_COUNT=3

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Function to log messages with timestamp
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check for required tools and configurations
setup_test_environment() {
    log "${YELLOW}Setting up test environment...${NC}"

    # Check for Xcode installation
    if ! command -v xcodebuild &> /dev/null; then
        log "${RED}Error: Xcode command line tools not found${NC}"
        exit 1
    fi

    # Verify Xcode version
    local xcode_version=$(xcodebuild -version | head -n 1 | awk '{print $2}')
    if [[ "${xcode_version}" < "14.0" ]]; then
        log "${RED}Error: Xcode 14.0 or higher required, found ${xcode_version}${NC}"
        exit 1
    }

    # Check for xcpretty
    if ! command -v xcpretty &> /dev/null; then
        log "${YELLOW}Installing xcpretty...${NC}"
        gem install xcpretty
    fi

    # Verify hardware configuration
    if [ ! -f "${HARDWARE_CONFIG}" ]; then
        log "${RED}Error: Hardware configuration not found at ${HARDWARE_CONFIG}${NC}"
        exit 1
    fi

    # Clean derived data
    if [ -d "${DERIVED_DATA_PATH}" ]; then
        log "${YELLOW}Cleaning derived data...${NC}"
        rm -rf "${DERIVED_DATA_PATH}"
    fi

    log "${GREEN}Test environment setup complete${NC}"
}

# Function to run unit tests
run_unit_tests() {
    log "${YELLOW}Running unit tests...${NC}"

    local test_command="xcodebuild test \
        -scheme ${TEST_SCHEME} \
        -destination '${TEST_DESTINATION}' \
        -configuration ${BUILD_CONFIG} \
        -derivedDataPath ${DERIVED_DATA_PATH} \
        -parallel-testing-enabled YES \
        -parallel-testing-worker-count ${TEST_PARALLELISM} \
        HARDWARE_CONFIG=${HARDWARE_CONFIG}"

    local attempt=1
    local success=false

    while [ $attempt -le $RETRY_COUNT ] && [ "$success" = false ]; do
        log "Test attempt ${attempt}/${RETRY_COUNT}"
        
        if eval "${test_command}" | xcpretty --color --test; then
            success=true
            log "${GREEN}Unit tests passed successfully${NC}"
        else
            if [ $attempt -eq $RETRY_COUNT ]; then
                log "${RED}Unit tests failed after ${RETRY_COUNT} attempts${NC}"
                return 1
            fi
            log "${YELLOW}Test attempt ${attempt} failed, retrying...${NC}"
            sleep 5
        fi
        
        ((attempt++))
    done
}

# Function to run performance tests
run_performance_tests() {
    log "${YELLOW}Running performance tests...${NC}"

    # Configure performance monitoring
    local perf_command="xcodebuild test \
        -scheme ${TEST_SCHEME} \
        -destination '${TEST_DESTINATION}' \
        -configuration ${BUILD_CONFIG} \
        -derivedDataPath ${DERIVED_DATA_PATH} \
        -only-testing:TALDUniaTests/DSPProcessorTests/testProcessingLatency \
        -only-testing:TALDUniaTests/AIEngineTests/testHardwareOptimizedPerformance \
        PERFORMANCE_THRESHOLDS=${PERFORMANCE_THRESHOLDS}"

    if ! eval "${perf_command}" | xcpretty --color --test; then
        log "${RED}Performance tests failed${NC}"
        return 1
    fi

    log "${GREEN}Performance tests completed successfully${NC}"
}

# Function to generate test report
generate_test_report() {
    log "${YELLOW}Generating test report...${NC}"

    local report_dir="${DERIVED_DATA_PATH}/Reports"
    mkdir -p "${report_dir}"

    # Collect test results
    local test_logs="${DERIVED_DATA_PATH}/Logs/Test"
    if [ -d "${test_logs}" ]; then
        # Generate HTML report
        xcpretty --report html --output "${report_dir}/test_report.html"
        
        # Generate JUnit report
        xcpretty --report junit --output "${report_dir}/junit.xml"
        
        # Generate coverage report if available
        if [ -d "${DERIVED_DATA_PATH}/Logs/Test/Coverage" ]; then
            xcrun xccov view --report --json \
                "${DERIVED_DATA_PATH}/Logs/Test/Coverage.xcresult" \
                > "${report_dir}/coverage.json"
        fi
    fi

    log "${GREEN}Test reports generated at ${report_dir}${NC}"
}

# Main execution flow
main() {
    log "${YELLOW}Starting TALD UNIA test suite execution${NC}"

    # Setup environment
    setup_test_environment || exit 1

    # Run tests
    run_unit_tests || exit 1
    run_performance_tests || exit 1

    # Generate reports
    generate_test_report

    log "${GREEN}Test suite execution completed successfully${NC}"
}

# Execute main function
main