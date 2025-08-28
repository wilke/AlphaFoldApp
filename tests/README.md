# AlphaFold BV-BRC Service - Test Suite

This directory contains test scripts and configurations for the AlphaFold BV-BRC service.

## Test Scripts

### run_simple_test.sh
Quick test script that runs AlphaFold with minimal configuration.
- Uses reduced databases for faster execution
- Tests with a small protein (73 amino acids)
- Validates end-to-end functionality
- Creates `test_params_local.json` automatically

**Usage:**
```bash
# From project root:
./tests/run_simple_test.sh

# From tests directory:
./run_simple_test.sh
```

### test_alphafold.sh
Comprehensive test suite with multiple options.
- Includes preflight testing
- Container validation
- Resource estimation checks
- Support for quick mode (no prediction)

**Usage:**
```bash
# Quick test (no AlphaFold execution):
./tests/test_alphafold.sh --quick

# Full test with prediction:
./tests/test_alphafold.sh

# Keep output files:
./tests/test_alphafold.sh --keep
```

## Test Configurations

### Pre-configured Test Cases

- `small_monomer_test/` - Small single-chain protein test
  - Parameters: monomer preset, reduced databases
  - Expected runtime: ~30 minutes

- `medium_monomer_ptm_test/` - Medium protein with confidence metrics
  - Parameters: monomer_ptm preset, reduced databases
  - Expected runtime: ~45 minutes

### Generated Files

- `test_params_local.json` - Auto-generated parameters for testing
- `test_run_local.log` - Log output from test runs
- Test outputs remain in project root `work/` directory

## Running Tests

### Prerequisites

1. **Container Setup** (if not already done):
   ```bash
   cd /opt/patric-common/runtime/bin/
   ln -s /opt/conda/bin/python python
   ```
   Or run: `./container_setup.sh` from project root

2. **Database Access**: Ensure databases are mounted at `/databases`

3. **Workspace Credentials**: Login with `p3-login` if testing workspace integration

### Quick Validation

For a quick validation that everything is working:
```bash
./tests/run_simple_test.sh
```

This will:
- Create test parameters
- Run AlphaFold on a small test protein
- Generate 5 structure models
- Save outputs to workspace (if available)

### Expected Output

Successful test run produces:
```
work/test_protein_small/
├── ranked_0.pdb through ranked_4.pdb  # Final structures
├── confidence_model_*.json            # Confidence scores
├── timings.json                       # Performance metrics
└── msas/                              # Sequence alignments
```

## Troubleshooting

If tests fail:
1. Check Python symlink exists (see Prerequisites)
2. Verify databases are accessible
3. Review log files in `tests/` directory
4. Ensure sufficient memory (minimum 32GB)
5. Check container is properly started with GPU support (if available)

## Notes

- All test scripts automatically detect project structure
- Paths are relative to allow tests to run from any location
- Test outputs are preserved in `work/` directory for inspection
- The workspace overwrite error at the end is cosmetic and can be ignored