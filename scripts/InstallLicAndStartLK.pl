#!/opt/LifeKeeper/bin/perl
#
# Copyright (c) SIOS Technology, Corp.
#
#	Description: Install Licenses and Start LifeKeeper
#
#	Options: -u: URL for License
#
# Exit codes:
#	0 - License installed and LifeKeeper started
#	1 - License or LifeKeeper start failed
#

BEGIN { require '/etc/default/LifeKeeper.pl'; }
use LK;
use strict;
use Getopt::Std;
use vars qw($opt_u);

my $DEFAULT_LIC_NAME = "/evalkeys.lic";
my $ret;

#
# Usage
#
sub usage {
	print "Usage:\n";
	print "\t-u <URL to LifeKeeper license file>\n";
	exit 1;
}

#
# Get the LifeKeeper license file using the URL passed in.
#
# Return values:
#	undef - failed to obtain LifeKeeper license
#	path - local file location for license file
#
sub GetLicenseFile {
	my $licenseURL = shift;
	my $cmd = "curl --connect-timeout 5 -s -S";
	my @results;
	my $retCode;
	my $localPath = "/tmp/LK4L.lic";
	my @cmdOutput;
	my $s3URI = 0;

	# Check to see if the url is actually an s3 uri
	if ($licenseURL =~ /^s3:\/\/(.*)/) {
		$cmd = "/usr/local/bin/aws s3 cp";
		
		# Lop off the trailing slash if there is one. 
		if ($licenseURL =~ /(.*)\/$/) {
			chop $licenseURL;
		}
		$s3URI = 1;
	} 
	
	# Append default license filename to the end of the URL if 
	# no license filename already present
	if ($licenseURL =~ m/.lic$/) {
		$cmd = $cmd . " $licenseURL";
	} else {
		$cmd = $cmd . " $licenseURL" . $DEFAULT_LIC_NAME;
	}

	# Download file from S3 URI, and save it to localPath location.
	if ($s3URI) {
		$cmd = $cmd . " $localPath";
		@results = `$cmd 2>&1`;
		if($?) {
			return $localPath;
		} else {
			return undef;
		}
	}

	# Get the license file
	@results = `$cmd 2>&1`;

	# Check and see if what is returned looks like a license file
	# because curl does not always set the return code to a non-zero
	# value when there is a problem.  For example a typo on the URL
	# could result in a "404 Not Found" issue but curl exits with 0.
	if (!grep (/^FEATURE lklc/, @results)) {
		print "Failed to obtain LifeKeeper license.\n";
		foreach (@results) {
			print "$_";
		}
		return undef;
	}

	# Save the license info to a file for use with lkkeyins.
	open(LIC, ">$localPath") or die "Failed to open license file!";
	foreach (@results) {
		print LIC $_;
	}
	close (LIC);

	return $localPath;
}

#
# Install the LifeKeeper license
#
# Return values:
#	0 - License install failed
#	1 - License installed
#
sub InstallLicense {
	my $licenseFile = shift;
	my $cmd = "lkkeyins $licenseFile";
	my @results;
	my $retCode;

	@results = `$cmd 2>&1`;
	$retCode = $? >> 8;
	if ($retCode != 0) {
		print "Failed to install the LifeKeeper license\n";
		foreach (@results) {
			print "$_";
		}
		return 0;
	}

	unlink $licenseFile;
	return 1;
}

#
# Check if LifeKeeper is running
#
# Return values:
#	0 - LifeKeeper is not running
#	1 - LifeKeeper is running
#
sub CheckLKStatus {
	my @results;
	my $retCode;

	@results = `lktest >/dev/null 2>&1`;
	$retCode = $? >> 8;

	return !$retCode;
}

#
# Start LifeKeeper
#
# Return values:
#	0 - LifeKeeper did not start
#	1 - LifeKeeper started
#
sub StartLifeKeeper {
	my @results;
	my $retCode;

	@results = `lkstart >/dev/null 2>&1`;
	sleep 5;

	# Test for LK running
	foreach (1..3) {
		if (CheckLKStatus()) {
			last;
		}
		sleep 5;
	}
	if (!CheckLKStatus()) {
		print "LifeKeeper start failed.\n";
		return 0;
	}

	# Test for LK init complete
	foreach (1..100) {
		if (-e "/opt/LifeKeeper/config/LK_INITDONE") {
			return 1;
		}
		sleep 2;
	}

	# LifeKeeper init process did not complete.
	print "LifeKeeper startup failed to complete.\n";
	return 0;
}

#
# Main body of script
#
getopts('u:');
if ($opt_u eq '') {
	usage();
}

$ret = CheckLKStatus();
if (!$ret) {
	# LifeKeeper is not running so assume we need to retrieve the license,
	# install it and then start LifeKeeper.
	my $licFile = GetLicenseFile($opt_u);
	if (!defined $licFile) {
		exit 1;
	}
	if (InstallLicense($licFile)) {
		$ret = !(StartLifeKeeper());
	}
}

exit $ret;
