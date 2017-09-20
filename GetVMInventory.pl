#!/usr/bin/perl 

# This script collects inventory details required for building nagios host 
# configuration and outputs comma seperated values to stdout.  The output from
# this script can be used by another script to build the nagios config files.
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
use warnings;
use VMware::VIRuntime;

use Data::Validate::IP qw(is_ipv4 is_ipv6);
Opts::parse();
Opts::validate();
Util::connect();

my $vm_views = Vim::find_entity_views(
	view_type => 'VirtualMachine',
	filter => {
		'runtime.powerState' => 'poweredOn'
	}
);
Util::trace(0, "Name,FQDN,Primary IP,OSFamily,VMPath,Datacenter,VMToolsStatus,FullOSName,AllIPs\n");

# Collect inventory and output csv
foreach my $vm_view (@$vm_views) {
	my ($vm_name, $vm_hostname, $tools_status, $ip_address, 
		$path, $dc, $os_family, $fullos, $ip_string);
	
	$vm_name = $vm_view->name;
	if (defined($vm_view->guest->hostName)) {
		$vm_hostname = $vm_view->guest->hostName;
		$ip_address = $vm_view->guest->ipAddress;
		$os_family = $vm_view->guest->guestFamily;
		$fullos = $vm_view->guest->guestFullName;
	}
	if (defined($vm_view->guest->toolsStatus)) {
		$tools_status = $vm_view->guest->toolsStatus->val;
	} else {
		$tools_status = 'Not defined';
	}
	#my $path = Util::get_inventory_path($vm_view, Vim->get_vim());
	my @array = split(/\//, Util::get_inventory_path($vm_view, Vim->get_vim()) );
    # Split with limit would be better
	$dc = shift @array;  # Datacenter
	my @throw = shift @array; # Root folder
	@throw = pop @array; # vm folder
	$path = join('/', @array);

	if (defined($vm_view->guest->net)) {
        my $ifaces = $vm_view->guest->net;
	    foreach my $h (@$ifaces) {
            my $ipref = $h->ipAddress;
            # Lets take only ipv4 valid IPs
            foreach my $ip (@$ipref) {
                if (is_ipv4($ip)) {
                    unless ($ip =~ /169\.254/) {
                        $ip_string .= "$ip-";

                    }
                }
             }
        }
        chop $ip_string;
    }


     Util::trace(0, "$vm_name,$vm_hostname,$ip_address,$os_family,$path,$dc,$tools_status,$fullos,$ip_string\n");
}
Util::disconnect();

#guest->hostName # full name with FQDN
#->ipAddress # primary IP
#->@net->macAddress
#->@net->ipAddress
#->@net->network # vlan
#->toolsRunningStatus
#->toolsStatus->val
#->disk->@->capacity
#->disk->@->diskpath
#->disk->@->freeSpace
#->guestFamily
#->guestFullName
