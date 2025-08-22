#!/usr/bin/env perl
#
# Generic BV-BRC Service Template
# Auto-generated template based on existing BV-BRC service patterns
#
# This template provides the standard structure for BV-BRC services
# Replace placeholders with tool-specific implementation
#

use Bio::KBase::AppService::AppScript;
use Bio::KBase::AppService::AppConfig;
use File::Slurp;
use File::Temp;
use File::Basename;
use File::Path qw(make_path remove_tree);
use JSON;
use Data::Dumper;
use POSIX qw(strftime);
use Cwd;
use strict;
use warnings;

use Bio::KBase::AppService::AppConfig qw(application_backend_dir);
   
# Create the application script object
my $script = Bio::KBase::AppService::AppScript->new(\&process_alphafoldv2, \&preflight);


print Dumper($script);

# Run the script
$script->run(\@ARGV);
=head1 NAME

App-AlphaFoldV2 - AlphaFold protein structure prediction

=head1 SYNOPSIS

App-AlphaFoldV2 [options] job_id app_definition_file parameters_file

=head1 DESCRIPTION

AlphaFold predicts a protein's 3D structure from its amino acid sequence.
This tool uses DeepMind's AlphaFold v2.3.0 implementation.


Auto-generated from:
- Container: unknown:latest
- CWL Definition: auto-generated

=cut

# # Create the application script object
# my $script = Bio::KBase::AppService::AppScript->new(\&process_alphafoldv2, \&preflight);

# # Run the script
# $script->run(\@ARGV);

=head2 preflight

Resource estimation callback. Analyzes input parameters to determine
computational requirements (CPU, memory, runtime).

=cut

sub preflight {
    my($app, $app_def, $raw_params, $params) = @_;
    
    print STDERR "Preflight for AlphaFoldV2\n";
    print STDERR "Parameters: " . Dumper($params) if $ENV{P3_DEBUG};
    
    # Default resource allocation
    my $cpu = $ENV{P3_ALLOCATED_CPU} // 8;
    my $memory = "64G";
    my $runtime = 7200;
    
    
    # Dynamic resource estimation based on input size
    my $input_size_gb = 0;
    
    # Estimate input size (simplified)
    for my $param_name (keys %$params) {
        if ($param_name =~ /file|reads/) {
            # This is a simplification - in reality would check file sizes
            $input_size_gb += 1;
        }
    }
    
    # Adjust resources based on input size
    $cpu = 8 + int($input_size_gb * 4);
    $cpu = 32 if $cpu > 32;
    
    my $memory_gb = 64;
    $memory_gb += int($input_size_gb * 8);
    $memory = "${memory_gb}G";
    
    $runtime += int($input_size_gb * 3600);
    $runtime = 86400 if $runtime > 86400;
    
    my $time = int($runtime / 60);
    $time = 1 if $time == 0;
    
    return {
        cpu => $cpu,
        memory => $memory,
        runtime => $time,
    };

}

=head2 process_alphafoldv2

Main processing function. Handles input staging, tool execution,
and output collection.

=cut

sub process_alphafoldv2 {
    my($app, $app_def, $raw_params, $params) = @_;


    print STDERR "Application backend directory: " . application_backend_dir() . "\n";

    print STDERR "Starting AlphaFoldV2 analysis\n";
    print STDERR "Parameters: " . Dumper($params) if $ENV{P3_DEBUG};

   
    # Validate required parameters

    validate_parameters($params);
    
    # Setup working environment
    my $cwd = getcwd();
    my $work_dir = "$cwd/work";
    my $stage_dir = "$cwd/stage";

    print STDERR "Creating working directories: $work_dir, $stage_dir\n";
    make_path($work_dir, $stage_dir);
    
    # Get output configuration
    my $output_folder = $app->result_folder();
    die "Output folder not specified" unless $output_folder;
    
    # Clean up the output folder path - remove trailing slashes and dots
    $output_folder =~ s/\/+$//;  # Remove trailing slashes
    $output_folder =~ s/\/\.$//;  # Remove trailing /.
    
    my $output_base = $params->{output_file} // "alphafoldv2_result";
    
    # Create a unique subfolder for this run using timestamp and task ID
    my $timestamp = strftime("%Y%m%d_%H%M%S", localtime);
    my $task_id = $app->{task_id} // "unknown";
    my $run_folder = "${output_base}_${timestamp}_${task_id}";
    $output_folder = "$output_folder/$run_folder";
    
    print STDERR "Output base name: $output_base\n";
    print STDERR "Output folder: $output_folder\n";

    eval {
        # Stage input files
        my $staged_inputs = stage_inputs($app, $params, $stage_dir);
        print STDERR "Staged inputs: " . Dumper($staged_inputs) if $ENV{P3_DEBUG};

        # Execute main tool
        my $results = execute_tool($app, $params, $staged_inputs, $work_dir, $stage_dir);
        
        # Collect and save outputs
        collect_outputs($app, $results, $output_folder, $output_base, $params);
        
        print STDERR "AlphaFoldV2 analysis completed successfully\n";
    };
    
    if ($@) {
        my $error = $@;
        print STDERR "AlphaFoldV2 analysis failed: $error\n";
        
        # Don't try to write error file to workspace - it might cause issues
        # Just re-throw the error for the framework to handle
        die $error;
    }
    
    # Cleanup temporary files
    cleanup_temp_files($work_dir, $stage_dir);
    
    # Return success to prevent framework from trying additional saves
    return 1;
}

