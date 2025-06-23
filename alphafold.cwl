#!/usr/bin/env cwl-runner
cwlVersion: v1.2
class: CommandLineTool
label: AlphaFold protein structure prediction
doc: |
  AlphaFold predicts a protein's 3D structure from its amino acid sequence.
  This tool uses DeepMind's AlphaFold v2.3.0 implementation.

baseCommand: ["apptainer", "run", "-B", "/alphafold/databases:/databases"]

requirements:
  InlineJavascriptRequirement: {}
  ResourceRequirement:
    coresMin: 8
    ramMin: 65536  # 64GB
    tmpdirMin: 100000  # 100GB temp space

inputs:
  apptainer_image:
    type: string
    default: "/alphafold/images/alphafold_latest.sif"
    inputBinding:
      position: 0

  fasta_paths:
    type: File
    doc: "FASTA file containing protein sequence(s) to predict"
    inputBinding:
      prefix: "--fasta_paths"
      position: 1

  output_dir:
    type: string
    default: "./alphafold_output"
    doc: "Output directory for prediction results"
    inputBinding:
      prefix: "--output_dir"
      position: 2

  data_dir:
    type: string
    default: "/databases"
    doc: "Path to AlphaFold databases"
    inputBinding:
      prefix: "--data_dir"
      position: 3

  model_preset:
    type:
      type: enum
      symbols: ["monomer", "monomer_casp14", "monomer_ptm", "multimer"]
    default: "monomer"
    doc: "Model configuration preset"
    inputBinding:
      prefix: "--model_preset"
      position: 4

  db_preset:
    type:
      type: enum
      symbols: ["full_dbs", "reduced_dbs"]
    default: "full_dbs"
    doc: "Database configuration - full for accuracy, reduced for speed"
    inputBinding:
      prefix: "--db_preset"
      position: 5

  max_template_date:
    type: string?
    doc: "Maximum template release date (YYYY-MM-DD format)"
    inputBinding:
      prefix: "--max_template_date"
      position: 6

  models_to_relax:
    type:
      type: enum
      symbols: ["all", "best", "none"]
    default: "best"
    doc: "Which models to run relaxation on"
    inputBinding:
      prefix: "--models_to_relax"
      position: 7

  num_multimer_predictions_per_model:
    type: int?
    default: 5
    doc: "Number of predictions per multimer model (only for multimer preset)"
    inputBinding:
      prefix: "--num_multimer_predictions_per_model"
      position: 8

  use_gpu_relax:
    type: boolean?
    default: true
    doc: "Use GPU for relaxation (faster if GPU available)"
    inputBinding:
      prefix: "--use_gpu_relax"
      position: 9

  use_precomputed_msas:
    type: boolean?
    default: false
    doc: "Use pre-computed MSAs from previous runs"
    inputBinding:
      prefix: "--use_precomputed_msas"
      position: 10

  benchmark:
    type: boolean?
    default: false
    doc: "Run timing benchmarks"
    inputBinding:
      prefix: "--benchmark"
      position: 11

  random_seed:
    type: int?
    doc: "Random seed for reproducibility"
    inputBinding:
      prefix: "--random_seed"
      position: 12

outputs:
  prediction_results:
    type: Directory
    outputBinding:
      glob: $(inputs.output_dir)
    doc: "Directory containing all prediction results"

  ranked_structures:
    type: File[]
    outputBinding:
      glob: "$(inputs.output_dir)/*/ranked_*.pdb"
    doc: "Final predicted structures ranked by confidence"

  timings:
    type: File?
    outputBinding:
      glob: "$(inputs.output_dir)/*/timings.json"
    doc: "Runtime statistics for each prediction stage"

  confidence_metrics:
    type: File[]?
    outputBinding:
      glob: "$(inputs.output_dir)/*/ranking_debug.json"
    doc: "Confidence scores used for structure ranking"

hints:
  SoftwareRequirement:
    packages:
      apptainer:
        specs: ["https://apptainer.org/"]
  DockerRequirement:
    dockerImageId: "alphafold_metadata"