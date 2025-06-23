# AlphaFold Service

## Description
AlphaFold predicts a protein's 3D structure from its amino acid sequence using deep learning

## Usage
```bash
App-AlphaFold [job_id] app_specs/AlphaFold.json params.json
```

### Help
```bash
App-AlphaFold --help
```

### Test Run
```bash
App-AlphaFold xx app_specs/AlphaFold.json tests/test_case_1/params.json
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

## Input/Output

### Input Files
- FASTQ sequencing files
- Configuration parameters via JSON

### Output Files
- Analysis results in workspace output folder
- Log files for debugging
- Summary reports and visualizations

## Generated Service

This module was auto-generated from:
- Docker container specification
- CWL workflow definition  
- BV-BRC service configuration

The service follows BV-BRC standards for:
- Parameter validation
- Resource estimation
- Error handling
- Output organization

## Development

### Building
```bash
make
```

### Testing
```bash
make test
```

### Debugging
Enable debug mode by setting environment variable:
```bash
export P3_DEBUG=1
```

## Support

For issues with this auto-generated service:
1. Check the generated Perl script for errors
2. Verify input parameters match expected format
3. Review log files in output directory
4. Contact BV-BRC support if needed
