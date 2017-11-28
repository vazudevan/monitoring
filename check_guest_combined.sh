#!/bin/sh
# args ipaddress, _vmname, mor_ref, inventory, perffile, _allips, [true] or leave blank
# # true as seventh arugment will ping, else it will not.
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
ping='/usr/lib64/nagios/plugins/check_icmp -w 3000.0,80% -c 5000.0,100% -p 5 -H '
ipaddress=$1
hostname=$2
mor_ref=$3
vCenterInventory=$4
vCenterPerfFile=$5 #
AllIPs=$6
DoPing=$7  # set it to 'true' if ping check should be done. 


PoweredOff=$(grep -iE "(${hostname},|\"${hostname}\",|{mor_ref})" ${vCenterPerfFile} | grep -i poweredOff)
PoweredON=$(grep -iE "(${hostname},|\"${hostname}\",|{mor_ref})" ${vCenterPerfFile} | grep -i poweredOn)
IpsInInventory=$(grep -iE "(${hostname},|\"${hostname}\",)" ${vCenterInventory} | awk -F',' '{print $6}' | tr -d '"' | tr ',' ' ')
oldfile=$(find ${vCenterPerfFile} -mmin +10)

if [[ ${oldfile} ]]; then
	logger -p local6.notice -t VMGUESTCHECK "vmware guest performace data file is stale, older than 10 mins"
fi

if [ ${1} != "unknown.ip" ]; then
	if [[ "${AllIPs}" != "${IpsInInventory}" ]]; then
		logger -p local6.notice -t VMGUESTCHECK "IP appears to have changed for vm ${hostname}"
	fi
	if [[ ${DoPing} == "true" ]]; then
		icmp_result=$($ping $1)
		icmp_return=$?
	else
		icmp_return=1
	fi
	if [[ ${icmp_return} -eq 0 ]]; then
		echo ${icmp_result}
		exit ${icmp_return}
	elif [[ ${PoweredOff} ]]; then
		echo "DOWN: Powered Off in vCenter"
		exit 2
	elif [[ ${PoweredON} && ${DoPing} ]]; then
		echo "UP: Powered ON in vCenter, but IP not pinging"
		exit 2
	elif [[ ${PoweredON} ]]; then
		echo "UP: Powered ON in vCenter"
		exit 0
	fi
else
	if [[ ${IpsInInventory }]]; then
		logger -p local6.notice -t VMGUESTCHECK "IP appears to have changed for vm ${hostname}"
	fi
	# does have an ip
	if [[ ${PoweredOff} ]]; then
		echo "DOWN: Powered Off in vCenter"
		exit 2
	elif [[ ${PoweredON} ]]; then	
		echo "UP: Powered ON in vCenter"
		exit 0
fi
echo "OK: No conditions met, may be a rare scenario"
exit 0
