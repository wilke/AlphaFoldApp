#!/bin/bash
#
# AlphaFold BV-BRC Service Test Script
# Tests the App-AlphaFold.pl service with container execution
#

set -e

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"  # Parent directory (AlphaFoldApp)
SERVICE_SCRIPT="$PROJECT_DIR/service-scripts/App-AlphaFold.pl"
APP_SPEC="$PROJECT_DIR/app_specs/AlphaFold.json"
TEST_FASTA="$PROJECT_DIR/test_protein_small.fasta"
CONTAINER_IMAGE="${ALPHAFOLD_CONTAINER:-$PROJECT_DIR/images/alphafold_unified_patric.sif}"
DATABASES_DIR="${ALPHAFOLD_DB_DIR:-$PROJECT_DIR/databases}"
OUTPUT_DIR="$PROJECT_DIR/test_output_$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

check_requirements() {
    log_info "Checking requirements..."
    
    # Check for Perl and required modules
    if ! command -v perl &> /dev/null; then
        log_error "Perl is not installed"
        exit 1
    fi
    
    # Check for required Perl modules
    perl -MBio::KBase::AppService::AppScript -e 1 2>/dev/null || {
        log_warning "Bio::KBase::AppService::AppScript not found. This is expected outside BV-BRC environment."
    }
    
    # Check for test FASTA file
    if [ ! -f "$TEST_FASTA" ]; then
        log_error "Test FASTA file not found: $TEST_FASTA"
        exit 1
    fi
    
    # Check for container image (if not running in container)
    if [ ! -f "/.singularity.d/Singularity" ] && [ ! -f "$CONTAINER_IMAGE" ]; then
        log_warning "Container image not found: $CONTAINER_IMAGE"
        log_warning "Running without container - AlphaFold must be installed locally"
    fi
    
    # Check for databases
    if [ ! -d "$DATABASES_DIR" ]; then
        log_warning "Databases directory not found: $DATABASES_DIR"
        log_warning "Will attempt to use container's internal databases"
    fi
    
    log_info "Requirements check completed"
}

run_syntax_check() {
    log_info "Checking Perl syntax..."
    perl -c "$SERVICE_SCRIPT" 2>&1 | grep -q "syntax OK" && {
        log_info "Perl syntax check passed"
    } || {
        log_error "Perl syntax check failed"
        exit 1
    }
}

create_test_params() {
    local params_file="$1"
    
    # Use the working parameter format from recipes/params_monomer_reduced.json
    # Using proper BV-BRC workspace path format
    cat > "$params_file" <<EOF
{
    "fasta_paths": "$TEST_FASTA",
    "output_dir": "/output",
    "data_dir": "/databases",
    "model_preset": "monomer",
    "db_preset": "reduced_dbs",
    "max_template_date": "2022-01-01",
    "models_to_relax": "best",
    "use_gpu_relax": false,
    "use_precomputed_msas": false,
    "benchmark": false,
    "random_seed": null,
    "output_path": "/awilke@bvbrc/home/AlphaFold/test_run"
}
EOF
    
    log_info "Created test parameters file: $params_file"
}

run_preflight_test() {
    log_info "Testing preflight resource estimation..."
    
    local params_file="$OUTPUT_DIR/test_params.json"
    create_test_params "$params_file"
    
    export P3_DEBUG=1
    
    # Run preflight (may fail outside BV-BRC environment)
    if perl "$SERVICE_SCRIPT" --preflight "$OUTPUT_DIR/preflight.json" appservice "$APP_SPEC" "$params_file" 2>/dev/null; then
        log_info "Preflight test completed"
        if [ -f "$OUTPUT_DIR/preflight.json" ]; then
            log_info "Resource estimates:"
            cat "$OUTPUT_DIR/preflight.json"
        fi
    else
        log_warning "Preflight test skipped (requires BV-BRC environment)"
    fi
}

run_container_test() {
    log_info "Testing container execution..."
    
    if [ ! -f "$CONTAINER_IMAGE" ]; then
        log_warning "Container test skipped - image not found"
        return
    fi
    
    # Test container launch
    apptainer exec "$CONTAINER_IMAGE" python --version &>/dev/null && {
        log_info "Container execution test passed"
    } || {
        log_error "Container execution test failed"
        return 1
    }
    
    # Test AlphaFold availability in container
    apptainer exec "$CONTAINER_IMAGE" python -c "import alphafold" 2>/dev/null && {
        log_info "AlphaFold module found in container"
    } || {
        log_warning "AlphaFold module not found in container"
    }
}

run_small_prediction() {
    log_info "Running small test prediction..."
    
    local params_file="$OUTPUT_DIR/test_params.json"
    create_test_params "$params_file"
    
    # Set environment for testing
    export P3_DEBUG=1
    export P3_ALLOCATED_CPU=8
    export P3_ALLOCATED_MEMORY="64G"
    export ALPHAFOLD_CONTAINER="$CONTAINER_IMAGE"
    export ALPHAFOLD_DB_DIR="$DATABASES_DIR"
    
    # For testing without workspace access
    export TEST_OUTPUT_DIR="$OUTPUT_DIR/alphafold_results"
    
    log_info "Executing: $SERVICE_SCRIPT test_job $APP_SPEC $params_file"
    log_info "Note: Running in test mode without workspace access"
    
    # Run the actual prediction
    if perl "$SERVICE_SCRIPT" test_job "$APP_SPEC" "$params_file" 2>&1 | tee "$OUTPUT_DIR/test_run.log"; then
        log_info "Test prediction completed successfully"
        
        # Check for output files
        if [ -d "$OUTPUT_DIR/work" ]; then
            log_info "Output files generated:"
            find "$OUTPUT_DIR/work" -type f -name "*.pdb" | head -5
        fi
    else
        log_error "Test prediction failed"
        return 1
    fi
}

cleanup() {
    if [ -d "$OUTPUT_DIR" ] && [ "$KEEP_OUTPUT" != "1" ]; then
        log_info "Cleaning up test output directory"
        rm -rf "$OUTPUT_DIR"
    else
        log_info "Test output preserved in: $OUTPUT_DIR"
    fi
}

# Main execution
main() {
    log_info "Starting AlphaFold service tests"
    log_info "Script directory: $SCRIPT_DIR"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Run tests
    check_requirements
    run_syntax_check
    
    if [ "$1" == "--quick" ]; then
        log_info "Quick test mode - skipping prediction"
        run_preflight_test
        run_container_test
    else
        run_preflight_test
        run_container_test
        run_small_prediction
    fi
    
    # Cleanup (unless KEEP_OUTPUT=1)
    trap cleanup EXIT
    
    log_info "All tests completed"
}

# Show usage
if [ "$1" == "--help" ]; then
    echo "Usage: $0 [--quick] [--keep]"
    echo ""
    echo "Options:"
    echo "  --quick    Run quick tests only (no prediction)"
    echo "  --keep     Keep test output directory"
    echo ""
    echo "Environment variables:"
    echo "  ALPHAFOLD_CONTAINER  Path to container image"
    echo "  ALPHAFOLD_DB_DIR     Path to AlphaFold databases"
    echo "  P3_DEBUG             Enable debug output"
    exit 0
fi

# Parse options
if [ "$1" == "--keep" ] || [ "$2" == "--keep" ]; then
    export KEEP_OUTPUT=1
fi

# Run main
main "$@"