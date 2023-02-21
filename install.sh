#!/bin/bash

RELEASE=$1
NODE_REPO=$2
HOOBS_REPO=$3
IMG_TYPE=$4

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

alternates() {
	if [ "|${RELEASE}|" == "|${1}|" ]; then
		RELEASE="${2}"
	fi
}

reset() {
	rm -f /usr/share/keyrings/nodesource.gpg > /dev/null 2>&1
	rm -f /usr/share/keyrings/yarnkey.gpg > /dev/null 2>&1
	rm -f /usr/share/keyrings/hoobs.gpg > /dev/null 2>&1

	rm -f /etc/apt/sources.list.d/nodesource.list > /dev/null 2>&1
	rm -f /etc/apt/sources.list.d/yarn.list > /dev/null 2>&1
	rm -f /etc/apt/sources.list.d/hoobs.list > /dev/null 2>&1
}

validate() {
	if $(uname -m | grep -Eq ^armv6); then
		message "device specifies an unsupported architecture" "armv6" "err"

		exit 1
	fi

	alternates "solydxk-9" "stretch"
	alternates "sana" "jessie"
	alternates "kali-rolling" "bullseye"
	alternates "Tyche" "stretch"
	alternates "Nibiru" "buster"
	alternates "Horizon" "stretch"
	alternates "Continuum" "stretch"
	alternates "patito feo" "buster"
	alternates "maya" "precise"
	alternates "qiana" "trusty"
	alternates "rafaela" "trusty"
	alternates "rebecca" "trusty"
	alternates "rosa" "trusty"
	alternates "sarah" "xenial"
	alternates "serena" "xenial"
	alternates "sonya" "xenial"
	alternates "sylvia" "xenial"
	alternates "tara" "bionic"
	alternates "tessa" "bionic"
	alternates "tina" "bionic"
	alternates "tricia" "bionic"
	alternates "ulyana" "focal"
	alternates "ulyssa" "focal"
	alternates "uma" "focal"
	alternates "betsy" "jessie"
	alternates "cindy" "stretch"
	alternates "debbie" "buster"
	alternates "luna" "precise"
	alternates "freya" "trusty"
	alternates "loki" "xenial"
	alternates "juno" "bionic"
	alternates "hera" "bionic"
	alternates "odin" "focal"
	alternates "toutatis" "precise"
	alternates "belenos" "trusty"
	alternates "flidas" "xenial"
	alternates "etiona" "bionic"
	alternates "lugalbanda" "xenial"
	alternates "anokha" "wheezy"
	alternates "anoop" "jessie"
	alternates "drishti" "stretch"
	alternates "unnati" "buster"
	alternates "bunsen-hydrogen" "jessie"
	alternates "helium" "stretch"
	alternates "lithium" "buster"
	alternates "chromodoris" "jessie"
	alternates "green" "sid"
	alternates "amber" "buster"
	alternates "jessie" "jessie"
	alternates "ascii" "stretch"
	alternates "beowulf" "buster"
	alternates "ceres" "sid"
	alternates "panda" "sid"
	alternates "unstable" "sid"
	alternates "stable" "buster"
	alternates "onyedi" "stretch"
	alternates "lemur-3" "stretch"
	alternates "orel" "stretch"
	alternates "dolcetto" "stretch"
	alternates "jammy" "bullseye"

	if [ "|${RELEASE}|" == "|debian|" ]; then
		FOUND=$([ -e /etc/debian_version ] && cut -d/ -f1 < /etc/debian_version)

		if [ "|${NEWRELEASE}|" != "||" ]; then
			RELEASE=$FOUND
		fi
	fi
}

availability() {
	bash -c "curl -sLf -o /dev/null 'https://deb.nodesource.com/${NODE_REPO}/dists/${RELEASE}/Release'"

	if [[ $? != 0 ]]; then
		message "device specifies an unsupported operating system" "" "err"

		exit 1
	fi
}

prerequisites() {
	PREREQUISITES=" ca-certificates libgnutls30 git make gcc g++ avahi-daemon avahi-utils ntp"

	if [ ! -e /usr/lib/apt/methods/https ]; then
		PREREQUISITES="${PREREQUISITES} apt-transport-https"
	fi

	if [ ! -x /usr/bin/lsb_release ]; then
		PREREQUISITES="${PREREQUISITES} lsb-release"
	fi

	if [ ! -x /usr/bin/curl ]; then
		PREREQUISITES="${PREREQUISITES} curl"
	fi

	if [ ! -x /usr/bin/gpg ]; then
		PREREQUISITES="${PREREQUISITES} gnupg"
	fi

	if [ "|${PREREQUISITES}|" != "||" ]; then
		bash -c "apt-get update && apt-get install -y${PREREQUISITES}"
	fi
}

