#!/usr/bin/perl -w
# --
# mkStats.pl - send stats output via email
# Copyright (C) 2001-2006 Martin Edenhofer <martin+code@otrs.org>
# --
# $Id: mkStats.pl,v 1.35 2006-07-13 10:43:20 tr Exp $
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# --

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin)."/Kernel/cpan-lib";

use strict;

use vars qw($VERSION);

$VERSION = '$Revision: 1.35 $';
$VERSION =~ s/^\$.*:\W(.*)\W.+?$/$1/;

use Getopt::Std;
use Kernel::Config;
use Kernel::System::Time;
use Kernel::System::Main;
use Kernel::System::DB;
use Kernel::System::Log;
use Kernel::System::Email;
use Kernel::System::CheckItem;
use Kernel::System::Stats;
use Kernel::System::Group;
use Kernel::System::User;
use Kernel::System::CSV;


# --
# create common objects
# --
my %CommonObject = ();
$CommonObject{UserID} = 1;
$CommonObject{ConfigObject}    = Kernel::Config               ->new();
$CommonObject{LogObject}       = Kernel::System::Log          ->new(
    LogPrefix => 'OTRS-SendStats',
    %CommonObject,
);
$CommonObject{CSVObject}       = Kernel::System::CSV          ->new(%CommonObject);
$CommonObject{TimeObject}      = Kernel::System::Time         ->new(%CommonObject);
$CommonObject{MainObject}      = Kernel::System::Main         ->new(%CommonObject);
$CommonObject{DBObject}        = Kernel::System::DB           ->new(%CommonObject);
$CommonObject{GroupObject}     = Kernel::System::Group        ->new(%CommonObject);
$CommonObject{UserObject}      = Kernel::System::User         ->new(%CommonObject);
$CommonObject{StatsObject}     = Kernel::System::Stats        ->new(%CommonObject);
$CommonObject{CheckItemObject} = Kernel::System::CheckItem    ->new(%CommonObject);
$CommonObject{EmailObject}     = Kernel::System::Email        ->new(%CommonObject);

# --
# get options
# --
my %Opts = ();
getopt('nrsmhop', \%Opts);
if ($Opts{'h'}) {
    print "mkStats.pl <Revision $VERSION> - OTRS cmd stats\n";
    print "Copyright (C) 2003-2006 OTRS GmbH, http://www.otrs.com/\n";
    print "usage: mkStats.pl -n <StatNumber> [-p <PARAM_STRING>] [-o <DIRECTORY>] [-r <RECIPIENT> -s <SENDER>] [-m <MESSAGE>]\n";
    print "       <PARAM_STRING> e. g. 'Year=1977&Month=10' (only for static files)\n";
    print "       <DIRECTORY> /output/dir/\n";
    exit 1;
}
# required output param check
if (!$Opts{'o'} && !$Opts{'r'}) {
    print STDERR "ERROR: Need -o /tmp/ OR -r email\@example.com [-m 'some message']\n";
    exit 1;
}
# stats module check
if (!$Opts{'n'}) {
    print STDERR "ERROR: Need -n StatNumber\n";
    exit 1;
}
# fill up body
if (!$Opts{'m'} && $Opts{'p'}) {
    $Opts{'m'} .= "Stats with following options:\n\n";
    $Opts{'m'} .= "StatNumber: $Opts{'n'}\n";
    my @P = split(/&/, $Opts{'p'}||'');
    foreach (@P) {
        my ($Key, $Value) = split(/=/, $_, 2);
        $Opts{'m'} .= "$Key: $Value\n";
    }
}
# only necessary for emails
if (!$Opts{'m'} && $Opts{'r'}) {
    print STDERR "ERROR: Need -m 'some message (necessary for emails)'\n";
    exit 1;
}

# recipient check
if ($Opts{'r'}) {
    if (!$CommonObject{CheckItemObject}->CheckEmail(Address => $Opts{'r'})) {
        print STDERR "ERROR: " . $CommonObject{CheckItemObject}->CheckError() . "\n";
        exit 1;
    }
}
# sender, if given
if (!$Opts{'s'}) {
    $Opts{'s'} = '';
}
# directory check
if ($Opts{'o'} && !-e $Opts{'o'}) {
    print STDERR "ERROR: No such directory: $Opts{'o'}\n";
    exit 1;
}

