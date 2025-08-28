#!/usr/bin/env perl
#
# Script to inspect BV-BRC workspace API from inside container
#

use strict;
use warnings;
use Data::Dumper;

print "=== Perl Module Search Paths ===\n";
print join("\n", @INC), "\n\n";

print "=== Looking for Bio::KBase modules ===\n";
foreach my $path (@INC) {
    if (-d "$path/Bio/KBase") {
        print "Found Bio::KBase at: $path/Bio/KBase\n";
        system("ls -la $path/Bio/KBase/ | head -10");
    }
    if (-d "$path/Bio/P3") {
        print "Found Bio::P3 at: $path/Bio/P3\n";
        system("ls -la $path/Bio/P3/ | head -10");
    }
}

print "\n=== Trying to load workspace modules ===\n";
eval {
    require Bio::KBase::AppService::AppScript;
    print "Loaded Bio::KBase::AppService::AppScript\n";
};

eval {
    require Bio::P3::Workspace::WorkspaceClient;
    print "Loaded Bio::P3::Workspace::WorkspaceClient\n";
};

eval {
    require Bio::P3::Workspace::WorkspaceImpl;
    print "Loaded Bio::P3::Workspace::WorkspaceImpl\n";
};

print "\n=== Checking AppScript workspace methods ===\n";
eval {
    require Bio::KBase::AppService::AppScript;
    my $test_app = bless {}, 'Bio::KBase::AppService::AppScript';
    
    print "Methods available:\n";
    # Check what methods the workspace object might have
    if ($test_app->can('workspace')) {
        print "  - workspace() method exists\n";
    }
    if ($test_app->can('result_folder')) {
        print "  - result_folder() method exists\n";
    }
};

print "\n=== Looking for workspace documentation ===\n";
# The error showed /vol/patric3/production/workspace/
if (-d "/vol/patric3/production/workspace/deployment/lib") {
    print "Found workspace deployment at: /vol/patric3/production/workspace/deployment/lib\n";
    system("find /vol/patric3/production/workspace/deployment/lib -name '*.pod' -o -name 'README*' 2>/dev/null | head -5");
}

print "\nDone.\n";