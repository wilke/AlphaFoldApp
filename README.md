# AlphaFoldV2 Service

## Description
AlphaFold predicts a protein's 3D structure from its amino acid sequence using deep learning

## BV-BRC Development Structure

This module follows the standard BV-BRC dev container structure:
- `Makefile` – fits into the dev container build plan
- `lib/` – library code directory
- `scripts/` – user level programs
- `service-scripts/` – service-side programs
- `app_specs/` – BV-BRC application specifications

## Setup in BV-BRC Environment

```bash
cd ${KB_TOP}/modules/AlphaFoldV2
source ${KB_TOP}/user-env.sh
make
```

## Usage

### Development Testing
```bash
./service-scripts/App-AlphaFoldV2.pl --help
./service-scripts/App-AlphaFoldV2.pl xx app_specs/AlphaFoldV2.json tests/test_case_1/params.json
```

### Production Deployment
```bash
make deploy-service  # Deploy service components
make deploy-specs    # Deploy app specifications
```

### Testing Targets
```bash
make test-service    # Test the generated service
make help-service    # Show service-specific help
```

## Parameters

### Required Parameters

- **apptainer_image** (`string`): No description (default: `/alphafold/images/alphafold_latest.sif`)
- **fasta_paths** (`wsid`): FASTA file containing protein sequence(s) to predict
- **output_dir** (`string`): Output directory for prediction results (default: `./alphafold_output`)
- **data_dir** (`string`): Path to AlphaFold databases (default: `/databases`)

### Optional Parameters

- **model_preset** (`enum`): Choose the AlphaFold model configuration (default: `monomer`)
- **db_preset** (`enum`): Choose database configuration for MSA generation (default: `full_dbs`)
- **max_template_date** (`string`): Latest template release date to consider (YYYY-MM-DD) (default: `2022-01-01`)
- **models_to_relax** (`enum`): Which predicted models to run energy minimization on (default: `best`)
- **num_multimer_predictions_per_model** (`int`): Number of predictions per multimer model (only for multimer preset) (default: `5`)
- **use_gpu_relax** (`bool`): Enable GPU acceleration for structure relaxation (if available) (default: `True`)
- **use_precomputed_msas** (`bool`): Reuse MSAs from previous runs (faster for parameter testing) (default: `False`)
- **benchmark** (`bool`): Run timing benchmarks (default: `False`)
- **random_seed** (`int`): Random seed for reproducibility (optional)
- **output_path** (`folder`): Path to which the output will be written
- **output_file** (`wsid`): Basename for generated output files

## Generated Service

This module was auto-generated from:
- Docker/Apptainer container specification
- CWL workflow definition  
- BV-BRC service configuration

The service follows BV-BRC standards for:
- Parameter validation and type checking
- Resource estimation and scaling
- Error handling and logging
- Output organization and workspace integration
- Container execution (Apptainer/Singularity)

## Development Workflow

### Initial Setup
1. Clone this module into BV-BRC dev_container
2. Run `source user-env.sh` to set environment
3. Run `make` to build all components

### Making Changes
1. Edit `service-scripts/App-AlphaFoldV2.pl` for logic changes
2. Edit `app_specs/AlphaFoldV2.json` for parameter changes
3. Run `make test-service` to validate changes
4. Run `make deploy-service` for production deployment

### Integration Testing
```bash
# Set debug mode
export P3_DEBUG=1

# Test preflight resource estimation
./service-scripts/App-AlphaFoldV2.pl --preflight /tmp/preflight.json appservice app_specs/AlphaFoldV2.json tests/test_case_1/params.json

# Test actual execution
./service-scripts/App-AlphaFoldV2.pl xx app_specs/AlphaFoldV2.json tests/test_case_1/params.json
```

## Environment Variables

The service uses standard BV-BRC environment variables:
- `${KB_TOP}` - Development container top directory
- `${KB_RUNTIME}` - Runtime directory path
- `${P3_ALLOCATED_CPU}` - Allocated CPU cores
- `${P3_DEBUG}` - Enable debug logging

## Support

For issues with this auto-generated service:
1. Check the generated Perl script syntax: `perl -c service-scripts/App-AlphaFoldV2.pl`
2. Verify input parameters match expected format
3. Review log files in output directory
4. Check container availability and database paths
5. Contact BV-BRC support team if needed
