function fetch_sources_tools__sunxi_tools() {
	fetch_from_repo "https://github.com/linux-sunxi/sunxi-tools" "sunxi-tools" "branch:master"
}

function build_host_tools__compile_sunxi_tools() {
	cd "${SRC}"/cache/sources/sunxi-tools || exit

	if [[ ! -f .commit_id || $(improved_git rev-parse @ 2>/dev/null) != $(<.commit_id) || ! -f /usr/local/bin/sunxi-fexc ]]; then
		display_alert "Compiling" "sunxi-tools" "info"
		make -s clean >/dev/null
		make -s tools >/dev/null
		mkdir -p /usr/local/bin/
		make install-tools >/dev/null 2>&1
		improved_git rev-parse @ 2>/dev/null >.commit_id
	fi
}