=head2 validate_parameters

Validates input parameters and ensures all required inputs are present.

=cut

sub validate_parameters {
    my($params) = @_;
    
    die "Missing required parameter: fasta_paths" unless $params->{fasta_paths};
    die "Missing required parameter: output_dir" unless $params->{output_dir};
    die "Missing required parameter: data_dir" unless $params->{data_dir};
    die "Missing required parameter: model_preset" unless $params->{model_preset};
    die "Missing required parameter: db_preset" unless $params->{db_preset};
    # die "Missing required parameter: models_to_relax" unless $params->{models_to_relax};
    
    # Example validations:
    # die "Missing required parameter: input_file" unless $params->{input_file};
    # die "Invalid parameter value: threads must be positive" if $params->{threads} && $params->{threads} <= 0;
}

=head2 stage_inputs

Downloads and prepares input files from workspace or processes input data.

=cut

sub stage_inputs {
    my($app, $params, $stage_dir) = @_;
    
    print STDERR "Staging input files...\n";
    
    my $staged_inputs = {};
    
    
    # Stage fasta_paths
    if ($params->{fasta_paths}) {
        # if workspace space get from workspace
        if ($app->workspace->exists($params->{fasta_paths})) {
            my $file_path = "$stage_dir/fasta_paths.data";
            $app->workspace->download_file($params->{fasta_paths}, $file_path, 1);
            $staged_inputs->{fasta_paths} = $file_path;
        }
        else {
            my $file_path = $params->{fasta_paths};
            # check if local
            if (-e $file_path) {
                $staged_inputs->{fasta_paths} = $file_path;
            } else {
                die "Fasta file not found: $file_path";
            }
        }
    }
    
    # Example staging patterns:
    #
    # # For workspace files:
    # if ($params->{input_file}) {
    #     my $input_path = "$stage_dir/input.fasta";
    #     $app->workspace->download_file($params->{input_file}, $input_path, 1);
    #     $staged_inputs->{input_file} = $input_path;
    # }
    #
    # # For string inputs (e.g., sequences):
    # if ($params->{sequence_data}) {
    #     my $seq_path = "$stage_dir/sequence.fasta";
    #     write_file($seq_path, $params->{sequence_data});
    #     $staged_inputs->{sequence_file} = $seq_path;
    # }
    
    return $staged_inputs;
}

=head2 execute_tool

Executes the main computational tool with prepared inputs.

=cut

