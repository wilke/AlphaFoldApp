# GitHub Issue: Workspace Directory Overwrite Error

## Title
BV-BRC Workspace: "Cannot overwrite directory" error after successful AlphaFold execution

## Labels
- bug
- workspace
- bv-brc
- production

## Description

### Summary
After successful AlphaFold execution and output collection, the BV-BRC framework throws an error when attempting to save job metadata, reporting "Cannot overwrite directory" even though the actual analysis outputs are successfully saved.

### Current Behavior
1. AlphaFold executes successfully
2. All output files (PDB, JSON, MSA) are correctly saved to workspace
3. Error occurs at the final step when framework tries to save job results
4. Despite the error, all scientific outputs are accessible in the workspace

### Expected Behavior
The job should complete without errors, allowing the framework to save job metadata without conflicts.

### Error Message
```
Error -32603 invoking create:
_ERROR_Cannot overwrite directory /awilke@bvbrc/home/AlphaFold/test_run/ on save!_ERROR_ 
at /vol/patric3/production/workspace/deployment/lib/Bio/P3/Workspace/WorkspaceImpl.pm line 186.
```

### Steps to Reproduce
1. Run AlphaFold service with parameters:
   ```json
   {
     "fasta_paths": "test_protein_small.fasta",
     "output_path": "/awilke@bvbrc/home/AlphaFold/test_run",
     "model_preset": "monomer",
     "db_preset": "reduced_dbs"
   }
   ```
2. Service completes successfully with all outputs saved
3. Error occurs after line: `[INFO] Output collection completed. Files saved to: ...`

### Environment
- **Container**: alphafold_unified_patric.sif
- **Service**: App-AlphaFold.pl v1.0.0
- **BV-BRC Module**: Bio::KBase::AppService::AppScript
- **Workspace Module**: Bio::P3::Workspace::WorkspaceImpl
- **Date**: 2025-08-28

### Analysis

#### Root Cause
The error appears to originate from the BV-BRC framework attempting to create or overwrite a directory that already exists. This happens in the post-processing phase, likely when:

1. The service creates output folder: `/awilke@bvbrc/home/AlphaFold/test_run/alphafoldv2_result_[timestamp]_[taskid]/`
2. Framework later tries to create or save to parent directory: `/awilke@bvbrc/home/AlphaFold/test_run/`
3. Workspace API rejects the overwrite attempt

#### Code Location
- Error originates in: `/vol/patric3/production/workspace/deployment/lib/Bio/P3/Workspace/WorkspaceImpl.pm:186`
- Called after: `App-AlphaFold.pl` completes output collection
- Likely triggered by: AppScript framework's job result saving mechanism

### Workaround
Currently, the error can be safely ignored as all scientific outputs are successfully saved before the error occurs.

### Proposed Solutions

#### Option 1: Check Before Create (Recommended)
Modify the workspace interaction to check if directory exists before attempting to create:
```perl
if (!$app->workspace->exists({paths => [$output_path]})) {
    $app->workspace->create({
        objects => [[$output_path, 'folder', {}]], 
        overwrite => 0
    });
}
```

#### Option 2: Use Unique Output Paths
Ensure each run uses a completely unique output path by including timestamp in the base path:
```perl
my $output_path = $params->{output_path} . "_" . strftime("%Y%m%d_%H%M%S", localtime);
```

#### Option 3: Handle in Framework
The BV-BRC AppScript framework could be modified to handle existing directories gracefully when saving job results.

### Impact
- **Severity**: Low-Medium
- **User Impact**: Confusing error message despite successful completion
- **Data Impact**: None - all outputs are saved correctly
- **Production Readiness**: Does not block production deployment

### Related Files
- `/nfs/ml_lab/projects/ml_lab/cepi/alphafold/AlphaFoldApp/service-scripts/App-AlphaFold.pl`
- `/dev_container/modules/app_service/lib/Bio/KBase/AppService/AppScript.pm`
- `/dev_container/modules/Workspace/lib/Bio/P3/Workspace/WorkspaceImpl.pm`

### Test Results
```
[SUCCESS] Test completed successfully
[INFO] Output files in work directory:
work/test_protein_small/unrelaxed_model_2_pred_0.pdb
work/test_protein_small/ranked_3.pdb
work/test_protein_small/ranked_4.pdb
work/test_protein_small/ranked_2.pdb
work/test_protein_small/confidence_model_3_pred_0.json
work/test_protein_small/timings.json
```

### Additional Context
- This issue occurs in the BV-BRC framework layer, not in the AlphaFold service itself
- All AlphaFold outputs (structures, confidence scores, MSAs) are successfully generated and saved
- The error appears to be related to job metadata rather than scientific outputs

### Acceptance Criteria
- [ ] Service completes without workspace overwrite errors
- [ ] Job metadata is saved successfully
- [ ] All outputs remain accessible in workspace
- [ ] No duplicate folders are created
- [ ] Existing workspace contents are not inadvertently overwritten

---

**Note**: This issue should be reported to the BV-BRC development team as it may affect other services using the same framework.