setup() {
	curl -ks https://deb.nodesource.com/gpgkey/nodesource.gpg.key | gpg --dearmor | tee /usr/share/keyrings/nodesource.gpg > /dev/null
	curl -ks https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | tee /usr/share/keyrings/yarnkey.gpg > /dev/null
	curl -ks https://dl.hoobs.org/debian/pubkey.gpg.key | gpg --dearmor | tee /usr/share/keyrings/hoobs.gpg > /dev/null

	echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/${NODE_REPO} ${RELEASE} main" | tee /etc/apt/sources.list.d/nodesource.list > /dev/null 2>&1
	echo "deb-src [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/${NODE_REPO} ${RELEASE} main" | tee -a /etc/apt/sources.list.d/nodesource.list > /dev/null 2>&1
	echo "" | tee -a /etc/apt/sources.list.d/nodesource.list > /dev/null 2>&1

	echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list > /dev/null 2>&1
	echo "" | tee -a /etc/apt/sources.list.d/yarn.list > /dev/null 2>&1

	echo "deb [signed-by=/usr/share/keyrings/hoobs.gpg] https://dl.hoobs.org/debian/ ${HOOBS_REPO} main" | tee /etc/apt/sources.list.d/hoobs.list > /dev/null 2>&1
	echo "" | tee -a /etc/apt/sources.list.d/hoobs.list > /dev/null 2>&1

	apt-get update
}

users() {
	message "Adding service user" "" "info"

	if ! id -u service > /dev/null 2>&1; then
		adduser --gecos service --disabled-password service > /dev/null 2>&1
	fi

	adduser service sudo > /dev/null 2>&1
	echo "service:u9V5*Qh*J0P_ERd" | chpasswd > /dev/null 2>&1

	message "Adding HOOBS user" "" "info"

	if ! id -u hoobs > /dev/null 2>&1; then
		adduser --gecos hoobs --disabled-password hoobs > /dev/null 2>&1
	fi

	adduser hoobs sudo > /dev/null 2>&1
	echo "hoobs:hoobsadmin" | chpasswd > /dev/null 2>&1
	passwd --expire hoobs > /dev/null 2>&1

	message "Locking root account" "" "info"
	passwd -l root 2>&1
}

install() {
	message "Installing HOOBS" "" "info"

	apt-get update
	apt-get install -y nodejs yarn network-manager helm hbs-portal hbs-vendor hoobs-cli hoobsd hoobs-gui ffmpeg

	message "Enabling HelM" "" "info"
	systemctl enable helm.service > /dev/null 2>&1

	message "Initilizing the HOOBS hub" "" "info"
	hbs install --port 80
}

watchdog() {
	message "Installing watchdog" "" "info"

	apt-get update
	apt-get install -y watchdog
	update-rc.d watchdog defaults

	echo "watchdog-device = /dev/watchdog" | tee /etc/watchdog.conf > /dev/null 2>&1
	echo "watchdog-timeout = 15" | tee -a /etc/watchdog.conf > /dev/null 2>&1
	echo "max-load-1 = 24" | tee -a /etc/watchdog.conf > /dev/null 2>&1
	echo "min-memory = 1" | tee -a /etc/watchdog.conf > /dev/null 2>&1
	echo "" | tee -a /etc/watchdog.conf > /dev/null 2>&1

	systemctl enable watchdog > /dev/null 2>&1
}

message "Validating NodeSource repository" "${RELEASE}" "info"

validate

message "Installing required packages" "" "info"

reset
prerequisites

message "Checking if NodeSource release is available" "${RELEASE}" "info"

availability

message "Configuring extra apt repos" "" "info"

setup
users

case $IMG_TYPE in
	sdcard)
		message "Configuring image" "SD Card RPI" "info"

		echo "ID=card" | tee /etc/hoobs > /dev/null 2>&1
		echo "MODEL=SD Card" | tee -a /etc/hoobs > /dev/null 2>&1
		echo "SKU=7-45114-12419-7" | tee -a /etc/hoobs > /dev/null 2>&1
		echo "" | tee -a /etc/hoobs > /dev/null 2>&1
		;;

	box)
		message "Configuring image" "HOOBS Box HSLF-2" "info"

		echo "ID=box" | tee /etc/hoobs > /dev/null 2>&1
		echo "MODEL=HSLF-2" | tee -a /etc/hoobs > /dev/null 2>&1
		echo "SKU=7-45114-12418-0" | tee -a /etc/hoobs > /dev/null 2>&1
		echo "" | tee -a /etc/hoobs > /dev/null 2>&1
		;;
esac

install
watchdog

message "Configuring WiFi captive portal" "" "info"

echo "[Unit]" | tee /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
echo "Description=Capitive WiFi Portal" | tee -a /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
echo "After=NetworkManager.service" | tee -a /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
echo "Before=helm.service hoobsd.service" | tee -a /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
echo "" | tee -a /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
echo "[Service]" | tee -a /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
echo "Type=oneshot" | tee -a /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
echo "ExecStart=/usr/bin/hbs-portal" | tee -a /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
echo "" | tee -a /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
echo "[Install]" | tee -a /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
echo "WantedBy=multi-user.target" | tee -a /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
echo "" | tee -a /usr/lib/systemd/system/hbs-portal.service > /dev/null 2>&1
