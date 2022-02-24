#!/bin/bash

cleaning()
{
	case $1 in
		debs)
			if [[ -d "${DEB_STORAGE}" ]]; then
				display_alert "Cleaning ${DEB_STORAGE} for" "$BOARD $BRANCH" "info"

				find "${DEB_STORAGE}" -name "${CHOSEN_UBOOT}_*.deb" -delete
				find "${DEB_STORAGE}" \( -name "${CHOSEN_KERNEL}_*.deb" -o \
					-name "armbian-*.deb" -o \
					-name "${CHOSEN_KERNEL/image/dtb}_*.deb" -o \
					-name "${CHOSEN_KERNEL/image/headers}_*.deb" -o \
					-name "${CHOSEN_KERNEL/image/source}_*.deb" -o \
					-name "${CHOSEN_KERNEL/image/firmware-image}_*.deb" \) -delete
				[[ -n $RELEASE ]] && rm -f "${DEB_STORAGE}/${RELEASE}/${CHOSEN_ROOTFS}"_*.deb
				[[ -n $RELEASE ]] && rm -f "${DEB_STORAGE}/${RELEASE}/armbian-desktop-${RELEASE}"_*.deb
			fi
			;;

		ubootdebs)
			if [[ -d "${DEB_STORAGE}" ]]; then
				display_alert "Cleaning ${DEB_STORAGE} for u-boot" "$BOARD $BRANCH" "info"

				find "${DEB_STORAGE}" -name "${CHOSEN_UBOOT}_*.deb" -delete
			fi
			;;

		extras)
			if [[ -n $RELEASE && -d ${DEB_STORAGE}/extra/$RELEASE ]]; then
				display_alert "Cleaning ${DEB_STORAGE}/extra for" "$RELEASE" "info"
				rm -rf "${DEB_STORAGE}/extra/${RELEASE}"
			fi
			;;

		alldebs)
			[[ -d "${DEB_STORAGE}" ]] && display_alert "Cleaning" "${DEB_STORAGE}" "info" && rm -rf "${DEB_STORAGE}"/*
			;;

		cache)
			[[ -d "${SRC}"/cache/rootfs ]] && display_alert "Cleaning" "rootfs cache (all)" "info" && find "${SRC}"/cache/rootfs -type f -delete
			;;

		images)
			[[ -d "${DEST}"/images ]] && display_alert "Cleaning" "output/images" "info" && rm -rf "${DEST}"/images/*
			;;

		sources)
			[[ -d "${SRC}"/cache/sources ]] && display_alert "Cleaning" "sources" "info" && rm -rf "${SRC}"/cache/sources/* "${DEST}"/buildpkg/*
			;;

		oldcache)
			if [[ -d "${SRC}"/cache/rootfs && $(ls -1 "${SRC}"/cache/rootfs/*.lz4 2> /dev/null | wc -l) -gt "${ROOTFS_CACHE_MAX}" ]]; then
				display_alert "Cleaning" "rootfs cache (old)" "info"
				(cd "${SRC}"/cache/rootfs; ls -t *.lz4 | sed -e "1,${ROOTFS_CACHE_MAX}d" | xargs -d '\n' rm -f)
				(cd "${SRC}"/cache/rootfs; ls -t *.asc | sed -e "1,${ROOTFS_CACHE_MAX}d" | xargs -d '\n' rm -f)
			fi
			;;
	esac
}

exit_with_error()
{
	local _file
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _description=$1
	local _highlight=$2

	_file=$(basename "${BASH_SOURCE[1]}")

	local stacktrace="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"

	display_alert "ERROR in function $_function" "$stacktrace" "err"
	display_alert "$_description" "$_highlight" "err"
	display_alert "Process terminated" "" "info"

	if [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
		display_alert "MOUNT" "${MOUNT}" "err"
		display_alert "SDCARD" "${SDCARD}" "err"
		display_alert "Here's a shell." "debug it" "err"
		bash < /dev/tty || true
	fi

	overlayfs_wrapper "cleanup"

	exec {FD}>/var/lock/armbian-debootstrap-losetup
	flock -u "${FD}"

	exit 255
}

get_package_list_hash()
{
	local package_arr exclude_arr
	local list_content

	read -ra package_arr <<< "${DEBOOTSTRAP_LIST} ${PACKAGE_LIST}"
	read -ra exclude_arr <<< "${PACKAGE_LIST_EXCLUDE}"

	( ( printf "%s\n" "${package_arr[@]}"; printf -- "-%s\n" "${exclude_arr[@]}" ) | sort -u; echo "${1}" ) \
		| md5sum | cut -d' ' -f 1
}

create_sources_list()
{
	local release=$1
	local basedir=$2

	[[ -z $basedir ]] && exit_with_error "No basedir passed to create_sources_list"

	case $release in
		stretch|buster)
			cat <<-EOF > "${basedir}"/etc/apt/sources.list
			deb http://${DEBIAN_MIRROR} $release main contrib non-free
			deb http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free
			deb http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free
			deb http://${DEBIAN_SECURTY} ${release}/updates main contrib non-free
			EOF
			;;

		bullseye|bookworm|trixie)
			cat <<-EOF > "${basedir}"/etc/apt/sources.list
			deb http://${DEBIAN_MIRROR} $release main contrib non-free
			deb http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free
			deb http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free
			deb http://${DEBIAN_SECURTY} ${release}-security main contrib non-free
			EOF
			;;

		sid)
			cat <<-EOF > "${basedir}"/etc/apt/sources.list
			deb http://${DEBIAN_MIRROR} $release main contrib non-free
			EOF
			;;

		xenial|bionic|focal|hirsute|impish|jammy)
			cat <<-EOF > "${basedir}"/etc/apt/sources.list
			deb http://${UBUNTU_MIRROR} $release main restricted universe multiverse
			deb http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse
			deb http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse
			deb http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
			EOF
			;;
	esac

	echo "deb http://"$([[ $BETA == yes ]] && echo "beta" || echo "apt" )".armbian.com $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > "${basedir}"/etc/apt/sources.list.d/armbian.list

	display_alert "Adding armbian repository and authentication key" "/etc/apt/sources.list.d/armbian.list" "info"
	cp "${SRC}"/config/armbian.key "${basedir}"
	chroot "${basedir}" /bin/bash -c "cat armbian.key | apt-key add - > /dev/null 2>&1"
	rm "${basedir}"/armbian.key
}

improved_git()
{
	local realgit=$(command -v git)
	local retries=3
	local delay=10
	local count=1

	while [ $count -lt $retries ]; do
		$realgit "$@"

		if [[ $? -eq 0 || -f .git/index.lock ]]; then
			retries=0
			break
		fi

		let count=$count+1
		sleep $delay
	done
}

clean_up_git ()
{
	local target_dir=$1

	git -C $target_dir clean -qdf
	git -C $target_dir checkout -qf HEAD
}

waiter_local_git ()
{
	for arg in $@;do
		case $arg in
			url=*|https://*|git://*)	eval "local url=${arg/url=/}"
				;;
			dir=*|/*/*/*)	eval "local dir=${arg/dir=/}"
				;;
			*=*|*:*)	eval "local ${arg/:/=}"
				;;
		esac
	done

	for var in url name dir branch; do
		[ "${var#*=}" == "" ] && exit_with_error "Error in configuration"
	done

	local reachability

	if [ "$OFFLINE_WORK" == "yes" ]; then
		local offline=true
	else
		local offline=false
	fi

	local work_dir="$(realpath ${SRC}/cache/sources)/$dir"

	mkdir -p $work_dir
	cd $work_dir || exit_with_error
	display_alert "Checking git sources" "$dir $url$name/$branch" "info"

	if [ "$(git rev-parse --git-dir 2>/dev/null)" != ".git" ]; then
		git init -q .

		if [ -n "$VAR_SHALLOW_ORIGINAL" ]; then
			(
				$VAR_SHALLOW_ORIGINAL

				display_alert "Add original git sources" "$dir $name/$branch" "info"

				if [ "$(improved_git ls-remote -h $url $branch | \
					awk -F'/' '{if (NR == 1) print $NF}')" != "$branch" ];then
					display_alert "Bad $branch for $url in $VAR_SHALLOW_ORIGINAL"
					exit 177
				fi

				git remote add -t $branch $name $url

				if [ "${start_tag}.1" == "$(improved_git ls-remote -t $url ${start_tag}.1 | \
					awk -F'/' '{ print $NF }')" ]
				then
					improved_git fetch --shallow-exclude=$start_tag $name
				else
					improved_git fetch --depth 1 $name
				fi

				improved_git fetch --deepen=1 $name
				git gc
			)

			[ "$?" == "177" ] && exit
		fi
	fi

	files_for_clean="$(git status -s | wc -l)"

	if [ "$files_for_clean" != "0" ];then
		display_alert " Cleaning .... " "$files_for_clean files"
		clean_up_git $work_dir
	fi

	if [ "$name" != "$(git remote show | grep $name)" ];then
		git remote add -t $branch $name $url
	fi

	if ! $offline; then
		for t_name in $(git remote show);do
			improved_git fetch $t_name
		done
	fi

	reachability=false

	for var in obj tag commit branch;do
		eval pval=\$$var

		if [ -n "$pval" ] && [ "$pval" != *HEAD ]; then
			case $var in
				obj|tag|commit) obj=$pval ;;
				branch) obj=${name}/$branch ;;
			esac

			if  t_hash=$(git rev-parse $obj 2>/dev/null);then
				reachability=true
				break
			else
				display_alert "Variable $var=$obj unreachable for extraction"
			fi
		fi
	done

	if $reachability && [ "$t_hash" != "$(git rev-parse @ 2>/dev/null)" ];then
		display_alert "Switch $obj = $t_hash"
		git checkout -qf $t_hash
	else
		display_alert "Up to date"
	fi
}

fetch_from_repo()
{
	local url=$1
	local dir=$2
	local ref=$3
	local ref_subdir=$4

	url=${url//'https://github.com/'/$GITHUB_SOURCE}

	if [ "$OFFLINE_WORK" == "yes" ]; then
		local offline=true
	else
		local offline=false
	fi

	[[ -z $ref || ( $ref != tag:* && $ref != branch:* && $ref != head && $ref != commit:* ) ]] && exit_with_error "Error in configuration"

	local ref_type=${ref%%:*}

	if [[ $ref_type == head ]]; then
		local ref_name=HEAD
	else
		local ref_name=${ref##*:}
	fi

	display_alert "Checking git sources" "$dir $ref_name" "info"

	if [[ $ref_subdir == yes ]]; then
		local workdir=$dir/$ref_name
	else
		local workdir=$dir
	fi

	mkdir -p "${SRC}/cache/sources/${workdir}" 2>/dev/null || exit_with_error "No path or no write permission" "${SRC}/cache/sources/${workdir}"

	cd "${SRC}/cache/sources/${workdir}" || exit

	if [[ "$(git rev-parse --git-dir 2>/dev/null)" == ".git" && "$url" != *"$(git remote get-url origin | sed 's/^.*@//' | sed 's/^.*\/\///' 2>/dev/null)" ]]; then
		display_alert "Remote URL does not match, removing existing local copy"
		rm -rf .git ./*
	fi

	if [[ "$(git rev-parse --git-dir 2>/dev/null)" != ".git" ]]; then
		display_alert "Creating local copy"
		git init -q .
		git remote add origin "${url}"
		# Here you need to upload from a new address
		offline=false
	fi

	local changed=false

	if ! $offline; then
		local local_hash

		local_hash=$(git rev-parse @ 2>/dev/null)

		case $ref_type in
			branch)
				local remote_hash

				remote_hash=$(improved_git ls-remote -h "${url}" "$ref_name" | head -1 | cut -f1)
				[[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
				;;

			tag)
				local remote_hash

				remote_hash=$(improved_git ls-remote -t "${url}" "$ref_name" | cut -f1)

				if [[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]]; then
					remote_hash=$(improved_git ls-remote -t "${url}" "$ref_name^{}" | cut -f1)

					[[ -z $remote_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
				fi
				;;

			head)
				local remote_hash

				remote_hash=$(improved_git ls-remote "${url}" HEAD | cut -f1)

				[[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
				;;

			commit)
				[[ -z $local_hash || $local_hash == "@" ]] && changed=true
				;;
		esac
	fi

	if [[ $changed == true ]]; then
		display_alert "Fetching updates"

		case $ref_type in
			branch) improved_git fetch --depth 200 origin "${ref_name}" ;;
			tag) improved_git fetch --depth 200 origin tags/"${ref_name}" ;;
			head) improved_git fetch --depth 200 origin HEAD ;;
		esac

		if [[ $ref_type == commit ]]; then
			improved_git fetch --depth 200 origin "${ref_name}"

			if [[ $? -ne 0 ]]; then
				display_alert "Commit checkout not supported on this repository. Doing full clone." "" "wrn"
				improved_git pull
				git checkout -fq "${ref_name}"
				display_alert "Checkout out to" "$(git --no-pager log -2 --pretty=format:"$ad%s [%an]" | head -1)" "info"
			else
				display_alert "Checking out"
				git checkout -f -q FETCH_HEAD
				git clean -qdf
			fi
		else
			display_alert "Checking out"
			git checkout -f -q FETCH_HEAD
			git clean -qdf
		fi
	elif [[ -n $(git status -uno --porcelain --ignore-submodules=all) ]]; then
		display_alert " Cleaning .... " "$(git status -s | wc -l) files"
		git checkout -f -q HEAD
		git clean -qdf
	else
		display_alert "Up to date"
	fi

	if [[ -f .gitmodules ]]; then
		display_alert "Updating submodules" "" "ext"

		for i in $(git config -f .gitmodules --get-regexp path | awk '{ print $2 }'); do
			cd "${SRC}/cache/sources/${workdir}" || exit

			local surl sref

			surl=$(git config -f .gitmodules --get "submodule.$i.url")
			sref=$(git config -f .gitmodules --get "submodule.$i.branch")

			if [[ -n $sref ]]; then
				sref="branch:$sref"
			else
				sref="head"
			fi

			fetch_from_repo "$surl" "$workdir/$i" "$sref"
		done
	fi
}

display_alert()
{
	[[ -n "${DEST}" ]] && echo "Displaying message: $@" >> "${DEST}"/${LOG_SUBPATH}/output.log

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

export -f display_alert

DISTRIBUTIONS_DESC_DIR="config/distributions"

function distro_menu ()
{
	local distrib_dir="${1}"

	if [[ -d "${distrib_dir}" ]]; then
		local distro_codename="$(basename "${distrib_dir}")"
		local distro_fullname="$(cat "${distrib_dir}/name")"

		options+=("${distro_codename}" "${distro_fullname}")
	fi
}

function distros_options() {
	for distrib_dir in "${DISTRIBUTIONS_DESC_DIR}/"*; do
		distro_menu "${distrib_dir}"
	done
}

function set_distribution_status() {
	local distro_support_desc_filepath="${SRC}/${DISTRIBUTIONS_DESC_DIR}/${RELEASE}/support"

	if [[ ! -f "${distro_support_desc_filepath}" ]]; then
		exit_with_error "Distribution ${distribution_name} does not exist"
	else
		DISTRIBUTION_STATUS="$(cat "${distro_support_desc_filepath}")"
	fi
}

NODESOURCE_DESC_DIR="config/nodesource"

function nodesource_menu ()
{
	local nodesource_dir="${1}"

	if [[ -d "${nodesource_dir}" ]]; then
		local nodesource_tag="$(cat "${nodesource_dir}/tag")"
		local nodesource_codename="$(basename "${nodesource_dir}")"
		local nodesource_fullname="$(cat "${nodesource_dir}/name")"

		options+=("${nodesource_codename}" "${nodesource_fullname} ${nodesource_tag}")
	fi
}

function nodesource_options() {
	for nodesource_dir in "${NODESOURCE_DESC_DIR}/"*; do
		nodesource_menu "${nodesource_dir}"
	done
}

adding_packages()
{
	display_alert "Checking and adding to repository $release" "$3" "ext"

	for f in "${DEB_STORAGE}${2}"/*.deb
	do
		local name version arch

		name=$(dpkg-deb -I "${f}" | grep Package | awk '{print $2}')
		version=$(dpkg-deb -I "${f}" | grep Version | awk '{print $2}')
		arch=$(dpkg-deb -I "${f}" | grep Architecture | awk '{print $2}')
		aptly repo search -architectures="${arch}" -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${1}" 'Name (% '${name}'), $Version (='${version}'), $Architecture (='${arch}')' &>/dev/null

		if [[ $? -ne 0 ]]; then
			display_alert "Adding ${1}" "$name" "info"
			aptly repo add -force-replace=true -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${1}" "${f}" &>/dev/null
		fi
	done
}

addtorepo()
{
	local distributions=("stretch" "bionic" "buster" "bullseye" "focal" "hirsute" "impish" "jammy" "sid")
	local errors=0

	for release in "${distributions[@]}"; do
		local forceoverwrite=""

		if [[ -n $(aptly publish list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}") ]]; then
			aptly publish drop -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" > /dev/null 2>&1
		fi

		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}") ]]; then
			display_alert "Creating section" "main" "info"
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="main" \
			-comment="Armbian main repository" "${release}" >/dev/null
		fi

		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "^utils") ]]; then
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="utils" \
			-comment="Armbian utilities (backwards compatibility)" utils >/dev/null
		fi

		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="${release}-utils" \
			-comment="Armbian ${release} utilities" "${release}-utils" >/dev/null
		fi

		if [[ -z $(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
			aptly repo create -config="${SCRIPTPATH}config/${REPO_CONFIG}" -distribution="${release}" -component="${release}-desktop" \
			-comment="Armbian ${release} desktop" "${release}-desktop" >/dev/null
		fi

		if find "${DEB_STORAGE}"/ -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			adding_packages "$release" "" "main"
		else
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi

		local COMPONENTS="main"

		if find "${DEB_STORAGE}/${release}" -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			adding_packages "${release}-utils" "/${release}" "release packages"
		else
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi

		if find "${DEB_STORAGE}/extra/${release}-utils" -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			adding_packages "${release}-utils" "/extra/${release}-utils" "release utils"
		else
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-utils" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi

		COMPONENTS="${COMPONENTS} ${release}-utils"

		if find "${DEB_STORAGE}/extra/${release}-desktop" -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			adding_packages "${release}-desktop" "/extra/${release}-desktop" "desktop"
		else
			aptly repo add -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" "${SCRIPTPATH}config/templates/example.deb" >/dev/null
		fi

		COMPONENTS="${COMPONENTS} ${release}-desktop"

		local mainnum utilnum desknum

		mainnum=$(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" | grep "Number of packages" | awk '{print $NF}')
		utilnum=$(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" | grep "Number of packages" | awk '{print $NF}')
		desknum=$(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-utils" | grep "Number of packages" | awk '{print $NF}')

		if [ $mainnum -gt 0 ] && [ $utilnum -gt 0 ] && [ $desknum -gt 0 ]; then
			aptly publish -acquire-by-hash -passphrase="${GPG_PASS}" -origin="Armbian" -label="Armbian" -config="${SCRIPTPATH}config/${REPO_CONFIG}" -component="${COMPONENTS// /,}" -distribution="${release}" repo "${release}" ${COMPONENTS//main/} >/dev/null

			if [[ $? -ne 0 ]]; then
				display_alert "Publishing failed" "${release}" "err"
				errors=$((errors+1))

				exit 0
			fi
		else
			errors=$((errors+1))

			local err_txt=": All components must be present: main, utils and desktop for first build"
		fi
	done

	display_alert "Cleaning repository" "${DEB_STORAGE}" "info"
	aptly db cleanup -config="${SCRIPTPATH}config/${REPO_CONFIG}"

	echo ""

	display_alert "List of local repos" "local" "info"
	(aptly repo list -config="${SCRIPTPATH}config/${REPO_CONFIG}") | grep -E packages

	if [[ $errors -eq 0 ]]; then
		if [[ "$2" == "delete" ]]; then
			display_alert "Purging incoming debs" "all" "ext"
			find "${DEB_STORAGE}" -name "*.deb" -type f -delete
		fi
	else
		display_alert "There were some problems $err_txt" "leaving incoming directory intact" "err"
	fi
}

repo-manipulate()
{
	local DISTROS=("stretch" "bionic" "buster" "bullseye" "focal" "hirsute" "impish" "jammy" "sid")

	case $@ in
		serve)
			display_alert "Serving content" "common utils" "ext"
			aptly serve -listen=$(ip -f inet addr | grep -Po 'inet \K[\d.]+' | grep -v 127.0.0.1 | head -1):80 -config="${SCRIPTPATH}config/${REPO_CONFIG}"

			exit 0
			;;

		show)
			for release in "${DISTROS[@]}"; do
				display_alert "Displaying repository contents for" "$release" "ext"
				aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" | tail -n +7
				aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" | tail -n +7
			done

			display_alert "Displaying repository contents for" "common utils" "ext"
			aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" utils | tail -n +7

			echo "done."
			exit 0
			;;

		unique)
			IFS=$'\n'

			while true; do
				LIST=()

				for release in "${DISTROS[@]}"; do
					LIST+=( $(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" | tail -n +7) )
					LIST+=( $(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}-desktop" | tail -n +7) )
				done

				LIST+=( $(aptly repo show -with-packages -config="${SCRIPTPATH}config/${REPO_CONFIG}" utils | tail -n +7) )
				LIST=( $(echo "${LIST[@]}" | tr ' ' '\n' | sort -u))

				new_list=()

				for ((n=0;n<$((${#LIST[@]}));n++));
				do
					new_list+=( "${LIST[$n]}" )
					new_list+=( "" )
				done

				LIST=("${new_list[@]}")
				LIST_LENGTH=$((${#LIST[@]}/2));

				exec 3>&1

				TARGET_VERSION=$(DIALOGRC="${SRC}/config/dialog.conf" dialog --keep-tite --cancel-label "Cancel" --backtitle "BACKTITLE" --no-collapse --title "Remove packages from repositories" --clear --menu "Delete" $((9+${LIST_LENGTH})) 82 65 "${LIST[@]}" 2>&1 1>&3)
				exitstatus=$?;

				exec 3>&-

				if [[ $exitstatus -eq 0 ]]; then
					for release in "${DISTROS[@]}"; do
						aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}"  "${release}" "$TARGET_VERSION"
						aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}"  "${release}-desktop" "$TARGET_VERSION"
					done

					aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}" "utils" "$TARGET_VERSION"
				else
					exit 1
				fi

				aptly db cleanup -config="${SCRIPTPATH}config/${REPO_CONFIG}" > /dev/null 2>&1
			done
			;;

		update)
			addtorepo "update" ""
			cp "${SCRIPTPATH}"config/armbian.key "${REPO_STORAGE}"/public/

			exit 0
			;;

		purge)
			for release in "${DISTROS[@]}"; do
				repo-remove-old-packages "$release" "armhf" "5"
				repo-remove-old-packages "$release" "arm64" "5"
				repo-remove-old-packages "$release" "amd64" "5"
				repo-remove-old-packages "$release" "all" "5"
				aptly -config="${SCRIPTPATH}config/${REPO_CONFIG}" -passphrase="${GPG_PASS}" publish update "${release}" > /dev/null 2>&1
			done

			exit 0
			;;

		purgeedge)
			for release in "${DISTROS[@]}"; do
				repo-remove-old-packages "$release" "armhf" "3" "edge"
				repo-remove-old-packages "$release" "arm64" "3" "edge"
				repo-remove-old-packages "$release" "amd64" "3" "edge"
				repo-remove-old-packages "$release" "all" "3" "edge"
				aptly -config="${SCRIPTPATH}config/${REPO_CONFIG}" -passphrase="${GPG_PASS}" publish update "${release}" > /dev/null 2>&1
			done

			exit 0
			;;

		purgesource)
			for release in "${DISTROS[@]}"; do
				aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${release}" 'Name (% *-source*)'
				aptly -config="${SCRIPTPATH}config/${REPO_CONFIG}" -passphrase="${GPG_PASS}" publish update "${release}"  > /dev/null 2>&1
			done

			aptly db cleanup -config="${SCRIPTPATH}config/${REPO_CONFIG}" > /dev/null 2>&1

			exit 0
			;;
		*)
			echo -e "Usage: repository show | serve | unique | create | update | purge | purgesource\n"
			echo -e "\n show           = display repository content"
			echo -e "\n serve          = publish your repositories on current server over HTTP"
			echo -e "\n unique         = manually select which package should be removed from all repositories"
			echo -e "\n update         = updating repository"
			echo -e "\n purge          = removes all but last 5 versions"
			echo -e "\n purgeedge      = removes all but last 3 edge versions"
			echo -e "\n purgesource    = removes all sources\n\n"
			exit 0
			;;
	esac
}

repo-remove-old-packages() {
	local repo=$1
	local arch=$2
	local keep=$3

	for pkg in $(aptly repo search -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${repo}" "Architecture ($arch)" | grep -v "ERROR: no results" | sort -t '.' -nk4 | grep -e "$4"); do
		local pkg_name

		count=0
		pkg_name=$(echo "${pkg}" | cut -d_ -f1)

		for subpkg in $(aptly repo search -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${repo}" "Name ($pkg_name)"  | grep -v "ERROR: no results" | sort -rt '.' -nk4); do
			((count+=1))

			if [[ $count -gt $keep ]]; then
				pkg_version=$(echo "${subpkg}" | cut -d_ -f2)
				aptly repo remove -config="${SCRIPTPATH}config/${REPO_CONFIG}" "${repo}" "Name ($pkg_name), Version (= $pkg_version)"
			fi
		done
	done
}

wait_for_package_manager()
{
	while true; do
		if [[ "$(fuser /var/lib/dpkg/lock 2>/dev/null; echo $?)" != 1 && "$(fuser /var/lib/dpkg/lock-frontend 2>/dev/null; echo $?)" != 1 ]]; then
			display_alert "Package manager is running in the background." "Please wait! Retrying in 30 sec" "wrn"
			sleep 30
		else
			break
		fi
	done
}

install_pkg_deb ()
{
	local list=""
	local log_file
	local for_install
	local need_autoup=false
	local need_upgrade=false
	local need_clean=false
	local need_verbose=false
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _file=$(basename "${BASH_SOURCE[1]}")
	local tmp_file=$(mktemp /tmp/install_log_XXXXX)

	export DEBIAN_FRONTEND=noninteractive

	list=$(
		for p in $*;do
			case $p in
				autoupdate) need_autoup=true; continue ;;
				upgrade) need_upgrade=true; continue ;;
				clean) need_clean=true; continue ;;
				verbose) need_verbose=true; continue ;;
				\||\(*|*\)) continue ;;
			esac

			echo " $p"
		done
	)

	if [ -d $(dirname $LOG_OUTPUT_FILE) ]; then
		log_file=${LOG_OUTPUT_FILE}
	else
		log_file="${SRC}/output/${LOG_SUBPATH}/install.log"
	fi

	if $need_upgrade; then
		apt-get -q update || echo "apt cannot update" >>$tmp_file
		apt-get -y upgrade || echo "apt cannot upgrade" >>$tmp_file
	fi

	for_install=$(
		for p in $list;do
			if $(dpkg-query -W -f '${db:Status-Abbrev}' $p |& awk '/ii/{exit 1}');then
				apt-cache  show $p -o APT::Cache::AllVersions=no |& \
				awk -v p=$p -v tmp_file=$tmp_file \
				'/^Package:/{print $2} /^E:/{print "Bad package name: ",p >>tmp_file}'
			fi
		done
	)

	if [ -s $tmp_file ]; then
		echo -e "\nInstalling packages in function: $_function" "[$_file:$_line]" >>$log_file
		echo -e "\nIncoming list:" >>$log_file
		printf "%-30s %-30s %-30s %-30s\n" $list >>$log_file
		echo "" >>$log_file

		cat $tmp_file >>$log_file
	fi

	if [ -n "$for_install" ]; then
		if $need_autoup; then
			apt-get -q update
			apt-get -y upgrade
		fi

		apt-get install -qq -y --no-install-recommends $for_install
		echo -e "\nPackages installed:" >>$log_file
		dpkg-query -W -f '${binary:Package;-27} ${Version;-23}\n' $for_install >>$log_file
	fi

	if $need_verbose; then
		echo -e "\nstatus after installation:" >>$log_file
		dpkg-query -W -f '${binary:Package;-27} ${Version;-23} [ ${Status} ]\n' $list >>$log_file
	fi

	if $need_clean;then apt-get clean; fi

	rm $tmp_file
}

prepare_host_basic()
{
	local check_pack install_pack

	local checklist=(
		"dialog:dialog"
		"fuser:psmisc"
		"getfacl:acl"
		"uuid:uuid uuid-runtime"
		"curl:curl"
		"gpg:gnupg"
		"gawk:gawk"
	)

	for check_pack in "${checklist[@]}"; do
		if ! which ${check_pack%:*} >/dev/null; then local install_pack+=${check_pack#*:}" "; fi
	done

	if [[ -n $install_pack ]]; then
		display_alert "Installing basic packages" "$install_pack"
		sudo bash -c "apt-get -qq update && apt-get install -qq -y --no-install-recommends $install_pack"
	fi
}

prepare_host_raspi() {
	display_alert "Preparing" "host" "info"

	wait_for_package_manager

	HOSTRELEASE=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d"=" -f2)

	[[ -z $HOSTRELEASE ]] && HOSTRELEASE=$(cut -d'/' -f1 /etc/debian_version)

	if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
		sudo sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
		sudo locale-gen
	fi

	export LC_ALL="en_US.UTF-8"

	local hostdeps="$(cat "${SRC}/depends")"

  	if [[ $(dpkg --print-architecture) == amd64 ]]; then
		hostdeps+=" distcc lib32ncurses-dev lib32stdc++6 libc6-i386"
		grep -q i386 <(dpkg --print-foreign-architectures) || dpkg --add-architecture i386
	elif [[ $(dpkg --print-architecture) == arm64 ]]; then
		hostdeps+=" gcc-arm-linux-gnueabi gcc-arm-none-eabi libc6 libc6-amd64-cross qemu"
	 else
		display_alert "Please read documentation to set up proper compilation environment"
		display_alert "https://www.armbian.com/using-armbian-tools/"
		exit_with_error "Running this tool on non x86_64 build host is not supported"
  	fi

	if [[ $HOSTRELEASE =~ ^(focal|impish|hirsute|ulyana|ulyssa|bullseye|uma)$ ]]; then
		hostdeps+=" python2 python3"
		ln -fs /usr/bin/python2.7 /usr/bin/python2
		ln -fs /usr/bin/python2.7 /usr/bin/python
	else
		hostdeps+=" python libpython-dev"
	fi

	if grep -qE "(Microsoft|WSL)" /proc/version; then
		if [ -f /.dockerenv ]; then
			display_alert "Building images using Docker on WSL2 may fail" "" "wrn"
		else
			exit_with_error "Windows subsystem for Linux is not a supported build environment"
		fi
	fi

	if ! $offline; then
		display_alert "Installing build dependencies"
		install_pkg_deb "autoupdate $hostdeps"
		update-ccache-symlinks

		if [[ $SYNC_CLOCK != no ]]; then
			display_alert "Syncing clock" "host" "info"
			ntpdate -s "${NTP_SERVER:-pool.ntp.org}"
		fi
	fi

	mkdir -p "${DEST}"/{config,debug,images,patch} "${SRC}"/cache/{work,sources,hash,hash-beta,macos,toolchain,utility,rootfs} "${SRC}"/.tmp

	local freespace=$(findmnt --target "${SRC}" -n -o AVAIL -b 2>/dev/null)

	if [[ -n $freespace && $(( $freespace / 1073741824 )) -lt 10 ]]; then
		display_alert "Low free space left" "$(( $freespace / 1073741824 )) GiB" "wrn"
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read
	fi
}

prepare_host()
{
	display_alert "Preparing" "host" "info"

	if [ "$OFFLINE_WORK" == "yes" ]; then
		local offline=true
	else
		local offline=false
	fi

	wait_for_package_manager

	if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
		sudo sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
		sudo locale-gen
	fi

	export LC_ALL="en_US.UTF-8"

	local hostdeps="$(cat "${SRC}/depends")"

  	if [[ $(dpkg --print-architecture) == amd64 ]]; then
		hostdeps+=" distcc lib32ncurses-dev lib32stdc++6 libc6-i386"
		grep -q i386 <(dpkg --print-foreign-architectures) || dpkg --add-architecture i386
	elif [[ $(dpkg --print-architecture) == arm64 ]]; then
		hostdeps+=" gcc-arm-linux-gnueabi gcc-arm-none-eabi libc6 libc6-amd64-cross qemu"
	 else
		display_alert "Please read documentation to set up proper compilation environment"
		display_alert "https://www.armbian.com/using-armbian-tools/"
		exit_with_error "Running this tool on non x86_64 build host is not supported"
  	fi

	if [[ $HOSTRELEASE =~ ^(focal|impish|hirsute|ulyana|ulyssa|bullseye|uma)$ ]]; then
		hostdeps+=" python2 python3"
		ln -fs /usr/bin/python2.7 /usr/bin/python2
		ln -fs /usr/bin/python2.7 /usr/bin/python
	else
		hostdeps+=" python libpython-dev"
	fi

	display_alert "Build host OS release" "${HOSTRELEASE:-(unknown)}" "info"

	if [[ -z $HOSTRELEASE || "buster bullseye focal impish hirsute debbie tricia ulyana ulyssa uma" != *"$HOSTRELEASE"* ]]; then
		if [[ $NO_HOST_RELEASE_CHECK == yes ]]; then
			display_alert "You are running on an unsupported system" "${HOSTRELEASE:-(unknown)}" "wrn"
			display_alert "Do not report any errors, warnings or other issues encountered beyond this point" "" "wrn"
		else
			exit_with_error "It seems you ignore documentation and run an unsupported build system: ${HOSTRELEASE:-(unknown)}"
		fi
	fi

	if grep -qE "(Microsoft|WSL)" /proc/version; then
		if [ -f /.dockerenv ]; then
			display_alert "Building images using Docker on WSL2 may fail" "" "wrn"
		else
			exit_with_error "Windows subsystem for Linux is not a supported build environment"
		fi
	fi

	if systemd-detect-virt -q -c; then
		display_alert "Running in container" "$(systemd-detect-virt)" "info"

		if [[ $NO_APT_CACHER != no ]]; then
			display_alert "apt-cacher is disabled in containers, set NO_APT_CACHER=no to override" "" "wrn"
			NO_APT_CACHER=yes
		fi

		CONTAINER_COMPAT=yes

		if [[ $EXTERNAL_NEW == compile ]]; then
			display_alert "EXTERNAL_NEW=compile is not available when running in container, setting to prebuilt" "" "wrn"
			EXTERNAL_NEW=prebuilt
		fi

		SYNC_CLOCK=no
	fi

	if ! $offline; then
		if [[ $NO_APT_CACHER != yes ]]; then hostdeps+=" apt-cacher-ng"; fi

		export EXTRA_BUILD_DEPS=""

		call_extension_method "add_host_dependencies" <<- 'ADD_HOST_DEPENDENCIES'
	*run before installing host dependencies*
	you can add packages to install, space separated, to ${EXTRA_BUILD_DEPS} here.
	ADD_HOST_DEPENDENCIES

		if [ -n "${EXTRA_BUILD_DEPS}" ]; then hostdeps+=" ${EXTRA_BUILD_DEPS}"; fi

		display_alert "Installing build dependencies"

		sudo echo "apt-cacher-ng    apt-cacher-ng/tunnelenable      boolean false" | sudo debconf-set-selections

		LOG_OUTPUT_FILE="${DEST}"/${LOG_SUBPATH}/hostdeps.log
		install_pkg_deb "autoupdate $hostdeps"

		unset LOG_OUTPUT_FILE

		update-ccache-symlinks

		export FINAL_HOST_DEPS="$hostdeps ${EXTRA_BUILD_DEPS}"

		call_extension_method "host_dependencies_ready" <<- 'HOST_DEPENDENCIES_READY'
	*run after all host dependencies are installed*
	At this point we can read `${FINAL_HOST_DEPS}`, but changing won't have any effect.
	All the dependencies, including the default/core deps and the ones added via `${EXTRA_BUILD_DEPS}`
	are installed at this point. The system clock has not yet been synced.
	HOST_DEPENDENCIES_READY

		if [[ $SYNC_CLOCK != no ]]; then
			display_alert "Syncing clock" "host" "info"
			ntpdate -s "${NTP_SERVER:-pool.ntp.org}"
		fi

		mkdir -p "${SRC}"/{cache,output} "${USERPATCHES_PATH}"

		if [[ -n $SUDO_USER ]]; then
			chgrp --quiet sudo cache output "${USERPATCHES_PATH}"
			chmod --quiet g+w,g+s output "${USERPATCHES_PATH}"
			find "${SRC}"/output "${USERPATCHES_PATH}" -type d ! -group sudo -exec chgrp --quiet sudo {} \;
			find "${SRC}"/output "${USERPATCHES_PATH}" -type d ! -perm -g+w,g+s -exec chmod --quiet g+w,g+s {} \;
		fi

		mkdir -p "${DEST}"/debs-beta/extra "${DEST}"/debs/extra "${DEST}"/{config,debug,images,patch} "${USERPATCHES_PATH}"/overlay "${SRC}"/cache/{work,sources,hash,hash-beta,macos,toolchain,utility,rootfs} "${SRC}"/.tmp

		if [[ $(dpkg --print-architecture) == amd64 ]]; then
			if [[ "${SKIP_EXTERNAL_TOOLCHAINS}" != "yes" ]]; then
				if [[ -d "${ARMBIAN_CACHE_TOOLCHAIN_PATH}" ]]; then
					mountpoint -q "${SRC}"/cache/toolchain && umount -l "${SRC}"/cache/toolchain
					mount --bind "${ARMBIAN_CACHE_TOOLCHAIN_PATH}" "${SRC}"/cache/toolchain
				fi

				display_alert "Checking for external GCC compilers" "" "info"

				local toolchains=(
					"${ARMBIAN_MIRROR}/_toolchain/gcc-linaro-aarch64-none-elf-4.8-2013.11_linux.tar.xz"
					"${ARMBIAN_MIRROR}/_toolchain/gcc-linaro-arm-none-eabi-4.8-2014.04_linux.tar.xz"
					"${ARMBIAN_MIRROR}/_toolchain/gcc-linaro-arm-linux-gnueabihf-4.8-2014.04_linux.tar.xz"
					"${ARMBIAN_MIRROR}/_toolchain/gcc-linaro-7.4.1-2019.02-x86_64_arm-linux-gnueabi.tar.xz"
					"${ARMBIAN_MIRROR}/_toolchain/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz"
					"${ARMBIAN_MIRROR}/_toolchains/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz"
					"${ARMBIAN_MIRROR}/_toolchains/gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu.tar.xz"
					"${ARMBIAN_MIRROR}/_toolchain/gcc-arm-9.2-2019.12-x86_64-arm-none-linux-gnueabihf.tar.xz"
					"${ARMBIAN_MIRROR}/_toolchain/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz"
				)

				USE_TORRENT_STATUS=${USE_TORRENT}
				USE_TORRENT="no"

				for toolchain in ${toolchains[@]}; do
					download_and_verify "_toolchain" "${toolchain##*/}"
				done

				USE_TORRENT=${USE_TORRENT_STATUS}

				rm -rf "${SRC}"/cache/toolchain/*.tar.xz*

				local existing_dirs=( $(ls -1 "${SRC}"/cache/toolchain) )

				for dir in ${existing_dirs[@]}; do
					local found=no

					for toolchain in ${toolchains[@]}; do
						local filename=${toolchain##*/}
						local dirname=${filename//.tar.xz}

						[[ $dir == $dirname ]] && found=yes
					done

					if [[ $found == no ]]; then
						display_alert "Removing obsolete toolchain" "$dir"
						rm -rf "${SRC}/cache/toolchain/${dir}"
					fi
				done
			else
				display_alert "Ignoring toolchains" "SKIP_EXTERNAL_TOOLCHAINS: ${SKIP_EXTERNAL_TOOLCHAINS}" "info"
			fi
		fi
	fi

	modprobe -q binfmt_misc
	mountpoint -q /proc/sys/fs/binfmt_misc/ || mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc

	if [[ "$(arch)" != "aarch64" ]]; then
		test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
		test -e /proc/sys/fs/binfmt_misc/qemu-aarch64 || update-binfmts --enable qemu-aarch64
	fi

	if [[ ! -f "${USERPATCHES_PATH}"/README ]]; then
		rm -f "${USERPATCHES_PATH}"/readme.txt

		echo 'Please read documentation about customizing build configuration' > "${USERPATCHES_PATH}"/README
		echo 'https://www.armbian.com/using-armbian-tools/' >> "${USERPATCHES_PATH}"/README

		find "${SRC}"/patch -maxdepth 2 -type d ! -name . | sed "s%/.*patch%/$USERPATCHES_PATH%" | xargs mkdir -p
	fi

	local freespace=$(findmnt --target "${SRC}" -n -o AVAIL -b 2>/dev/null)

	if [[ -n $freespace && $(( $freespace / 1073741824 )) -lt 10 ]]; then
		display_alert "Low free space left" "$(( $freespace / 1073741824 )) GiB" "wrn"
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read
	fi
}

