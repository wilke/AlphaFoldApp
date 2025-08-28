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

# Version information
our $VERSION = '1.0.0';

# Logging setup
my $log_level = $ENV{P3_LOG_LEVEL} // ($ENV{P3_DEBUG} ? 'DEBUG' : 'INFO');

# Create the application script object
my $script = Bio::KBase::AppService::AppScript->new(\&run, \&preflight);

# Run the script
$script->run(\@ARGV);
=head1 NAME

App-AlphaFold - AlphaFold protein structure prediction service for BV-BRC

=head1 SYNOPSIS

App-AlphaFold [options] job_id app_definition_file parameters_file

=head1 DESCRIPTION

AlphaFold predicts a protein's 3D structure from its amino acid sequence.
This service uses DeepMind's AlphaFold v2.3.2 implementation running in an
Apptainer/Singularity container with pre-configured databases.

Container: alphafold_unified_patric.sif
Database location: /databases (mounted in container)

=cut


=head2 preflight

Resource estimation callback. Analyzes input parameters to determine
computational requirements (CPU, memory, runtime).

=cut

sub preflight {
    my($app, $app_def, $raw_params, $params) = @_;
    
    print STDERR "Preflight for AlphaFold\n" if $ENV{P3_DEBUG};

    # Validate input parameters, die if invalid
    validate_parameters($params);
    
    # Base resource requirements
    my $cpu = 8;
    my $memory_gb = 64;
    my $runtime = 7200; # 2 hours base
    
    # Estimate based on model preset
    my $model_preset = $params->{model_preset} // 'monomer';
    my $db_preset = $params->{db_preset} // 'reduced_dbs';
    
    # Model-specific adjustments
    if ($model_preset eq 'multimer') {
        $cpu = 16;
        $memory_gb = 128;
        $runtime = 14400; # 4 hours for multimer
    } elsif ($model_preset eq 'monomer_casp14') {
        $cpu = 16;
        $memory_gb = 96;
        $runtime = 28800; # 8 hours for 8 models
    } elsif ($model_preset eq 'monomer_ptm') {
        $memory_gb = 80;
        $runtime = 10800; # 3 hours
    }
    
    # Database preset adjustments
    if ($db_preset eq 'full_dbs') {
        $memory_gb += 32; # More memory for BFD
        $runtime = int($runtime * 1.5); # Longer search times
    }
    
    # Try to estimate protein length if possible
    if ($params->{fasta_paths} && -f $params->{fasta_paths}) {
        my $fasta_content = read_file($params->{fasta_paths});
        my $seq_length = 0;
        for my $line (split /\n/, $fasta_content) {
            next if $line =~ /^>/;
            $seq_length += length($line);
        }
        
        # Adjust for very long sequences
        if ($seq_length > 1000) {
            $memory_gb += int($seq_length / 1000) * 16;
            $runtime += int($seq_length / 500) * 3600;
        }
    }
    
    # Cap maximum resources
    $cpu = 32 if $cpu > 32;
    $memory_gb = 256 if $memory_gb > 256;
    $runtime = 86400 if $runtime > 86400; # 24 hour max
    
    my $time = int($runtime / 60);
    $time = 1 if $time == 0;
    
    print STDERR "Estimated resources: CPU=$cpu, Memory=${memory_gb}G, Runtime=${time}min\n" if $ENV{P3_DEBUG};
    
    return {
        cpu => $cpu,
        memory => "${memory_gb}G",
        runtime => $time,
        gpu => 1,  # AlphaFold benefits from GPU
    };
}

=head2 run

Main processing function. Handles input staging, tool execution,
and output collection.

=cut

