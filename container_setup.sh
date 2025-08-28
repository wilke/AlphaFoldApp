#!/bin/bash
#
# Container Setup Script for AlphaFold BV-BRC Service
# Run this inside the container to set up required environment
#

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== AlphaFold Container Setup ===${NC}"

# Check if we're inside the container
if [ ! -f "/app/alphafold/run_alphafold.py" ]; then
    echo -e "${RED}[ERROR]${NC} This script must be run inside the AlphaFold container!"
    echo "Please start the container first with:"
    echo "  apptainer shell --nv --writable-tmpfs [bindings...] alphafold_unified_patric.sif"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Detected AlphaFold container environment"

# Create Python symlink
RUNTIME_BIN="/opt/patric-common/runtime/bin"
CONDA_PYTHON="/opt/conda/bin/python"

if [ ! -d "$RUNTIME_BIN" ]; then
    echo -e "${YELLOW}[WARNING]${NC} Runtime bin directory doesn't exist: $RUNTIME_BIN"
    echo -e "${YELLOW}[WARNING]${NC} Creating directory..."
    mkdir -p "$RUNTIME_BIN"
fi

cd "$RUNTIME_BIN"

if [ -f "python" ] || [ -L "python" ]; then
    echo -e "${YELLOW}[WARNING]${NC} Python link already exists at $RUNTIME_BIN/python"
    echo -e "${YELLOW}[WARNING]${NC} Checking if it points to the correct location..."
    
    CURRENT_LINK=$(readlink -f python 2>/dev/null || echo "not a link")
    if [ "$CURRENT_LINK" = "$CONDA_PYTHON" ]; then
        echo -e "${GREEN}[OK]${NC} Python link is correctly configured"
    else
        echo -e "${YELLOW}[WARNING]${NC} Removing incorrect link and recreating..."
        rm -f python
        ln -s "$CONDA_PYTHON" python
        echo -e "${GREEN}[OK]${NC} Python link recreated"
    fi
else
    echo -e "${GREEN}[INFO]${NC} Creating Python symlink..."
    ln -s "$CONDA_PYTHON" python
    echo -e "${GREEN}[OK]${NC} Python link created successfully"
fi

# Verify Python works
echo -e "${GREEN}[INFO]${NC} Verifying Python installation..."
if $RUNTIME_BIN/python --version 2>&1 | grep -q "Python 3"; then
    PYTHON_VERSION=$($RUNTIME_BIN/python --version 2>&1)
    echo -e "${GREEN}[OK]${NC} $PYTHON_VERSION is available at $RUNTIME_BIN/python"
else
    echo -e "${RED}[ERROR]${NC} Python verification failed!"
    exit 1
fi

# Check AlphaFold module
echo -e "${GREEN}[INFO]${NC} Checking AlphaFold module..."
if $RUNTIME_BIN/python -c "import alphafold" 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} AlphaFold module is accessible"
else
    echo -e "${YELLOW}[WARNING]${NC} AlphaFold module import failed - this may be normal outside /app/alphafold/"
fi

# Check database availability
echo -e "${GREEN}[INFO]${NC} Checking database availability..."
if [ -d "/databases" ]; then
    echo -e "${GREEN}[OK]${NC} Database directory found at /databases"
    
    # Check for key databases
    for db in params small_bfd mgnify uniref90 pdb70 pdb_mmcif; do
        if [ -d "/databases/$db" ]; then
            echo -e "  ${GREEN}✓${NC} $db"
        else
            echo -e "  ${YELLOW}✗${NC} $db (not found)"
        fi
    done
else
    echo -e "${YELLOW}[WARNING]${NC} Database directory not found at /databases"
    echo -e "${YELLOW}[WARNING]${NC} You may need to mount databases when starting the container"
fi

# Check BV-BRC modules
echo -e "${GREEN}[INFO]${NC} Checking BV-BRC modules..."
if perl -e 'use Bio::KBase::AppService::AppScript; print "OK\n"' 2>/dev/null | grep -q OK; then
    echo -e "${GREEN}[OK]${NC} BV-BRC AppService modules are available"
else
    echo -e "${YELLOW}[WARNING]${NC} BV-BRC modules not found - this is expected if not in dev_container"
fi

# Final status
echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. If databases are not mounted, restart container with --bind /path/to/databases:/databases"
echo "2. Run the test script: ./run_simple_test.sh"
echo "3. Or run directly: perl service-scripts/App-AlphaFold.pl test_job app_specs/AlphaFold.json recipes/params_monomer_reduced.json"
echo ""
echo -e "${GREEN}[SUCCESS]${NC} Container is ready for AlphaFold execution!"