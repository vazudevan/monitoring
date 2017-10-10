#!/usr/bin/perl 

# This script collects inventory of virtual machines that have been powered Off.
# along with the time when they were powered off and by whom. Used to compare
# Nagios configs and disable them from monitoring.
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

Opts::parse();
Opts::validate();
Util::connect();
# getting all powered off vms
my $vms = Vim::find_entity_views(
	view_type => 'VirtualMachine',
	filter => { 'runtime.powerState' => 'poweredOff' },
	properties => ['name','config'],
	);

print "name,time,user\n";
foreach (@$vms) {
	# skipping templates
	next if(($_->config->template));

	# fetch poweroff events of vm
	my $eventMgr = Vim::get_view(mo_ref => Vim::get_service_content()->eventManager);
	my $events = $eventMgr->QueryEvents(
		filter => EventFilterSpec->new(
			type => ['VmPoweredOffEvent'],
			entity => EventFilterSpecByEntity->new( entity => $_,
				recursion => EventFilterSpecRecursionOption->new( "self" )
			),
		),
	);
	
	# the latest event from list
	my $event = pop @$events;
	if ($event) {
		print "\"" . $_->name . "\","; 
		print "\"" . $event->createdTime . "\","; 
		print "\"" . $event->userName . "\"\n"; 
	} else {
		print "\"" . $_->name . "\","; 
		print ",\n";
	}
}

Util::disconnect();