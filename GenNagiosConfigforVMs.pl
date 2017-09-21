#!/usr/bin/perl
# Used for automatic additon of VM guests to monitoring.
#
# This script reads vm inventory csv and:
# - Generates nagios host config for vms.
# - Checks if vm is reachable via icmp, and sets suitable host check command
# - Skips the vms that are already monitored.
# - vms not having IPs are printed out to STDERR, without creating confg for
# them.
# - Requres host and service template to be configured with require settings.
#
# Install Text::CSV from CPAN as yum version appears incomplete, and errors.
#
# Copyright (c) 2017 Vasudevan <vazudevan@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is furnished
# to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# This file is part of the monitoring bundle that can be found
# at https://github.com/vazudevan/monitoring
#

use Text::CSV qw( csv );
use Net::Ping;
use Switch;
use Getopt::Long;

my %opt = ();
GetOptions (\%opt, 'inventory=s', 'exception=s', 'destination=s');
GetOptions ("help" => sub { HelpMessage() });

sub HelpMessage {
    print "Config Options:\n  --inventory (path to inventory file)\n";
    print "\tCSV file containing the virtual machine inventory\n";
    print "  --exception\n";
    print "\tCSV file containing the exception hosts to exclude\n";
    print "  --destination\n";
    print "\tDestination folder where nagios configuration files to be created\n\n";
}

if ( scalar values %opt < 3 ) { &HelpMessage; exit 22; }
if (! -e $opt{inventory} && -r _ ) { 
    print STDERR "File $opt{inventory} not readable or does not exists\n"; 
    exit 2;
}
if (! -e $opt{exception} && -r _ ) { 
    print STDERR "File $opt{exception} not readable or does not exists\n";
    exit 2; 
}
if (! -e $opt{destination} && -w _ ) { 
    print STDERR "Direcory $opt{destination} not writable or does not exists\n"; 
    exit 2;
}

my $aoh = csv (
    in       => "$opt{inventory}",
    encoding => "utf-8",
    headers  => "auto",
);

foreach $row (@$aoh) {
    my @ips = split(/-/, $row->{AllIPs});
    my $p = Net::Ping->new('icmp');
    my $reachable = 0;
    my $reachable_ip = '';
    my $monitored = 0;
    my $host = '';
    my $config = '';

    # If IP not found in inventory
    if (! scalar @ips) {
        print STDERR "Missing ip, not proceeding: $row->{Name}\n";
        next;
    }
    # Look for exceptions
    open (my $ex, '<',"$opt{exception}") 
        or print STDERR "Exception file not found\n";
    EXCEPTION: while (<$ex>) {
        my $hostname = lc ($row->{Name});
        my ($eHost, $eIP, $eAlias) = split /,/;
        if ($eHost eq $hostname) {
            $monitored = 1;
            print STDERR "Excluding from exceptions, not proceeding: $row->{Name}\n";
            last EXCEPTION;
        }
        foreach $ip (@ips) {
            if ($eIP eq $ip) {
                $monitored = 1;
                print STDERR "Excluding from exceptions, not proceeding: $row->{Name}\n";
                last EXCEPTION;
            }
        }
    }

    close ($ex);

    # Check if host is already monitored
    open (my $fh, '<', '/var/spool/nagios/objects.cache') 
        or die "unable to open nagios object cache.";
    NAGIOS:	while (<$fh>) {
        my $hostname = lc ($row->{Name});
        if (/^\s+host_name\s+$hostname\s+/) { 
            $monitored = 1; 
            print STDERR "Host already monitored, not proceeding: $row->{Name}\n";
            last NAGIOS;
        }
        foreach $ip (@ips) {
            if (/^\s+address\s+$row->{PrimaryIP}\s+/) { 
                $monitored = 1; 
                print STDERR "IP already monitored, not proceeding: $row->{PrimaryIP}\n";
                last NAGIOS;
            }
        }
    }
    close ($fh);

    if (! $monitored) {
        # Check if the IP is reachable by ICMP, and which IP in case of multiple
        LBL_IP: {
            foreach my $ip (@ips) {
                if ($p->ping($ip)) {
                    $reachable = 1;
                    $reachable_ip = $ip;
                    last LBL_IP;
                } else { $reachable_ip = $row->{PrimaryIP}; }
            }
        }
        # print the host definitions
        $host = lc $row->{Name};
        $host =~ s/[\s\(\)]/_/g;
        $config = "define host {\n";
        switch($row->{OSFamily}) {
            case 'windowsGuest' { $config .= "    use          vmware-windows-guest\n" ; }
            case 'linuxGuest'   { $config .= "    use          vmware-centos-guest\n" ; }
            else { $config .=  "    use          vmware-generic-guest\n" ; }
        }
        $config .=  "    host_name	  $host\n" ;
        $config .=  "    address      $reachable_ip\n" ;
        if ($row->{FQDN}) { $config .= "    alias        $row->{FQDN}\n" ;}
        $config .=  "    notes        $row->{VMPath}\n" ;
        if  (! $reachable) {
            $config .= "    check_command        check-host-by-vcenter\n" 
        }
        if ($row->{OS} =~ /red/i) {  
            $config .= "    icon_mage        redhat.png\n";
        }
        $config .=  "}\n";

        # Services config
        $config .=  "define service {\n";
        $config .=  "    host_name            $host\n";
        $config .=  "    use                  cpu-usage-by-vc\n";
        $config .=  "    service_description  CPU Usage\n";
        $config .=  "    #contact_groups      contact-group\n";
        $config .=  "}\n";

        $config .=  "define service {\n";
        $config .=  "    host_name            $host\n";
        $config .=  "    use                  mem-usage-by-vc\n";
        $config .=  "    service_description  Memory Usage\n";
        $config .=  "    #contact_groups      contact-group\n";
        $config .=  "}\n";

        $config .=  "define service {\n";
        $config .=  "    host_name            $host\n";
        $config .=  "    use                  disk-latency-by-vc\n";
        $config .=  "    service_description  Disk Latency\n";
        $config .=  "    #contact_groups      contact-group\n";
        $config .=  "}\n";


        # write config file
        my $filename = "$opt{destination}" . "/" . "$host" . ".cfg";
        open (my $out, '>', $filename) or print STDERR "could not create '$filename' $!\n";
        print $out $config;
        close ($out);
    } 
}