sub execute_tool {
    my($app, $params, $staged_inputs, $work_dir, $stage_dir) = @_;
    
    print STDERR "Executing AlphaFoldV2...\n";
    
    # Get allocated resources
    my $threads = $ENV{P3_ALLOCATED_CPU} // 1;
    
    # Build command line - running directly within container
    my @cmd = ("python", "/app/alphafold/run_alphafold.py");
    # push @cmd, "--fasta_paths", $staged_inputs->{fasta_paths} if $staged_inputs->{fasta_paths};
    # push @cmd, "--output_dir", $params->{output_dir} if defined $params->{output_dir};
    # push @cmd, "--data_dir", $params->{data_dir} if defined $params->{data_dir};
    # push @cmd, "--model_preset", $params->{model_preset} if defined $params->{model_preset};
    # push @cmd, "--db_preset", $params->{db_preset} if defined $params->{db_preset};
    # push @cmd, "--max_template_date", $params->{max_template_date} if defined $params->{max_template_date};
    # push @cmd, "--models_to_relax", $params->{models_to_relax} if defined $params->{models_to_relax};
    # push @cmd, "--num_multimer_predictions_per_model", $params->{num_multimer_predictions_per_model} if defined $params->{num_multimer_predictions_per_model};
    # push @cmd, "--use_gpu_relax" if $params->{use_gpu_relax};
    # push @cmd, "--use_precomputed_msas" if $params->{use_precomputed_msas};
    # push @cmd, "--benchmark" if $params->{benchmark};
    # push @cmd, "--random_seed", $params->{random_seed} if defined $params->{random_seed};

    # for every key in params add to command line (except database paths and presets which are handled conditionally)
    foreach my $key (keys %$params) {
        next if $key eq 'output_path' || $key eq 'output_dir';
        # Skip database-related parameters - handled conditionally below
        next if $key =~ /database_path$|_database_path$|template_mmcif_dir|obsolete_pdbs_path|db_preset|model_preset|data_dir/;
        # Skip parameters that need special handling or have null values
        next if $key eq 'max_template_date' || $key eq 'use_gpu_relax';
        next if !defined $params->{$key} || $params->{$key} eq 'null' || $params->{$key} eq '';
        push @cmd, "--$key=" . $params->{$key};
    }

    push @cmd, "--output_dir=" . $work_dir;


    my $db = "";
    $db = $params->{data_dir} if $params->{data_dir};

    
    my $backend_dir = application_backend_dir;
    if ($backend_dir and -d "$backend_dir/databases") {
        $db = "$backend_dir/databases";
    }
    push @cmd, "--data_dir", "$db";
    
    # Common databases for all presets
    push @cmd, "--uniref90_database_path", "$db/uniref90/uniref90.fasta";
    push @cmd, "--mgnify_database_path", "$db/mgnify/mgy_clusters_2022_05.fa";
    push @cmd, "--template_mmcif_dir", "$db/pdb_mmcif/mmcif_files";
    push @cmd, "--obsolete_pdbs_path", "$db/pdb_mmcif/obsolete.dat";
    
    # Database paths based on db_preset
    my $db_preset = $params->{db_preset} // "reduced_dbs";
    if ($db_preset eq "full_dbs") {
        push @cmd, "--bfd_database_path", "$db/bfd/bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt";
        push @cmd, "--uniref30_database_path", "$db/uniref30/UniRef30_2021_03";
    } elsif ($db_preset eq "reduced_dbs") {
        push @cmd, "--small_bfd_database_path", "$db/small_bfd/bfd-first_non_consensus_sequences.fasta";
    }
    
    # Database paths based on model_preset  
    my $model_preset = $params->{model_preset} // "monomer";
    if ($model_preset eq "multimer") {
        push @cmd, "--pdb_seqres_database_path", "$db/pdb_seqres/pdb_seqres.txt";
        push @cmd, "--uniprot_database_path", "$db/uniprot/uniprot.fasta";
    } else {
        # monomer, monomer_ptm, monomer_casp14
        push @cmd, "--pdb70_database_path", "$db/pdb70/pdb70";
    }
  
    # constants - use values from parameters
    push @cmd, "--db_preset", $params->{db_preset} if defined $params->{db_preset};
    push @cmd, "--model_preset", $params->{model_preset} if defined $params->{model_preset};
    
    # Required constants with proper defaults
    push @cmd, "--max_template_date", "2022-01-01";
    push @cmd, "--use_gpu_relax=false";

    # Example command building:
    # push @cmd, "--input", $staged_inputs->{input_file} if $staged_inputs->{input_file};
    # push @cmd, "--output", "$work_dir/output.txt";
    # push @cmd, "--threads", $threads;
    # push @cmd, "--param", $params->{param_value} if defined $params->{param_value};
    
    # Execute command directly within container
    print STDERR "Running command: " . join(" ", @cmd) . "\n";
    
    # my $rc = system(@cmd);
    
    # if ($rc != 0) {
    #     die "Tool execution failed with exit code $rc";
    # }

    my $rc = '';
    
    # Standard execution pattern:
    # $rc = system(@cmd);
    # if ($rc != 0) {
    #     die "AlphaFoldV2 execution failed with exit code $rc";
    # }
    
    # Return results information
    return {
        work_dir => $work_dir,
        exit_code => $rc,
        command => \@cmd
    };
}

=head2 collect_outputs

