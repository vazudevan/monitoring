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
use strict;
use VMware::VIRuntime;

use Data::Validate::IP qw(is_ipv4 is_ipv6);
Opts::parse();
Opts::validate();
Util::connect();

# list of fields we want in order of output in csv
my @fields = qw(dc cluster path name fqdn ipaddress family os morid);

# get dcs
my $dc_views = Vim::find_entity_views(view_type => 'Datacenter');
my $header_string;
foreach (@fields) {
	$header_string .= "\"" . $_ . "\",";
}
chop $header_string;
print $header_string . "\n";

# for each dc; get cluster
foreach my $dc_view (@$dc_views) {
	# get clusters
    my $ccr = Vim::find_entity_views(view_type => 'ClusterComputeResource',
    begin_entity => $dc_view);
	
	# if cluster exists
	if ($ccr) {
		
		# get vms within each cluster
		foreach my $cluster (@$ccr) {
			
			my $vm_views = Vim::find_entity_views(
				view_type => 'VirtualMachine',
				filter => { 'runtime.powerState' => 'poweredOn' },
				begin_entity => $cluster,
				properties => ['name','guest'],
				);
				output_inventory($vm_views, $dc_view, $cluster );
		}
	} else {
		
		# Cluster not found, so get vms within DC instead
		my $vm_views = Vim::find_entity_views(
			view_type => 'VirtualMachine',
			filter => { 'runtime.powerState' => 'poweredOn' },
			begin_entity => $dc_view,
			properties => ['name','guest'],
			);
			output_inventory($vm_views, $dc_view);
	}
}

Util::disconnect();

sub output_inventory {
	# vmview, dcview, # clusterview
	my ($vms, $dc, $cluster) = @_;

	foreach my $vm (@$vms) {
		
		my (%row, $ip_string, $row_string);
	
		$row{'dc'} = $dc->name;
		$row{'cluster'} = $cluster->name;
		$row{'name'} = $vm->name;
		$row{'morid'} = $vm->get_property('mo_ref')->value;

		if (defined($vm->guest->hostName)) {
			$row{'fqdn'}= $vm->guest->hostName;
			#$ip_address = $vm->guest->ipAddress;
			$row{'family'} = $vm->guest->guestFamily;
			$row{'os'} = $vm->guest->guestFullName;
		}
		$row{'path'} = Util::get_inventory_path($vm, Vim->get_vim());

		if (defined($vm->guest->net)) {
	        my $ifaces = $vm->guest->net;
		    foreach my $h (@$ifaces) {
	            my $ipref = $h->ipAddress;
	            # Lets take only ipv4 valid IPs
	            foreach my $ip (@$ipref) {
	                if (is_ipv4($ip)) {
	                    unless ($ip =~ /169\.254/) {
	                        $ip_string .= "$ip,";

	                    }
	                }
	             }
	        }
	        chop $ip_string;
			$row{'ipaddress'} = $ip_string;
	    }

#	    my $mor_host = $vm->runtime->host;
#	    $row{'host'} = Vim::get_view(mo_ref => $mor_host)->name;
#    
#	    my ($devices, $mac_string);
#	    $devices = $vm->config->hardware->device;
#	    foreach(@$devices) {
#	        if ($_->isa('VirtualEthernetCard')) {
#	            $mac_string .= $_->macAddress . ",";
#	        }
#	    }
#	    chop $mac_string;
#		$row{'macaddress} = $mac_string;

	foreach my $field (@fields) {
		$row_string .= "\"" . $row{$field} . "\",";
	}
	print $row_string . "\n";
	
	}
}