sub run {
    my($app, $app_def, $raw_params, $params) = @_;
    
    # Log startup information
    log_message("INFO", "Starting AlphaFold analysis");
    
    # Debug application_backend_dir
    my $backend_check = eval { application_backend_dir() };
    if ($backend_check) {
        log_message("DEBUG", "Application backend directory: $backend_check");
    } else {
        log_message("DEBUG", "Application backend directory not available");
    }
    
    log_message("DEBUG", "Parameters: " . Dumper($params)) if $ENV{P3_DEBUG};
    
    # Validate required parameters
    validate_parameters($params);
    
    # Setup working environment
    my $cwd = getcwd();
    my $work_dir = "$cwd/work";
    my $stage_dir = "$cwd/stage";

    log_message("INFO", "Creating working directories: $work_dir, $stage_dir");
    make_path($work_dir, $stage_dir);
    
    # Get output configuration
    log_message("DEBUG", "About to call app->result_folder()");
    log_message("DEBUG", "output_path parameter: " . ($params->{output_path} || "not set"));
    
    # result_folder() returns the output_path parameter and may try to create workspace
    my $output_folder = eval { $app->result_folder() };
    if ($@) {
        log_message("WARNING", "Could not get result_folder: $@");
        $output_folder = $params->{output_path} || "./test_output";
    }
    log_message("DEBUG", "Output folder: " . ($output_folder || "undefined"));
    
    # For testing, allow local output if workspace not available
    if (!$output_folder || $output_folder eq '.') {
        $output_folder = $ENV{TEST_OUTPUT_DIR} || "./alphafold_output";
        log_message("INFO", "Using local output directory: $output_folder");
        make_path($output_folder) unless -d $output_folder;
    }
    
    # Clean up the output folder path - remove trailing slashes and dots
    $output_folder =~ s/\/+$//;  # Remove trailing slashes
    $output_folder =~ s/\/\.$//;  # Remove trailing /.
    
    my $output_base = $params->{output_file} // "alphafoldv2_result";
    
    # Create a unique subfolder for this run using timestamp and task ID
    my $timestamp = strftime("%Y%m%d_%H%M%S", localtime);
    my $task_id = $app->{task_id} // "unknown";
    my $run_folder = "${output_base}_${timestamp}_${task_id}";
    $output_folder = "$output_folder/$run_folder";
    
    log_message("INFO", "Output configuration - Base: $output_base, Folder: $output_folder");

    
    # Stage input files
    my $staged_inputs = stage_inputs($app, $params, $stage_dir);
    log_message("DEBUG", "Staged inputs: " . Dumper($staged_inputs)) if $ENV{P3_DEBUG};

    # Execute main tool
    my $results = undef;

    # Change later to split pipeline and allow for recompute or reuse of results
    # For now, always execute the tool and set to zero for denbugging workspace issues
    if (1) {
        $results = execute_tool($app, $params, $staged_inputs, $work_dir, $stage_dir);
    } else {
        log_message("DEBUG", "AlphaFold execution is disabled for testing purposes");
        $results = {
            work_dir => $work_dir,
            exit_code => 0,
            command => ["echo", "AlphaFold execution skipped for testing"]
        };
    }
    # Collect and save outputs
    collect_outputs($app, $results, $output_folder, $output_base, $params);
    
    log_message("INFO", "AlphaFold analysis completed successfully");
    



    if ($@) {
        my $error = $@;
        log_message("ERROR", "AlphaFold analysis failed: $error");
        
        # Re-throw the error for the framework to handle
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
    
    # Required parameters
    die "Missing required parameter: fasta_paths" unless $params->{fasta_paths};
    die "Missing required parameter: output_path" unless $params->{output_path};
    
    # Set defaults for optional parameters
    $params->{model_preset} //= 'monomer';
    $params->{db_preset} //= 'reduced_dbs';
    $params->{output_dir} //= '/output';
    
    # Validate model preset
    my @valid_models = qw(monomer monomer_ptm monomer_casp14 multimer);
    unless (grep { $_ eq $params->{model_preset} } @valid_models) {
        die "Invalid model_preset: $params->{model_preset}. Must be one of: " . join(", ", @valid_models);
    }
    
    # Validate database preset
    my @valid_dbs = qw(full_dbs reduced_dbs);
    unless (grep { $_ eq $params->{db_preset} } @valid_dbs) {
        die "Invalid db_preset: $params->{db_preset}. Must be one of: " . join(", ", @valid_dbs);
    }
    
    # Validate database directory if not using backend default
    if ($params->{data_dir} && !application_backend_dir()) {
        die "Database directory not accessible: $params->{data_dir}" unless -d $params->{data_dir};
    }
    
    log_message("INFO", "Parameters validated successfully");
}

=head2 stage_inputs

Downloads and prepares input files from workspace or processes input data.

=cut

sub stage_inputs {
    my($app, $params, $stage_dir) = @_;
    
    log_message("INFO", "Staging input files");
    
    my $staged_inputs = {};
    
    # Stage FASTA input
    if ($params->{fasta_paths}) {
        my $fasta_input = $params->{fasta_paths};
        
        # Check if it's a local file first (most common in testing)
        if (-f $fasta_input) {
            log_message("INFO", "Using local FASTA file: $fasta_input");
            $staged_inputs->{fasta_paths} = $fasta_input;
        }
        # Check if it's a workspace path
        elsif ($app->workspace) {
            log_message("DEBUG", "Checking if $fasta_input exists in workspace");
            if (eval { $app->workspace->exists($fasta_input) }) {
                my $file_path = "$stage_dir/input.fasta";
                log_message("INFO", "Downloading FASTA from workspace: $fasta_input");
                $app->workspace->download_file($fasta_input, $file_path, 1);
                $staged_inputs->{fasta_paths} = $file_path;
            }
        }
        # Check if it's raw sequence data
        elsif ($fasta_input =~ /^>/) {
            my $file_path = "$stage_dir/input.fasta";
            log_message("INFO", "Writing FASTA data to file");
            write_file($file_path, $fasta_input);
            $staged_inputs->{fasta_paths} = $file_path;
        }
        else {
            die "Cannot access FASTA input: $fasta_input";
        }
        
        # Validate FASTA format
        validate_fasta($staged_inputs->{fasta_paths});
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
    
    log_message("INFO", "Executing AlphaFold");
    
    # Get allocated resources
    my $threads = $ENV{P3_ALLOCATED_CPU} // 8;
    my $use_gpu = $ENV{P3_ALLOCATED_GPU} ? 1 : 0;
    
    # We're always in the container in production (BV-BRC runs services in containers)
    # The script is executed inside the alphafold_unified_patric.sif container
    
    log_message("INFO", "Running AlphaFold in container environment");
    
    # Build the AlphaFold command
    my @cmd = ("python", "/app/alphafold/run_alphafold.py");
    # Add FASTA input path
    if ($staged_inputs->{fasta_paths}) {
        push @cmd, "--fasta_paths", $staged_inputs->{fasta_paths};
    }
    
    # Output directory is always work_dir
    push @cmd, "--output_dir", $work_dir;


    # Get database directory
    my $db_path = get_database_directory($params);
    
    push @cmd, "--data_dir", $db_path;
    
    # Common databases for all presets
    push @cmd, "--uniref90_database_path", "$db_path/uniref90/uniref90.fasta";
    push @cmd, "--mgnify_database_path", "$db_path/mgnify/mgy_clusters_2022_05.fa";
    push @cmd, "--template_mmcif_dir", "$db_path/pdb_mmcif/mmcif_files";
    push @cmd, "--obsolete_pdbs_path", "$db_path/pdb_mmcif/obsolete.dat";
    
    # Database paths based on db_preset
    my $db_preset = $params->{db_preset} // "reduced_dbs";
    if ($db_preset eq "full_dbs") {
        push @cmd, "--bfd_database_path", "$db_path/bfd/bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt";
        push @cmd, "--uniref30_database_path", "$db_path/uniref30/UniRef30_2021_03";
    } elsif ($db_preset eq "reduced_dbs") {
        push @cmd, "--small_bfd_database_path", "$db_path/small_bfd/bfd-first_non_consensus_sequences.fasta";
    }
    
    # Database paths based on model_preset  
    my $model_preset = $params->{model_preset} // "monomer";
    if ($model_preset eq "multimer") {
        push @cmd, "--pdb_seqres_database_path", "$db_path/pdb_seqres/pdb_seqres.txt";
        push @cmd, "--uniprot_database_path", "$db_path/uniprot/uniprot.fasta";
    } else {
        # monomer, monomer_ptm, monomer_casp14
        push @cmd, "--pdb70_database_path", "$db_path/pdb70/pdb70";
    }
    
    # Model and database presets
    push @cmd, "--db_preset", $db_preset;
    push @cmd, "--model_preset", $model_preset;
    
    # Required constants with proper defaults
    push @cmd, "--max_template_date", $params->{max_template_date} // "2022-01-01";
    push @cmd, "--use_gpu_relax=" . ($use_gpu ? "true" : "false");

    # Example command building:
    # push @cmd, "--input", $staged_inputs->{input_file} if $staged_inputs->{input_file};
    # push @cmd, "--output", "$work_dir/output.txt";
    # push @cmd, "--threads", $threads;
    # push @cmd, "--param", $params->{param_value} if defined $params->{param_value};
    
    # Log command for debugging
    log_message("INFO", "Executing command: " . join(" ", @cmd));
    
    # Execute AlphaFold
    my $rc = system(@cmd);
    
    if ($rc != 0) {
        my $exit_code = $rc >> 8;
        my $signal = $rc & 127;
        
        # Provide helpful error messages based on exit code
        my $error_msg = "AlphaFold execution failed with exit code $exit_code";
        
        if ($signal) {
            $error_msg .= " (killed by signal $signal)";
        }
        
        if ($exit_code == 137) {
            $error_msg .= " - Out of memory. Consider using reduced_dbs or requesting more memory.";
        } elsif ($exit_code == 124) {
            $error_msg .= " - Execution timeout. Consider requesting more runtime.";
        }
        
        log_message("ERROR", $error_msg);
        die $error_msg;
    }
    
    log_message("INFO", "AlphaFold execution completed successfully");
    
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
    
    log_message("INFO", "Collecting outputs to: $output_folder");
    
    my $work_dir;

    if ($results) {
        $work_dir = $results->{work_dir};
    } else {
        $work_dir = "./work";
    }

    # AlphaFold outputs are in $work_dir since we set --output_dir=$work_dir
    # The structure is: work_dir/target_name/[various output files]
    
    # Check if workspace is available


    my $op;
    if (! $app->workspace->exists($params->{output_path})) {
        log_message("INFO", "Output path does not exist in workspace, creating $params->{output_path}");
        $op = $app->result_folder();

        if ($op) {
            log_message("INFO", "Output path exists in workspace");
        } else {
            log_message("WARNING", "Output path does not exist in workspace");
            die "Output path does not exist in workspace";
        }
    }

    print $op . "\n" if $op;



    
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
                log_message("DEBUG", "Saving PDB: $file -> $save_path") if $ENV{P3_DEBUG};
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
                log_message("DEBUG", "Saving Crystallographic Information File (CIF): $file -> $save_path") if $ENV{P3_DEBUG};
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
                log_message("DEBUG", "Saving PKL: $file -> $save_path") if $ENV{P3_DEBUG};
                $app->workspace->save_file_to_file($file, {}, $save_path, 'unspecified', 1);
            }
        }
        
        # Collect JSON files (timings, ranking_debug)
        my @json_files = glob("$target_path/*.json");
        for my $file (@json_files) {
            if (-f $file) {
                my $basename = basename($file);
                my $save_path = "$output_folder/${target_dir}_${basename}";
                log_message("DEBUG", "Saving JSON: $file -> $save_path") if $ENV{P3_DEBUG};
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
                    log_message("DEBUG", "Saving Multiple Sequence Alignments (MSA): $file -> $save_path") if $ENV{P3_DEBUG};
                    $app->workspace->save_file_to_file($file, {},
                                                     $save_path,
                                                     'txt', 1);
                }
            }
        }
    }
    
    log_message("INFO", "Output collection completed. Files saved to: $output_folder");
    
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
            log_message("DEBUG", "Cleaning up directory: $dir");
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

