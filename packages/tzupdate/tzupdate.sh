#!/bin/bash

BUILD_VERSION=$1
RELEASE=$2
BOARD=$3
NODE_REPO=$4
IMG_TYPE=$5
BOOT_METHOD=$6

message()
{
	local tmp=""

	[[ -n $2 ]] && tmp="[\e[0;33m $2 \x1B[0m]"

	case $3 in
		err)
			echo -e "[\e[0;31m error \x1B[0m] $1 $tmp"
			;;

		wrn)
			echo -e "[\e[0;35m warn \x1B[0m] $1 $tmp"
			;;

		ext)
			echo -e "[\e[0;32m o.k. \x1B[0m] \e[1;32m$1\x1B[0m $tmp"
			;;

		info)
			echo -e "[\e[0;32m o.k. \x1B[0m] $1 $tmp"
			;;

		*)
			echo -e "[\e[0;32m .... \x1B[0m] $1 $tmp"
			;;
	esac
}

install() {
	message "Installing python" "" "info"

	apt-get update
	apt-get -y install python3-minimal python3-pip

	message "Installing tzupdate" "" "info"

	echo "#!/usr/bin/python3" | tee /usr/bin/tzupdate > /dev/null 2>&1
	echo "# -*- coding: utf-8 -*-" | tee -a /usr/bin/tzupdate > /dev/null 2>&1
	echo "import re" | tee -a /usr/bin/tzupdate > /dev/null 2>&1
	echo "import sys" | tee -a /usr/bin/tzupdate > /dev/null 2>&1
	echo "from tzupdate import main" | tee -a /usr/bin/tzupdate > /dev/null 2>&1
	echo "if __name__ == '__main__':" | tee -a /usr/bin/tzupdate > /dev/null 2>&1
	echo "    sys.argv[0] = re.sub(r'(-script\.pyw|\.exe)?$', '', sys.argv[0])" | tee -a /usr/bin/tzupdate > /dev/null 2>&1
	echo "    sys.exit(main())" | tee -a /usr/bin/tzupdate > /dev/null 2>&1

	chmod 755 /usr/bin/tzupdate

	echo "[Unit]" | tee /usr/lib/systemd/system/tzupdate.service > /dev/null 2>&1
	echo "Description=Timezone Update Service" | tee -a /usr/lib/systemd/system/tzupdate.service > /dev/null 2>&1
	echo "After=network-online.target" | tee -a /usr/lib/systemd/system/tzupdate.service > /dev/null 2>&1
	echo "" | tee -a /usr/lib/systemd/system/tzupdate.service > /dev/null 2>&1
	echo "[Service]" | tee -a /usr/lib/systemd/system/tzupdate.service > /dev/null 2>&1
	echo "Type=oneshot" | tee -a /usr/lib/systemd/system/tzupdate.service > /dev/null 2>&1
	echo "ExecStart=/usr/bin/tzupdate" | tee -a /usr/lib/systemd/system/tzupdate.service > /dev/null 2>&1
	echo "" | tee -a /usr/lib/systemd/system/tzupdate.service > /dev/null 2>&1
	echo "[Install]" | tee -a /usr/lib/systemd/system/tzupdate.service > /dev/null 2>&1
	echo "WantedBy=multi-user.target" | tee -a /usr/lib/systemd/system/tzupdate.service > /dev/null 2>&1
	echo "" | tee -a /usr/lib/systemd/system/tzupdate.service > /dev/null 2>&1

	message "Enabling tzupdate service" "" "info"
	rm -f /etc/systemd/system/multi-user.target.wants/tzupdate.service
	ln -s /lib/systemd/system/tzupdate.service /etc/systemd/system/multi-user.target.wants/tzupdate.service
}

install