if ($Opts{'n'}) {
    my $StatNumber = $Opts{'n'};
    my $StatID     = $CommonObject{StatsObject}->StatNumber2StatID(StatNumber => $StatNumber);
    if (!$StatID) {
        print STDERR "ERROR: No StatNumber: $Opts{'n'}\n";
        exit 1;
    }

    my ($s,$m,$h, $D,$M,$Y) = $CommonObject{TimeObject}->SystemTime2Date(
        SystemTime => $CommonObject{TimeObject}->SystemTime(),
    );

    my %GetParam   = ();
    my $Stat = $CommonObject{StatsObject}->StatsGet(StatID => $StatID);

    if ($Stat->{StatType} eq 'static') {
        $GetParam{Year}  = $Y;
        $GetParam{Month} = $M;
        $GetParam{Day}   = $D;

        # get params from -p
        # only for static files
        my $Params = $CommonObject{StatsObject}->GetParams(StatID => $StatID);
        foreach my $ParamItem (@{$Params}) {
            if (!$ParamItem->{Multiple}) {
                my $Value = GetParam(
                    Param => $ParamItem->{Name},
                );
                if (defined($Value)) {
                    $GetParam{$ParamItem->{Name}} = GetParam(
                        Param => $ParamItem->{Name},
                    );
                }
                elsif (defined($ParamItem->{SelectedID})) {
                    $GetParam{$ParamItem->{Name}} = $ParamItem->{SelectedID};
                }
            }
            else {
                my @Value = GetArray(
                    Param => $ParamItem->{Name},
                );
                if (@Value) {
                    $GetParam{$ParamItem->{Name}} = \@Value;
                }
                elsif (defined($ParamItem->{SelectedID})) {
                    $GetParam{$ParamItem->{Name}} = [$ParamItem->{SelectedID}];
                }
            }
        }
    }
    elsif ($Stat->{StatType} eq 'dynamic') {
        %GetParam = %{$Stat};
    }

    # run stat...
    my @StatArray = @{$CommonObject{StatsObject}->StatsRun(
        StatID       => $StatID,
        GetParam => \%GetParam,
    )};

    # generate output
    my $TitleArrayRef = shift (@StatArray);
    my $Title = $TitleArrayRef->[0];
    my $HeadArrayRef = shift (@StatArray);
    my $CountStatArray = @StatArray;
    my $Time = sprintf("%04d-%02d-%02d %02d:%02d:%02d",$Y,$M,$D,$h,$m,$s);
    if (!@StatArray) {
        push(@StatArray, [' ',0]);
    }

    # Greate the CVS data
    my $Output = "Name: $Title; Created: $Time\n";
    $Output .= $CommonObject{CSVObject}->Array2CSV(
        Head => $HeadArrayRef,
        Data => \@StatArray,
    );

    # save the csv with the title and timestamp as filename
    my $Filename = $CommonObject{StatsObject}->StringAndTimestamp2Filename(
        String => $Title . " Created",
    );

    my %Attachment = (
        Filename    => $Filename . ".csv",
        ContentType => "text/csv",
        Content     => $Output,
        Encoding    => "base64",
        Disposition => "attachment",
    );

    # write output
    if ($Opts{'o'}) {
        if (open(OUT, "> $Opts{'o'}/$Attachment{Filename}")) {
            print OUT $Attachment{Content};
            close (OUT);
            print "NOTICE: Writing file $Opts{'o'}/$Attachment{Filename}.\n";
            exit;
        }
        else {
            print STDERR "ERROR: Can't write $Opts{'o'}/$Attachment{Filename}: $!\n";
            exit 1;
        }
    }
    # send email
    elsif ($CommonObject{EmailObject}->Send(
        From       => $Opts{'s'},
        To         => $Opts{'r'},
        Subject    => "[Stats - $CountStatArray Records] $Title; Created: $Time",
        Body       => $Opts{'m'},
        Attachment => [
            {
               %Attachment,
            },
        ],
    )) {
        print "NOTICE: Email sent to '$Opts{'r'}'.\n";
    }
}

sub GetParam {
    my %Param = @_;
    if (!$Param{Param}) {
        print STDERR "ERROR: Need Param Arg in GetParam()\n";
    }
    my @P = split(/&/, $Opts{'p'}||'');
    foreach (@P) {
        my ($Key, $Value) = split(/=/, $_, 2);
        if ($Key eq $Param{Param}) {
            return $Value;
        }
    }
    return;
}
sub GetArray {
    my %Param = @_;
    if (!$Param{Param}) {
        print STDERR "ERROR: Need Param Arg in GetArray()\n";
    }
    my @P = split(/&/, $Opts{'p'}||'');
    my @Array;
    foreach (@P) {
        my ($Key, $Value) = split(/=/, $_, 1);
        if ($Key eq $Param{Param}) {
            push (@Array, $Value);
        }
    }
    return @Array;
}