=head2 log_message

Centralized logging function with timestamp and level.

=cut

sub log_message {
    my($level, $message) = @_;
    
    return unless $ENV{P3_LOG_LEVEL} || $ENV{P3_DEBUG} || $level eq 'ERROR' || $level eq 'INFO';
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    print STDERR "[$timestamp] [$level] $message\n";
}


=head2 get_database_directory

Determines the appropriate database directory based on configuration.

=cut

sub get_database_directory {
    my($params) = @_;
    
    # Priority order:
    # 1. Check application_backend_dir() if it returns a valid path
    # 2. Use /databases as default (standard container mount point)
    # 3. Explicit parameter (override if provided)
    # 4. Environment variable
    # 5. Other fallback locations
    
    # Try to get backend directory
    my $backend_dir = eval { application_backend_dir() };
    
    # Check if backend_dir is valid and databases exist there
    if ($backend_dir && $backend_dir ne '' && -d "$backend_dir/databases") {
        log_message("INFO", "Using backend database directory: $backend_dir/databases");
        return "$backend_dir/databases";
    }
    
    # Default container mount point - check this next
    if (-d "/databases") {
        log_message("INFO", "Using container database directory: /databases");
        return "/databases";
    }
    
    # Check explicit parameter
    if ($params->{data_dir} && -d $params->{data_dir}) {
        log_message("INFO", "Using database directory from parameters: $params->{data_dir}");
        return $params->{data_dir};
    }
    
    # Check environment variable
    if ($ENV{ALPHAFOLD_DB_DIR} && -d $ENV{ALPHAFOLD_DB_DIR}) {
        log_message("INFO", "Using database directory from environment: $ENV{ALPHAFOLD_DB_DIR}");
        return $ENV{ALPHAFOLD_DB_DIR};
    }
    
    # Other fallback locations
    my @fallback_locations = ('/alphafold/databases', './databases');
    for my $loc (@fallback_locations) {
        if (-d $loc) {
            log_message("INFO", "Using fallback database directory: $loc");
            return $loc;
        }
    }
    
    die "Cannot find AlphaFold database directory. Please ensure databases are mounted at /databases " .
        "or set data_dir parameter to the correct location.";
}

