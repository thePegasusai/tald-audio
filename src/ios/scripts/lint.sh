#!/bin/bash

# TALD UNIA iOS Application Linting Script
# Version: 1.0
# SwiftLint Version: 0.51.0

# Global variables
SWIFTLINT_CONFIG="../swiftlint.yml"
PROJECT_ROOT="../"
REQUIRED_SWIFTLINT_VERSION="0.51.0"
MAX_WARNINGS=50
LINT_TIMEOUT=300

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check SwiftLint installation and version
check_swiftlint_installation() {
    if ! command -v swiftlint &> /dev/null; then
        echo -e "${RED}Error: SwiftLint not found. Please install version ${REQUIRED_SWIFTLINT_VERSION} via CocoaPods or Homebrew.${NC}"
        exit 1
    fi

    local installed_version=$(swiftlint version)
    if [ "$installed_version" != "$REQUIRED_SWIFTLINT_VERSION" ]; then
        echo -e "${RED}Error: SwiftLint version mismatch. Required: ${REQUIRED_SWIFTLINT_VERSION}, Found: ${installed_version}${NC}"
        exit 2
    fi

    if [ ! -f "$SWIFTLINT_CONFIG" ]; then
        echo -e "${RED}Error: SwiftLint configuration file not found at ${SWIFTLINT_CONFIG}${NC}"
        exit 5
    fi
}

# Function to generate HTML report
generate_report() {
    local output_dir="reports/swiftlint"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local report_file="${output_dir}/lint_report_${timestamp}.html"
    
    mkdir -p "$output_dir"
    
    # Create HTML report header
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>TALD UNIA SwiftLint Report</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 20px; }
        .error { color: #D00; }
        .warning { color: #F90; }
        .summary { background: #F5F5F5; padding: 10px; margin: 10px 0; }
    </style>
</head>
<body>
    <h1>TALD UNIA SwiftLint Report</h1>
    <div class="summary">
        <h2>Summary</h2>
        <p>Generated: $(date)</p>
        <p>SwiftLint Version: ${REQUIRED_SWIFTLINT_VERSION}</p>
EOF

    # Parse SwiftLint output and add to report
    echo "$1" | awk '
        BEGIN { print "<h2>Violations</h2><ul>" }
        /^[^:]+:[0-9]+:[0-9]+: (warning|error):/ {
            severity = substr($0, index($0, ": ") + 2)
            severity = substr(severity, 1, index(severity, ":") - 1)
            message = substr($0, index($0, severity ": ") + length(severity) + 2)
            file = substr($0, 1, index($0, ":") - 1)
            printf "<li class=\"%s\">%s: %s in %s</li>\n", severity, severity, message, file
        }
        END { print "</ul>" }
    ' >> "$report_file"

    # Close HTML report
    echo "</body></html>" >> "$report_file"
    
    echo "$report_file"
}

# Function to run SwiftLint
run_swiftlint() {
    local start_time=$(date +%s)
    
    # Change to project root directory
    cd "$PROJECT_ROOT" || {
        echo -e "${RED}Error: Could not change to project root directory${NC}"
        exit 1
    }
    
    # Run SwiftLint with timeout
    local lint_output
    if ! lint_output=$(timeout "$LINT_TIMEOUT" swiftlint --config "$SWIFTLINT_CONFIG" 2>&1); then
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo -e "${RED}Error: SwiftLint execution timed out after ${LINT_TIMEOUT} seconds${NC}"
            exit 4
        fi
    fi

    # Count warnings and errors
    local warning_count=$(echo "$lint_output" | grep -c ": warning:")
    local error_count=$(echo "$lint_output" | grep -c ": error:")
    
    # Generate report
    local report_path=$(generate_report "$lint_output")
    
    # Print summary
    echo -e "\n${GREEN}SwiftLint Analysis Complete${NC}"
    echo -e "Found ${YELLOW}${warning_count} warnings${NC} and ${RED}${error_count} errors${NC}"
    echo -e "Detailed report available at: ${report_path}"
    
    # Check against maximum warnings
    if [ "$warning_count" -gt "$MAX_WARNINGS" ]; then
        echo -e "${RED}Error: Too many warnings (${warning_count}). Maximum allowed: ${MAX_WARNINGS}${NC}"
        exit 3
    fi
    
    # Exit with error if there are any errors
    if [ "$error_count" -gt 0 ]; then
        echo -e "${RED}Error: Found ${error_count} linting errors${NC}"
        exit 3
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo -e "${GREEN}Linting completed in ${duration} seconds${NC}"
}

# Main execution
echo "Starting TALD UNIA iOS linting process..."
check_swiftlint_installation
run_swiftlint