Collects and saves output files to the workspace.

=cut

sub collect_outputs {
    my($app, $results, $output_folder, $output_base, $params) = @_;
    
    print STDERR "Collecting outputs...\n";
    
    my $work_dir = $results->{work_dir};
    
    # AlphaFold outputs are in $work_dir since we set --output_dir=$work_dir
    # The structure is: work_dir/target_name/[various output files]
    
    # Find all target directories (one per sequence in the FASTA)
    opendir(my $dh, $work_dir) or die "Cannot open $work_dir: $!";
    my @target_dirs = grep { -d "$work_dir/$_" && $_ !~ /^\.\.?$/ } readdir($dh);
    closedir($dh);
    
    for my $target_dir (@target_dirs) {
        my $target_path = "$work_dir/$target_dir";
        
        # Collect all PDB structures (ranked and unrelaxed)
        my @pdb_files = glob("$target_path/*.pdb");
        for my $file (@pdb_files) {
            if (-f $file) {
                my $basename = basename($file);
                my $save_path = "$output_folder/${target_dir}_${basename}";
                print STDERR "Saving PDB: $file -> $save_path\n" if $ENV{P3_DEBUG};
                $app->workspace->save_file_to_file($file, {},
                                                 $save_path,
                                                 'pdb', 1);
            }
        }
        
        # Collect all CIF structures (ranked and unrelaxed)
        my @cif_files = glob("$target_path/*.cif");
        for my $file (@cif_files) {
            if (-f $file) {
                my $basename = basename($file);
                my $save_path = "$output_folder/${target_dir}_${basename}";
                print STDERR "Saving CIF: $file -> $save_path\n" if $ENV{P3_DEBUG};
                $app->workspace->save_file_to_file($file, {},
                                                 $save_path,
                                                 'txt', 1);
            }
        }
        
        # Collect pickle files (features and results)
        my @pkl_files = glob("$target_path/*.pkl");
        for my $file (@pkl_files) {
            if (-f $file) {
                my $basename = basename($file);
                my $save_path = "$output_folder/${target_dir}_${basename}";
                print STDERR "Saving PKL: $file -> $save_path\n" if $ENV{P3_DEBUG};
                $app->workspace->save_file_to_file($file, {}, $save_path, 'unspecified', 1);
            }
        }
        
        # Collect JSON files (timings, ranking_debug)
        my @json_files = glob("$target_path/*.json");
        for my $file (@json_files) {
            if (-f $file) {
                my $basename = basename($file);
                my $save_path = "$output_folder/${target_dir}_${basename}";
                print STDERR "Saving JSON: $file -> $save_path\n" if $ENV{P3_DEBUG};
                $app->workspace->save_file_to_file($file, {},
                                                 $save_path,
                                                 'json', 1);
            }
        }
        
        # Collect MSA files if present
        if (-d "$target_path/msas") {
            my @msa_files = glob("$target_path/msas/*");
            for my $file (@msa_files) {
                if (-f $file) {
                    my $basename = basename($file);
                    my $save_path = "$output_folder/${target_dir}_msa_${basename}";
                    print STDERR "Saving MSA: $file -> $save_path\n" if $ENV{P3_DEBUG};
                    $app->workspace->save_file_to_file($file, {},
                                                     $save_path,
                                                     'unspecified', 1);
                }
            }
        }
    }
    
    print STDERR "Output collection completed. Files saved to: $output_folder\n";
    
    # Example output collection:
    #
    # # Save primary output
    # my $main_output = "$work_dir/$(inputs.output_dir)";
    # if (-f $main_output) {
    #     $app->workspace->save_file_to_file($main_output, {}, 
    #                                       "$output_folder/$output_base.output_dir)", 
    #                                       'auto', 1);
    # } else {
    #     warn "Expected output file $main_output not found";
    # }
    #
    # # Save log files
    # my $log_file = "$work_dir/tool.log";
    # if (-f $log_file) {
    #     $app->workspace->save_file_to_file($log_file, {},
    #                                       "$output_folder/$output_base.log",
    #                                       'auto', 1);
    # }
    #
    # # Save additional outputs
    # opendir(my $dh, $work_dir) or die "Cannot open $work_dir: $!";
    # while (my $file = readdir($dh)) {
    #     next if $file =~ /^\.\.?$/;
    #     my $full_path = "$work_dir/$file";
    #     next unless -f $full_path;
    #     
    #     # Save files matching output patterns
    #     if ($file =~ /\.($(inputs.output_dir)|$(inputs.output_dir)/*/ranked_*.pdb|$(inputs.output_dir)/*/timings.json|$(inputs.output_dir)/*/ranking_debug.json)$/) {
    #         $app->workspace->save_file_to_file($full_path, {},
    #                                           "$output_folder/$file",
    #                                           'auto', 1);
    #     }
    # }
    # closedir($dh);
}