=head2 validate_fasta

Validates FASTA file format and content.

=cut

sub validate_fasta {
    my($fasta_file) = @_;
    
    die "FASTA file not found: $fasta_file" unless -f $fasta_file;
    
    my $content = read_file($fasta_file);
    my @lines = split /\n/, $content;
    
    my $seq_count = 0;
    my $total_length = 0;
    my $in_sequence = 0;
    my $current_seq_length = 0;
    
    for my $line (@lines) {
        chomp $line;
        next if $line =~ /^\s*$/;  # Skip blank lines
        
        if ($line =~ /^>/) {
            # Header line
            $seq_count++;
            if ($seq_count > 1 && $current_seq_length == 0) {
                die "Empty sequence found in FASTA file";
            }
            $total_length += $current_seq_length;
            $current_seq_length = 0;
            $in_sequence = 1;
        } elsif ($in_sequence) {
            # Sequence line - validate amino acid content
            $line =~ s/\s//g;  # Remove whitespace
            
            # Standard amino acids plus ambiguity codes
            unless ($line =~ /^[ACDEFGHIKLMNPQRSTVWYBXZ*-]*$/i) {
                die "Invalid characters in sequence: $line";
            }
            
            $current_seq_length += length($line);
        } else {
            die "FASTA format error: sequence before header";
        }
    }
    
    # Add last sequence
    $total_length += $current_seq_length;
    
    die "No sequences found in FASTA file" if $seq_count == 0;
    die "Empty sequence found in FASTA file" if $current_seq_length == 0;
    
    # Warn about very long sequences
    if ($total_length > 2500) {
        log_message("WARNING", "Long sequence detected ($total_length residues). This may require significant computational resources.");
    }
    
    log_message("INFO", "FASTA validation passed: $seq_count sequence(s), $total_length total residues");
    
    return {
        sequences => $seq_count,
        total_length => $total_length
    };
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