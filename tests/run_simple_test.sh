#!/bin/bash
#
# Simple AlphaFold test runner using known working parameters
#

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[INFO]${NC} Simple AlphaFold Test Runner"
echo -e "${GREEN}[INFO]${NC} Using known working parameters from recipes/params_monomer_reduced.json"

# Get project directory (parent of tests/)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Create a test parameters file based on the working recipe
cat > "$SCRIPT_DIR/test_params_local.json" <<EOF
{
  "fasta_paths": "$PROJECT_DIR/test_protein_small.fasta",
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

echo -e "${GREEN}[INFO]${NC} Created $SCRIPT_DIR/test_params_local.json"

# Set environment for debugging
export P3_DEBUG=1
export P3_LOG_LEVEL=DEBUG

# Check if we're in container
if [ -f "/.singularity.d/Singularity" ] || [ -f "/app/alphafold/run_alphafold.py" ]; then
    echo -e "${GREEN}[INFO]${NC} Running inside container"
    
    # Check database availability
    if [ -d "/databases" ]; then
        echo -e "${GREEN}[INFO]${NC} Databases found at /databases"
        ls -la /databases/ | head -5
    else
        echo -e "${YELLOW}[WARNING]${NC} Databases not found at /databases"
    fi
else
    echo -e "${YELLOW}[WARNING]${NC} Not running inside container"
fi

# Change to project directory for execution
cd "$PROJECT_DIR"

# Run the AlphaFold service
echo -e "${GREEN}[INFO]${NC} Starting AlphaFold service..."
echo -e "${GREEN}[INFO]${NC} Command: perl service-scripts/App-AlphaFold.pl test_job app_specs/AlphaFold.json tests/test_params_local.json"

# Create a minimal workspace directory
mkdir -p test_workspace_local

# Run with explicit error handling
if perl service-scripts/App-AlphaFold.pl test_job app_specs/AlphaFold.json "$SCRIPT_DIR/test_params_local.json" 2>&1 | tee "$SCRIPT_DIR/test_run_local.log"; then
    echo -e "${GREEN}[SUCCESS]${NC} Test completed successfully"
    
    # Check for output files
    if [ -d "work" ]; then
        echo -e "${GREEN}[INFO]${NC} Output files in work directory:"
        find work -type f -name "*.pdb" 2>/dev/null | head -5
        find work -type f -name "*.json" 2>/dev/null | head -5
    fi
else
    echo -e "${RED}[ERROR]${NC} Test failed. Check test_run_local.log for details"
    
    # Show last few lines of log
    echo -e "${YELLOW}[INFO]${NC} Last 10 lines of log:"
    tail -10 "$SCRIPT_DIR/test_run_local.log"
    
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Test complete. Results in work/ directory and tests/test_run_local.log"