#!/usr/bin/env perl

# This script lists the nagios hosts that are DOWN, for use to automatically 
# remove hosts from monitoring.
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

use Getopt::Long;
use LWP::Simple;
use JSON;
use DateTime;

my $days = 3;
my $all;
GetOptions ('threshold-days=i' => \$days, 
		'all' => \$all,
		"help" => sub { HelpMessage() });

sub HelpMessage {
    print "Config Options:\n  --threshold-days \n";
	print "\tDays.  Lists nagios hosts DOWN since days. default is 3.\n";
	print "--all\n";
	print "\t Lists all nagios hosts that are in DOWN state\n\n";
    exit 0;
}

my $content = get("http://localhost/nagios/cgi-bin/statusjson.cgi?query=hostlist&hoststatus=down");
die "Couldn't fetch nagios staus!" unless defined $content;

my $response = decode_json($content);
my @hosts;

if (($$response{result}{type_code} == 0)) {
	my $data = $$response{data};
	my $host_ref = $$data{hostlist};
	@hosts = keys % { $host_ref };
} else {
	print "Non Ok returned from nagios: $$response{result}{type_text}\n";
}

foreach (@hosts) {
	my $url = "http://localhost/nagios/cgi-bin/statusjson.cgi?query=host&hostname=" . $_;
	$content = get($url);
	$response = decode_json($content);
	my $data = $$response{data};
	my $status = $$data{host};
	my $down = ($$status{last_state_change}/1000);
	my $dt = DateTime->now;
	my $now = $dt->epoch;
	my $manydays = (86400 * $days);
	if (($now - $down) > $manydays) {
		#host is down for more than three days. lets disable it.
		print $_ . "\n";
	}
}