=head2 cleanup_temp_files

Removes temporary files and directories.

=cut

sub cleanup_temp_files {
    my(@dirs) = @_;
    
    return if $ENV{P3_DEBUG}; # Keep files for debugging
    
    for my $dir (@dirs) {
        if (-d $dir) {
            print STDERR "Cleaning up $dir\n";
            remove_tree($dir);
        }
    }
}

=head2 handle_error

Standardized error handling with user-friendly messages.

=cut

sub handle_error {
    my($error_message, $error_type) = @_;
    
    $error_type //= 'execution';
    
    # Map technical errors to user-friendly messages
    my %error_messages = (
        'out_of_memory' => 'Analysis requires more memory. Try with a smaller dataset or contact support.',
        'invalid_input' => 'Input file format is invalid. Please check file format requirements.',
        'tool_not_found' => 'Required tool is not available. Please contact support.',
        'timeout' => 'Analysis timed out. Try with a smaller dataset or contact support.',
        'disk_space' => 'Insufficient disk space for analysis. Please contact support.',
    );
    
    # Pattern matching for common errors
    if ($error_message =~ /std::bad_alloc|OutOfMemoryError|killed.*memory/i) {
        die $error_messages{'out_of_memory'};
    } elsif ($error_message =~ /invalid.*format|parse.*error|malformed/i) {
        die $error_messages{'invalid_input'};
    } elsif ($error_message =~ /command not found|No such file/i) {
        die $error_messages{'tool_not_found'};
    } elsif ($error_message =~ /timeout|timed out/i) {
        die $error_messages{'timeout'};
    } elsif ($error_message =~ /no space left|disk.*full/i) {
        die $error_messages{'disk_space'};
    } else {
        # Generic error message
        die "Tool execution failed: $error_message";
    }
}

=head1 PLACEHOLDERS

This template uses the following placeholders that should be replaced:

- AlphaFoldV2: Name of the tool (e.g., "Blast", "FastANI")
- alphafoldv2: Lowercase tool name for function names
- AlphaFold protein structure prediction: Brief description of the tool
- AlphaFold predicts a protein's 3D structure from its amino acid sequence.
This tool uses DeepMind's AlphaFold v2.3.0 implementation.
: Detailed description for documentation
- unknown:latest: Docker/Singularity container reference
- auto-generated: Path to CWL definition file
- 8: Default CPU allocation (e.g., 1, 4)
- 64G: Default memory allocation (e.g., "4G", "8G")
- 7200: Default runtime in seconds (e.g., 1800, 3600)
- 
    # Dynamic resource estimation based on input size
    my $input_size_gb = 0;
    
    # Estimate input size (simplified)
    for my $param_name (keys %$params) {
        if ($param_name =~ /file|reads/) {
            # This is a simplification - in reality would check file sizes
            $input_size_gb += 1;
        }
    }
    
    # Adjust resources based on input size
    $cpu = 8 + int($input_size_gb * 4);
    $cpu = 32 if $cpu > 32;
    
    my $memory_gb = 64;
    $memory_gb += int($input_size_gb * 8);
    $memory = "${memory_gb}G";
    
    $runtime += int($input_size_gb * 3600);
    $runtime = 86400 if $runtime > 86400;: Tool-specific resource estimation code
-     die "Missing required parameter: apptainer_image" unless $params->{apptainer_image};
    die "Missing required parameter: fasta_paths" unless $params->{fasta_paths};
    die "Missing required parameter: output_dir" unless $params->{output_dir};
    die "Missing required parameter: data_dir" unless $params->{data_dir};
    die "Missing required parameter: model_preset" unless $params->{model_preset};
    die "Missing required parameter: db_preset" unless $params->{db_preset};
    die "Missing required parameter: models_to_relax" unless $params->{models_to_relax};: Tool-specific parameter validation
- 
    # Stage fasta_paths
    if ($params->{fasta_paths}) {
        my $file_path = "$stage_dir/fasta_paths.data";
        $app->workspace->download_file($params->{fasta_paths}, $file_path, 1);
        $staged_inputs->{fasta_paths} = $file_path;
    }: Tool-specific input staging code
