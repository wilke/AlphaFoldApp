# AlphaFold BV-BRC Service - Production Deployment Guide

## Overview

This document provides instructions for deploying the AlphaFold protein structure prediction service in the BV-BRC production environment.

## System Requirements

### Hardware
- **CPU**: Minimum 8 cores, recommended 16-32 cores
- **Memory**: Minimum 64GB, recommended 128-256GB for large proteins
- **GPU**: Optional but recommended (NVIDIA GPU with CUDA support)
- **Storage**: 3TB for full databases, 500GB for reduced databases

### Software
- **Container Runtime**: Apptainer/Singularity 3.8+
- **Perl**: 5.16+ with Bio::KBase modules
- **BV-BRC Framework**: Current dev_container environment

## Pre-Deployment Checklist

### 1. Container Image
```bash
# Verify container image exists and is accessible
ls -lh images/alphafold_unified_patric.sif

# ⚠️ CRITICAL: Create Python symlink inside container
apptainer exec images/alphafold_unified_patric.sif bash -c \
  "cd /opt/patric-common/runtime/bin && ln -s /opt/conda/bin/python python"

# Test container functionality
apptainer exec images/alphafold_unified_patric.sif /opt/patric-common/runtime/bin/python -c "import alphafold"
```

**NOTE**: Without the Python symlink, AlphaFold will use the BV-BRC Python which lacks AlphaFold dependencies.
The symlink ensures the conda Python (with AlphaFold modules) is used instead.

### 2. Database Setup

The AlphaFold databases must be available at one of these locations:
- `${application_backend_dir}/databases/` (preferred for BV-BRC)
- `/databases/` (container default)
- Custom path via `ALPHAFOLD_DB_DIR` environment variable

Required database structure:
```
databases/
├── bfd/                    # 1.8 TB (full_dbs only)
├── small_bfd/             # 17 GB (reduced_dbs only)
├── mgnify/                # 120 GB
├── params/                # 5.3 GB (model parameters)
├── pdb70/                 # 56 GB (monomer models)
├── pdb_mmcif/             # 238 GB
├── pdb_seqres/            # 0.2 GB (multimer only)
├── uniref90/              # 67 GB
├── uniref30/              # 206 GB (full_dbs only)
└── uniprot/               # 105 GB (multimer only)
```

### 3. Validate Service Script
```bash
# Syntax check
perl -c service-scripts/App-AlphaFold.pl

# Setup container environment (if not already done)
./container_setup.sh

# Run test suite
./test_alphafold.sh --quick

# Or run simple test
./run_simple_test.sh
```

## Deployment Steps

### 1. Install in BV-BRC Dev Container

```bash
cd ${KB_TOP}/modules
git clone <repository> AlphaFoldApp
cd AlphaFoldApp
source ${KB_TOP}/user-env.sh
make
```

### 2. Deploy Service Components

```bash
# Deploy service scripts
make deploy-service

# Deploy application specifications
make deploy-specs

# Verify deployment
make test-service
```

### 3. Configure Environment

Set required environment variables in the service configuration:

```bash
# In service configuration file
export ALPHAFOLD_CONTAINER="${application_backend_dir}/images/alphafold_unified_patric.sif"
export ALPHAFOLD_DB_DIR="${application_backend_dir}/databases"
export P3_LOG_LEVEL="INFO"
```

### 4. Resource Allocation

Configure resource limits in the scheduler:

```yaml
alphafold_service:
  limits:
    cpu: 32
    memory: 256G
    gpu: 1
    runtime: 86400  # 24 hours max
  defaults:
    cpu: 8
    memory: 64G
    runtime: 7200   # 2 hours default
```

## Production Configuration

### App Specification (app_specs/AlphaFold.json)

Key parameters to verify:
- `default_memory`: "64G" minimum
- `default_cpu`: 8 minimum
- `default_gpu`: 1 (if available)
- `default_runtime`: 7200 (2 hours)

### Model Presets

| Preset | Use Case | Resources | Runtime |
|--------|----------|-----------|---------|
| monomer | Single chain, fast | 8 CPU, 64GB | 1-2 hours |
| monomer_ptm | With confidence metrics | 8 CPU, 80GB | 2-3 hours |
| monomer_casp14 | 8-model ensemble | 16 CPU, 96GB | 6-8 hours |
| multimer | Protein complexes | 16 CPU, 128GB | 3-4 hours |