function webseed ()
{
	unset text

	local CCODE=$(curl -s redirect.armbian.com/geoip | jq '.continent.code' -r)

	WEBSEED=($(curl -s https://redirect.armbian.com/mirrors | jq -r '.'${CCODE}' | .[] | values'))

	if [[ $DOWNLOAD_MIRROR == china ]]; then
		WEBSEED=(
		https://mirrors.tuna.tsinghua.edu.cn/armbian-releases/
		)
	elif [[ $DOWNLOAD_MIRROR == bfsu ]]; then
		WEBSEED=(
		https://mirrors.bfsu.edu.cn/armbian-releases/
		)
	fi

	for toolchain in ${WEBSEED[@]}; do
		text="${text} ${toolchain}${1}"
	done

	text="${text:1}"
	echo "${text}"
}

download_and_verify()
{
	local remotedir=$1
	local filename=$2
	local localdir=$SRC/cache/${remotedir//_}
	local dirname=${filename//.tar.xz}

	if [[ $DOWNLOAD_MIRROR == china ]]; then
		local server="https://mirrors.tuna.tsinghua.edu.cn/armbian-releases/"
	elif [[ $DOWNLOAD_MIRROR == bfsu ]]; then
		local server="https://mirrors.bfsu.edu.cn/armbian-releases/"
	else
		local server=${ARMBIAN_MIRROR}
	fi

	if [[ -f ${localdir}/${dirname}/.download-complete ]]; then
		return
	fi

	timeout 10 curl --head --fail --silent ${server}${remotedir}/${filename} 2>&1 >/dev/null

	if [[ $? -ne 7 && $? -ne 22 && $? -ne 0 ]]; then
		display_alert "Timeout from $server" "retrying" "info"
		server="https://mirrors.tuna.tsinghua.edu.cn/armbian-releases/"
		timeout 10 curl --head --fail --silent ${server}${remotedir}/${filename} 2>&1 >/dev/null

		if [[ $? -ne 7 && $? -ne 22 && $? -ne 0 ]]; then
			display_alert "Timeout from $server" "retrying" "info"
			server="https://mirrors.bfsu.edu.cn/armbian-releases/"
		fi
	fi

	[[ ! `timeout 10 curl --head --fail --silent ${server}${remotedir}/${filename}` ]] && return

	cd "${localdir}" || exit

	if [[ -f "${SRC}"/config/torrents/${filename}.asc ]]; then
		local torrent="${SRC}"/config/torrents/${filename}.torrent

		ln -sf "${SRC}/config/torrents/${filename}.asc" "${localdir}/${filename}.asc"
	elif [[ ! `timeout 10 curl --head --fail --silent "${server}${remotedir}/${filename}.asc"` ]]; then
		return
	else
		local torrent=${server}$remotedir/${filename}.torrent

		aria2c --download-result=hide --disable-ipv6=true --summary-interval=0 --console-log-level=error --auto-file-renaming=false \
		--continue=false --allow-overwrite=true --dir="${localdir}" ${server}${remotedir}/${filename}.asc $(webseed "$remotedir/${filename}.asc") -o "${filename}.asc"
		[[ $? -ne 0 ]] && display_alert "Failed to download control file" "" "wrn"
	fi

	if [[ ${USE_TORRENT} == "yes" ]]; then
		display_alert "downloading using torrent network" "$filename"

		local ariatorrent="--summary-interval=0 --auto-save-interval=0 --seed-time=0 --bt-stop-timeout=120 --console-log-level=error \
		--allow-overwrite=true --download-result=hide --rpc-save-upload-metadata=false --auto-file-renaming=false \
		--file-allocation=trunc --continue=true ${torrent} \
		--dht-file-path=${SRC}/cache/.aria2/dht.dat --disable-ipv6=true --stderr --follow-torrent=mem --dir=$localdir"

		if [[ -f "${SRC}"/cache/.aria2/dht.dat ]]; then
			aria2c ${ariatorrent}
		else
			# shellcheck disable=SC2035
			aria2c ${ariatorrent} &> "${DEST}"/${LOG_SUBPATH}/torrent.log
		fi

		[[ $? -eq 0 ]] && touch "${localdir}/${filename}.complete"
	fi

	if [[ ! -f "${localdir}/${filename}.complete" ]]; then
		if [[ ! `timeout 10 curl --head --fail --silent ${server}${remotedir}/${filename} 2>&1 >/dev/null` ]]; then
			display_alert "downloading using http(s) network" "$filename"

			aria2c --download-result=hide --rpc-save-upload-metadata=false --console-log-level=error \
			--dht-file-path="${SRC}"/cache/.aria2/dht.dat --disable-ipv6=true --summary-interval=0 --auto-file-renaming=false --dir="${localdir}" ${server}${remotedir}/${filename} $(webseed "${remotedir}/${filename}") -o "${filename}"

			[[ $? -eq 0 ]] && touch "${localdir}/${filename}.complete" && echo ""

		fi
	fi

	if [[ -f ${localdir}/${filename}.asc ]]; then
		if grep -q 'BEGIN PGP SIGNATURE' "${localdir}/${filename}.asc"; then
			if [[ ! -d "${SRC}"/cache/.gpg ]]; then
				mkdir -p "${SRC}"/cache/.gpg
				chmod 700 "${SRC}"/cache/.gpg
				touch "${SRC}"/cache/.gpg/gpg.conf
				chmod 600 "${SRC}"/cache/.gpg/gpg.conf
			fi

			if [ x"" != x"${http_proxy}" ]; then
				(gpg --homedir "${SRC}"/cache/.gpg --no-permission-warning --list-keys 8F427EAF >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1\
				 || gpg --homedir "${SRC}"/cache/.gpg --no-permission-warning \
				--keyserver hkp://keyserver.ubuntu.com:80 --keyserver-options http-proxy="${http_proxy}" \
				--recv-keys 8F427EAF >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1)

				(gpg --homedir "${SRC}"/cache/.gpg --no-permission-warning --list-keys 9F0E78D5 >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1\
				|| gpg --homedir "${SRC}"/cache/.gpg --no-permission-warning \
				--keyserver hkp://keyserver.ubuntu.com:80 --keyserver-options http-proxy="${http_proxy}" \
				--recv-keys 9F0E78D5 >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1)
			else
				(gpg --homedir "${SRC}"/cache/.gpg --no-permission-warning --list-keys 8F427EAF >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1\
				 || gpg --homedir "${SRC}"/cache/.gpg --no-permission-warning \
				--keyserver hkp://keyserver.ubuntu.com:80 \
				--recv-keys 8F427EAF >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1)

				(gpg --homedir "${SRC}"/cache/.gpg --no-permission-warning --list-keys 9F0E78D5 >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1\
				|| gpg --homedir "${SRC}"/cache/.gpg --no-permission-warning \
				--keyserver hkp://keyserver.ubuntu.com:80 \
				--recv-keys 9F0E78D5 >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1)
			fi

			gpg --homedir "${SRC}"/cache/.gpg --no-permission-warning --verify \
			--trust-model always -q "${localdir}/${filename}.asc" >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1

			[[ ${PIPESTATUS[0]} -eq 0 ]] && verified=true && display_alert "Verified" "PGP" "info"
		else
			md5sum -c --status "${localdir}/${filename}.asc" && verified=true && display_alert "Verified" "MD5" "info"
		fi

		if [[ $verified == true ]]; then
			if [[ "${filename:(-6)}" == "tar.xz" ]]; then
				display_alert "decompressing"
				pv -p -b -r -c -N "[ .... ] ${filename}" "${filename}" | xz -dc | tar xp --xattrs --no-same-owner --overwrite

				[[ $? -eq 0 ]] && touch "${localdir}/${dirname}/.download-complete"
			fi
		else
			exit_with_error "verification failed"
		fi
	fi
}

show_developer_warning()
{
	local warn_text="You are switching to the \Z1EXPERT MODE\Zn

	This allows building experimental configurations that are provided
	\Z1AS IS\Zn to developers and expert users,
	\Z1WITHOUT ANY RESPONSIBILITIES\Zn from the Armbian team:

	- You are using these configurations \Z1AT YOUR OWN RISK\Zn
	- Bug reports related to the dev kernel, CSC, WIP and EOS boards
	\Z1will be closed without a discussion\Zn
	- Forum posts related to dev kernel, CSC, WIP and EOS boards
	should be created in the \Z2\"Community forums\"\Zn section
	"

	DIALOGRC="${SRC}/config/dialog.conf" dialog --keep-tite --title "Expert mode warning" --backtitle "${BACKTITLE}" --colors --defaultno --no-label "I do not agree" --yes-label "I understand and agree" --yesno "$warn_text" 50 150

	[[ $? -ne 0 ]] && exit_with_error "Error switching to the expert mode"

	SHOW_WARNING=no
}

show_checklist_variables ()
{
	local checklist=$*
	local var pval
	local log_file=${LOG_OUTPUT_FILE:-"${SRC}"/output/${LOG_SUBPATH}/trash.log}
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _file=$(basename "${BASH_SOURCE[1]}")

	echo -e "Show variables in function: $_function" "[$_file:$_line]\n" >>$log_file

	for var in $checklist;do
		eval pval=\$$var
		echo -e "\n$var =:" >>$log_file

		if [ $(echo "$pval" | awk -F"/" '{print NF}') -ge 4 ];then
			printf "%s\n" $pval >>$log_file
		else
			printf "%-30s %-30s %-30s %-30s\n" $pval >>$log_file
		fi
	done
}
