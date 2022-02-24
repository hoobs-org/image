export LOG_ALL_HOOK_TRACES=no

function wishful_hooking_example__this_will_never_run() {
	echo "WISHFUL HOOKING -- this will never run. I promise."
}

function extension_metadata_ready__999_detect_wishful_hooking() {
	display_alert "Checking extensions and hooks for uncalled hook points"

	declare -i found_honeypot_function=0

	for one_defined_function in ${!defined_hook_point_functions[*]}; do
		local source_info defined_info line_info

		defined_info="${defined_hook_point_functions["${one_defined_function}"]}"
		source_info="${hook_point_function_trace_sources["${one_defined_function}"]}"
		line_info="${hook_point_function_trace_lines["${one_defined_function}"]}"
		stack="$(get_extension_hook_stracktrace "${source_info}" "${line_info}")"

		if [[ "$source_info" != "" ]]; then
			echo "\$\$\$ Hook function stacktrace for '${one_defined_function}': '${stack}' (${defined_info})" >>"${EXTENSION_MANAGER_LOG_FILE}"

			if [[ "${LOG_ALL_HOOK_TRACES}" != "no" ]]; then
				display_alert "Hook function stacktrace for '${one_defined_function}'" "${stack}" "${LOG_ALL_HOOK_TRACES}"
			fi

			continue
		fi

		if [[ "${one_defined_function}" == "wishful_hooking_example__this_will_never_run" ]]; then
			found_honeypot_function=1
		else
			echo "\$\$\$ Wishful hooking detected" "Function '${one_defined_function}' is defined (${defined_info}) but never called by the build." >>"${EXTENSION_MANAGER_LOG_FILE}"

			display_alert "Wishful hooking detected" "Function '${one_defined_function}' is defined (${defined_info}) but never called by the build." "wrn"
		fi
	done

	if [[ $found_honeypot_function -lt 1 ]]; then
		display_alert "Wishful hook DETECTION FAILED" "detect-wishful-hooking is not working. Good chance the environment vars are corrupted. Avoid child shells. Sorry." "wrn" | tee -a "${EXTENSION_MANAGER_LOG_FILE}"
	fi
}