- "apptainer", "run", "-B", "/alphafold/databases:/databases": Base command array (e.g., "blastp", "fastani")
-     push @cmd, "--fasta_paths", $staged_inputs->{fasta_paths} if $staged_inputs->{fasta_paths};
    push @cmd, "--output_dir", $params->{output_dir} if defined $params->{output_dir};
    push @cmd, "--data_dir", $params->{data_dir} if defined $params->{data_dir};
    push @cmd, "--model_preset", $params->{model_preset} if defined $params->{model_preset};
    push @cmd, "--db_preset", $params->{db_preset} if defined $params->{db_preset};
    push @cmd, "--max_template_date", $params->{max_template_date} if defined $params->{max_template_date};
    push @cmd, "--models_to_relax", $params->{models_to_relax} if defined $params->{models_to_relax};
    push @cmd, "--num_multimer_predictions_per_model", $params->{num_multimer_predictions_per_model} if defined $params->{num_multimer_predictions_per_model};
    push @cmd, "--use_gpu_relax" if $params->{use_gpu_relax};
    push @cmd, "--use_precomputed_msas" if $params->{use_precomputed_msas};
    push @cmd, "--benchmark" if $params->{benchmark};
    push @cmd, "--random_seed", $params->{random_seed} if defined $params->{random_seed};: Tool-specific command line building
- 
    # Execute with Singularity container
    if ($ENV{P3_USE_SINGULARITY}) {
        my @singularity_cmd = (
            "singularity", "exec",
            "--bind", "$stage_dir:/workspace/input",
            "--bind", "$work_dir:/workspace/output",
            "--pwd", "/workspace",
            "unknown:latest",
            @cmd
        );
        $rc = system(@singularity_cmd);
    } else {
        # Direct execution (for testing)
        $rc = system(@cmd);
    }
    
    if ($rc != 0) {
        die "Tool execution failed with exit code $rc";
    }: Tool-specific execution wrapper (container, etc.)
- 
    # Collect prediction_results
    my @prediction_results_files = glob("$work_dir/$params->{output_dir}");
    for my $file (@prediction_results_files) {
        if (-f $file) {
            my $basename = basename($file);
            $app->workspace->save_file_to_file($file, {},
                                             "$output_folder/$basename",
                                             'auto', 1);
        }
    }

    # Collect ranked_structures
    my @ranked_structures_files = glob("$work_dir/$params->{output_dir}/*/ranked_*.pdb");
    for my $file (@ranked_structures_files) {
        if (-f $file) {
            my $basename = basename($file);
            $app->workspace->save_file_to_file($file, {},
                                             "$output_folder/$basename",
                                             'auto', 1);
        }
    }

    # Collect timings
    my @timings_files = glob("$work_dir/$params->{output_dir}/*/timings.json");
    for my $file (@timings_files) {
        if (-f $file) {
            my $basename = basename($file);
            $app->workspace->save_file_to_file($file, {},
                                             "$output_folder/$basename",
                                             'auto', 1);
        }
    }

    # Collect confidence_metrics
    my @confidence_metrics_files = glob("$work_dir/$params->{output_dir}/*/ranking_debug.json");
    for my $file (@confidence_metrics_files) {
        if (-f $file) {
            my $basename = basename($file);
            $app->workspace->save_file_to_file($file, {},
                                             "$output_folder/$basename",
                                             'auto', 1);
        }
    }: Tool-specific output collection
- $(inputs.output_dir): Main output filename pattern
- output_dir): Primary output file extension
- ($(inputs.output_dir)|$(inputs.output_dir)/*/ranked_*.pdb|$(inputs.output_dir)/*/timings.json|$(inputs.output_dir)/*/ranking_debug.json): Regex pattern for output files

=head1 USAGE PATTERNS

Common patterns for different tool types:

=head2 Sequence Analysis Tools
- Input: FASTA files from workspace or text area
- Parameters: Algorithm-specific settings, thresholds
- Output: Results files, logs, visualizations

=head2 Comparative Analysis Tools  
- Input: Multiple genomes or sequences
- Parameters: Comparison parameters, output formats
- Output: Comparison matrices, trees, plots

=head2 Annotation Tools
- Input: Sequence data, reference databases
- Parameters: Annotation parameters, confidence thresholds
- Output: Annotated sequences, reports, statistics

=cut




1;