### Database Presets

| Preset | Databases Used | Size | Speed |
|--------|---------------|------|-------|
| reduced_dbs | Small BFD, no UniRef30 | ~500GB | Faster (70% accuracy) |
| full_dbs | Full BFD, UniRef30 | ~2.6TB | Slower (full accuracy) |

## Monitoring and Logging

### Enable Debug Logging
```bash
export P3_DEBUG=1
export P3_LOG_LEVEL=DEBUG
```

### Log Locations
- Service logs: `${service_log_dir}/alphafold/`
- Job logs: Within job working directory
- Container logs: `${container_log_dir}/`

### Key Log Messages
- `[INFO] Starting AlphaFold analysis`
- `[INFO] Parameters validated successfully`
- `[INFO] AlphaFold execution completed successfully`
- `[ERROR] AlphaFold execution failed`

## Troubleshooting

### Common Issues

1. **Python Module Import Errors (CRITICAL)**
   - Symptom: "ModuleNotFoundError: No module named 'alphafold'" or similar
   - Cause: BV-BRC Python lacks AlphaFold dependencies; must use conda Python
   - Solution: Create symlink inside container:
     ```bash
     cd /opt/patric-common/runtime/bin/
     ln -s /opt/conda/bin/python python
     ```
   - Or run: `./container_setup.sh` inside container

2. **Workspace Overwrite Error (Cosmetic)**
   - Symptom: "_ERROR_Cannot overwrite directory_" after successful run
   - Impact: None - all outputs are saved correctly
   - Status: Known issue, can be safely ignored

3. **Out of Memory (Exit code 137)**
   - Solution: Increase memory allocation or use reduced_dbs
   - Check: Memory usage during execution

4. **Database Not Found**
   - Solution: Verify database path and permissions
   - Check: Database mounted at `/databases` in container

5. **Timeout Issues**
   - Solution: Increase runtime allocation
   - Check: Protein length and complexity

### Debug Commands

```bash
# Test container access
apptainer shell --nv images/alphafold_unified_patric.sif

# Test database access
ls -la ${ALPHAFOLD_DB_DIR}/params/

# Run with debug output
P3_DEBUG=1 ./service-scripts/App-AlphaFold.pl test_job app_specs/AlphaFold.json test_params.json

# Check resource usage
top -p <pid>
nvidia-smi  # If GPU is used
```

## Performance Tuning

### CPU Optimization
- Set `OMP_NUM_THREADS` to match allocated CPUs
- Use CPU pinning for consistent performance

### Memory Optimization
- Pre-allocate memory for large proteins
- Use memory-mapped files for databases

### GPU Optimization
- Enable GPU relaxation for better structures
- Use `--nv` flag with Apptainer for GPU support

## Security Considerations

1. **Container Security**
   - Run containers in read-only mode when possible
   - Use `--contain` flag to isolate filesystem
   - Validate container signatures

2. **Input Validation**
   - FASTA format validation is enforced
   - Sequence length limits prevent resource exhaustion
   - Special characters are sanitized

3. **Output Handling**
   - Outputs are written to controlled workspace
   - File permissions are set appropriately
   - Temporary files are cleaned up

## Maintenance

### Regular Tasks

1. **Weekly**
   - Check disk usage for work directories
   - Review error logs for patterns
   - Monitor job success rates

2. **Monthly**
   - Update container image if new version available
   - Clean up old temporary files
   - Review resource utilization trends

3. **Quarterly**
   - Update AlphaFold databases if available
   - Review and optimize resource allocations
   - Update documentation

### Backup Requirements

- Container images: Keep previous version
- Database files: Snapshot before updates
- Configuration files: Version control

## Support Contacts

- BV-BRC Dev Team: dev-team@bv-brc.org
- AlphaFold Issues: https://github.com/deepmind/alphafold/issues
- Service Issues: Create ticket in BV-BRC support system

## Version History

- v1.0.0 (2025-08-28): Production-ready release
  - Container-based execution
  - Comprehensive error handling
  - Resource estimation based on model preset
  - FASTA validation
  - Structured logging
  - Python symlink configuration documented
  - Workspace integration validated
  - Successfully tested end-to-end

## References

- [AlphaFold GitHub](https://github.com/deepmind/alphafold)
- [BV-BRC Documentation](https://www.bv-brc.org/docs/)
- [Apptainer Documentation](https://apptainer.org/docs/)