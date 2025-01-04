#!/bin/bash

# TALD UNIA Audio System - SwiftLint Script
# Version: 1.0
# Purpose: Executes SwiftLint to enforce code style and quality standards

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SWIFTLINT_CONFIG="../swiftlint.yml"
readonly SOURCE_DIR="../TALDUnia"
readonly LOG_FILE="/tmp/swiftlint_$(date +%Y%m%d_%H%M%S).log"
readonly MIN_SWIFTLINT_VERSION="0.52.0"
EXIT_CODE=0

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message=$*
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Version comparison function
version_compare() {
    local version1=$1
    local version2=$2
    if [[ "$(printf '%s\n' "$version1" "$version2" | sort -V | head -n1)" == "$version2" ]]; then
        return 0
    else
        return 1
    fi
}

# Check if SwiftLint is installed with correct version
check_swiftlint_installed() {
    log "INFO" "Checking SwiftLint installation..."
    
    if ! command -v swiftlint &> /dev/null; then
        log "ERROR" "SwiftLint is not installed. Please install SwiftLint using: brew install swiftlint"
        return 1
    fi

    local installed_version=$(swiftlint version)
    if ! version_compare "${installed_version}" "${MIN_SWIFTLINT_VERSION}"; then
        log "ERROR" "SwiftLint version ${installed_version} is below minimum required version ${MIN_SWIFTLINT_VERSION}"
        return 1
    }

    log "INFO" "Found SwiftLint version ${installed_version}"
    return 0
}

# Validate environment and prerequisites
validate_environment() {
    log "INFO" "Validating environment..."

    # Check SwiftLint configuration file
    if [[ ! -f "${SCRIPT_DIR}/${SWIFTLINT_CONFIG}" ]]; then
        log "ERROR" "SwiftLint configuration file not found at: ${SCRIPT_DIR}/${SWIFTLINT_CONFIG}"
        return 1
    fi

    # Check source directory
    if [[ ! -d "${SCRIPT_DIR}/${SOURCE_DIR}" ]]; then
        log "ERROR" "Source directory not found at: ${SCRIPT_DIR}/${SOURCE_DIR}"
        return 1
    fi

    # Check for Swift files
    local swift_files_count=$(find "${SCRIPT_DIR}/${SOURCE_DIR}" -name "*.swift" | wc -l)
    if [[ ${swift_files_count} -eq 0 ]]; then
        log "ERROR" "No Swift files found in source directory"
        return 1
    fi

    # Ensure log directory is writable
    local log_dir=$(dirname "${LOG_FILE}")
    if [[ ! -w "${log_dir}" ]]; then
        log "ERROR" "Cannot write to log directory: ${log_dir}"
        return 1
    }

    log "INFO" "Environment validation successful"
    return 0
}

# Run SwiftLint
run_swiftlint() {
    log "INFO" "Starting SwiftLint analysis..."
    
    local start_time=$(date +%s)
    local lint_output
    local lint_exit_code=0

    # Change to script directory
    cd "${SCRIPT_DIR}"

    # Run SwiftLint with configuration
    lint_output=$(swiftlint lint \
        --config "${SWIFTLINT_CONFIG}" \
        --path "${SOURCE_DIR}" \
        --reporter xcode \
        2>&1) || lint_exit_code=$?

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Log full output
    echo "${lint_output}" >> "${LOG_FILE}"

    # Parse and display results
    local error_count=$(echo "${lint_output}" | grep -c "error:" || true)
    local warning_count=$(echo "${lint_output}" | grep -c "warning:" || true)

    # Display summary
    echo -e "\n${YELLOW}SwiftLint Analysis Summary:${NC}"
    echo -e "Duration: ${duration} seconds"
    echo -e "Errors: ${RED}${error_count}${NC}"
    echo -e "Warnings: ${YELLOW}${warning_count}${NC}"

    if [[ ${lint_exit_code} -ne 0 ]]; then
        log "ERROR" "SwiftLint analysis failed with exit code: ${lint_exit_code}"
        echo -e "\n${RED}SwiftLint found critical issues. Please fix them before committing.${NC}"
        return ${lint_exit_code}
    elif [[ ${error_count} -gt 0 ]]; then
        log "WARNING" "SwiftLint found ${error_count} error(s)"
        echo -e "\n${YELLOW}Please fix the above issues before committing.${NC}"
        return 1
    else
        log "INFO" "SwiftLint analysis completed successfully"
        echo -e "\n${GREEN}Code analysis passed!${NC}"
        return 0
    fi
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ -f "${LOG_FILE}" ]]; then
        log "INFO" "Analysis log saved to: ${LOG_FILE}"
    fi
    exit ${exit_code}
}

# Main execution
main() {
    # Set up cleanup trap
    trap cleanup EXIT

    # Print header
    echo -e "${GREEN}TALD UNIA Audio System - Code Quality Check${NC}"
    echo -e "${YELLOW}Running SwiftLint analysis...${NC}\n"

    # Initialize log file
    : > "${LOG_FILE}"
    log "INFO" "Starting code analysis"

    # Run checks
    check_swiftlint_installed || exit 1
    validate_environment || exit 1
    run_swiftlint
    EXIT_CODE=$?

    return ${EXIT_CODE}
}

# Execute main function
main