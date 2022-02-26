declare -A extension_function_info
declare -i initialize_extension_manager_counter=0
declare -A defined_hook_point_functions
declare -A hook_point_function_trace_sources
declare -A hook_point_function_trace_lines
declare fragment_manager_cleanup_file

export DEBUG_EXTENSION_CALLS=no
export LOG_ENABLE_EXTENSION=yes

call_extension_method() {
	write_hook_point_metadata "$@" || true

	if [[ ${initialize_extension_manager_counter} -lt 1 ]]; then
		display_alert "Extension problem" "Call to call_extension_method() (in ${BASH_SOURCE[1]- $(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")}) before extension manager is initialized." "err"
	fi

	[[ "${DEBUG_EXTENSION_CALLS}" == "yes" ]] && display_alert "--> Extension Method '${1}' being called from" "$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")" ""

	for hook_name in "$@"; do
		echo "-- Extension Method being called: ${hook_name}" >>"${EXTENSION_MANAGER_LOG_FILE}"

		[[ $(type -t ${hook_name}) == function ]] && { ${hook_name}; }
	done
}

initialize_extension_manager() {
	[[ ${initialize_extension_manager_counter} -lt 1 ]] && [[ "${ENABLE_EXTENSIONS}" != "" ]] && {
		local auto_extension
		for auto_extension in $(echo "${ENABLE_EXTENSIONS}" | tr "," " "); do
			ENABLE_EXTENSION_TRACE_HINT="ENABLE_EXTENSIONS -> " enable_extension "${auto_extension}"
		done
	}

	export initialize_extension_manager_counter=$((initialize_extension_manager_counter + 1))
	export EXTENSION_MANAGER_TMP_DIR="${SRC}/.tmp/.extensions/${LOG_SUBPATH}"

	mkdir -p "${EXTENSION_MANAGER_TMP_DIR}"

	export EXTENSION_MANAGER_LOG_FILE="${EXTENSION_MANAGER_TMP_DIR}/extensions.log"

	echo -n "" >"${EXTENSION_MANAGER_TMP_DIR}/hook_point_calls.txt"
	echo "-- lib/extensions.sh included. logs will be below, followed by the debug generated by the initialize_extension_manager() function." >"${EXTENSION_MANAGER_LOG_FILE}"
	echo "-- initialize_extension_manager() called." >>"${EXTENSION_MANAGER_LOG_FILE}"

	local hook_extension_delimiter="__"
	local all_hook_points

	all_hook_points="$(compgen -A 'function' | grep "${hook_extension_delimiter}" | awk -F "${hook_extension_delimiter}" '{print $1}' | sort | uniq | xargs echo -n)"

	declare -i hook_points_counter=0 hook_functions_counter=0 hook_point_functions_counter=0

	fragment_manager_cleanup_file="${SRC}"/.tmp/extension_function_cleanup.sh

	echo "# cleanups: " >"${fragment_manager_cleanup_file}"

	local FUNCTION_SORT_OPTIONS="--general-numeric-sort --ignore-case" #  --random-sort could be used to introduce chaos
	local hook_point=""

	for hook_point in ${all_hook_points}; do
		echo "-- hook_point ${hook_point}" >> "${EXTENSION_MANAGER_LOG_FILE}"

		local existing_hook_point_function

		existing_hook_point_function="$(compgen -A 'function' | grep "^${hook_point}\$")"

		if [[ "${existing_hook_point_function}" == "${hook_point}" ]]; then
			echo "--- hook_point_functions (final sorted realnames): ${hook_point_functions}" >>"${EXTENSION_MANAGER_LOG_FILE}"

			display_alert "Extension conflict" "function ${hook_point} already defined! ignoring functions: $(compgen -A 'function' | grep "^${hook_point}${hook_extension_delimiter}")" "wrn"

			continue
		fi

		local hook_point_functions hook_point_functions_pre_sort hook_point_functions_sorted_by_sort_id

		hook_point_functions_pre_sort="$(compgen -A 'function' | grep "^${hook_point}${hook_extension_delimiter}" | awk -F "${hook_extension_delimiter}" '{print $2}' | xargs echo -n)"

		echo "--- hook_point_functions_pre_sort: ${hook_point_functions_pre_sort}" >>"${EXTENSION_MANAGER_LOG_FILE}"

		declare -A hook_point_functions_sortname_to_realname
		declare -A hook_point_functions_realname_to_sortname

		for hook_point_function_realname in ${hook_point_functions_pre_sort}; do
			local sort_id="${hook_point_function_realname}"

			[[ ! $sort_id =~ ^[0-9] ]] && sort_id="500_${sort_id}"

			hook_point_functions_sortname_to_realname[${sort_id}]="${hook_point_function_realname}"
			hook_point_functions_realname_to_sortname[${hook_point_function_realname}]="${sort_id}"
		done

		hook_point_functions_sorted_by_sort_id="$(echo "${hook_point_functions_realname_to_sortname[*]}" | tr " " "\n" | LC_ALL=C sort ${FUNCTION_SORT_OPTIONS} | xargs echo -n)"

		echo "--- hook_point_functions_sorted_by_sort_id: ${hook_point_functions_sorted_by_sort_id}" >>"${EXTENSION_MANAGER_LOG_FILE}"

		hook_point_functions=""

		for hook_point_function_sortname in ${hook_point_functions_sorted_by_sort_id}; do
			hook_point_functions="${hook_point_functions} ${hook_point_functions_sortname_to_realname[${hook_point_function_sortname}]}"
		done

		hook_point_functions="$(echo -n ${hook_point_functions})"

		echo "--- hook_point_functions (final sorted realnames): ${hook_point_functions}" >>"${EXTENSION_MANAGER_LOG_FILE}"

		hook_point_functions_counter=0
		hook_points_counter=$((hook_points_counter + 1))

		local common_function_vars="HOOK_POINT=\"${hook_point}\""

		for hook_point_function in ${hook_point_functions}; do
			hook_point_functions_counter=$((hook_point_functions_counter + 1))
			hook_functions_counter=$((hook_functions_counter + 1))
		done

		common_function_vars="${common_function_vars} HOOK_POINT_TOTAL_FUNCS=\"${hook_point_functions_counter}\""

		echo "-- hook_point: ${hook_point} will run ${hook_point_functions_counter} functions: ${hook_point_functions}" >>"${EXTENSION_MANAGER_LOG_FILE}"

		local temp_source_file_for_hook_point="${EXTENSION_MANAGER_TMP_DIR}/extension_function_definition.sh"

		hook_point_functions_loop_counter=0

		cat <<-FUNCTION_CLEANUP_FOR_HOOK_POINT >>"${fragment_manager_cleanup_file}"
			unset ${hook_point}
		FUNCTION_CLEANUP_FOR_HOOK_POINT

		cat <<-FUNCTION_DEFINITION_HEADER >"${temp_source_file_for_hook_point}"
			${hook_point}() {
				echo "*** Extension-managed hook starting '${hook_point}': will run ${hook_point_functions_counter} functions: '${hook_point_functions}'" >>"\${EXTENSION_MANAGER_LOG_FILE}"
		FUNCTION_DEFINITION_HEADER

		for hook_point_function in ${hook_point_functions}; do
			hook_point_functions_loop_counter=$((hook_point_functions_loop_counter + 1))

			defined_hook_point_functions["${hook_point}${hook_extension_delimiter}${hook_point_function}"]="DEFINED=yes ${extension_function_info["${hook_point}${hook_extension_delimiter}${hook_point_function}"]}"

			local hook_point_function_variables="${common_function_vars}" # start with common vars... (eg: HOOK_POINT_TOTAL_FUNCS)

			hook_point_function_variables="${hook_point_function_variables} ${extension_function_info["${hook_point}${hook_extension_delimiter}${hook_point_function}"]}"
			hook_point_function_variables="${hook_point_function_variables} HOOK_ORDER=\"${hook_point_functions_loop_counter}\""

			eval "${hook_point_function_variables}"

			cat <<-FUNCTION_DEFINITION_CALLSITE >>"${temp_source_file_for_hook_point}"
				hook_point_function_trace_sources["${hook_point}${hook_extension_delimiter}${hook_point_function}"]="\${BASH_SOURCE[*]}"
				hook_point_function_trace_lines["${hook_point}${hook_extension_delimiter}${hook_point_function}"]="\${BASH_LINENO[*]}"
				[[ "\${DEBUG_EXTENSION_CALLS}" == "yes" ]] && display_alert "---> Extension Method ${hook_point}" "${hook_point_functions_loop_counter}/${hook_point_functions_counter} (ext:${EXTENSION:-built-in}) ${hook_point_function}" ""
				echo "*** *** Extension-managed hook starting ${hook_point_functions_loop_counter}/${hook_point_functions_counter} '${hook_point}${hook_extension_delimiter}${hook_point_function}':" >>"\${EXTENSION_MANAGER_LOG_FILE}"
				${hook_point_function_variables} ${hook_point}${hook_extension_delimiter}${hook_point_function} "\$@"
				echo "*** *** Extension-managed hook finished ${hook_point_functions_loop_counter}/${hook_point_functions_counter} '${hook_point}${hook_extension_delimiter}${hook_point_function}':" >>"\${EXTENSION_MANAGER_LOG_FILE}"
			FUNCTION_DEFINITION_CALLSITE

			cat <<-FUNCTION_CLEANUP_FOR_HOOK_POINT_IMPLEMENTATION >>"${fragment_manager_cleanup_file}"
				unset ${hook_point}${hook_extension_delimiter}${hook_point_function}
			FUNCTION_CLEANUP_FOR_HOOK_POINT_IMPLEMENTATION

			unset EXTENSION EXTENSION_DIR EXTENSION_FILE EXTENSION_ADDED_BY
		done

		cat <<-FUNCTION_DEFINITION_FOOTER >>"${temp_source_file_for_hook_point}"
			echo "*** Extension-managed hook ending '${hook_point}': completed." >>"\${EXTENSION_MANAGER_LOG_FILE}"
			} # end ${hook_point}() function
		FUNCTION_DEFINITION_FOOTER

		unset hook_point_functions hook_point_functions_sortname_to_realname hook_point_functions_realname_to_sortname

		cat "${temp_source_file_for_hook_point}" >>"${EXTENSION_MANAGER_LOG_FILE}"
		cat "${fragment_manager_cleanup_file}" >>"${EXTENSION_MANAGER_LOG_FILE}"

		source "${temp_source_file_for_hook_point}"

		rm -f "${temp_source_file_for_hook_point}"
	done

	[[ ${hook_functions_counter} -gt 0 ]] && display_alert "Extension manager" "processed ${hook_points_counter} Extension Methods calls and ${hook_functions_counter} Extension Method implementations" "info" | tee -a "${EXTENSION_MANAGER_LOG_FILE}"
}

cleanup_extension_manager() {
	if [[ -f "${fragment_manager_cleanup_file}" ]]; then
		display_alert "Cleaning up" "extension manager" "info"

		source "${fragment_manager_cleanup_file}"
	fi

	initialize_extension_manager_counter=0

	unset extension_function_info defined_hook_point_functions hook_point_function_trace_sources hook_point_function_trace_lines fragment_manager_cleanup_file
}

run_after_build__999_finish_extension_manager() {
	export defined_hook_point_functions hook_point_function_trace_sources

	call_extension_method "extension_metadata_ready" <<'EXTENSION_METADATA_READY'
*meta-Meta time!*
Implement this hook to work with/on the meta-data made available by the extension manager.
Interesting stuff to process:
- `"${EXTENSION_MANAGER_TMP_DIR}/hook_point_calls.txt"` contains a list of all hook points called, in order.
- For each hook_point in the list, more files will have metadata about that hook point.
  - `${EXTENSION_MANAGER_TMP_DIR}/hook_point.orig.md` contains the hook documentation at the call site (inline docs), hopefully in Markdown format.
  - `${EXTENSION_MANAGER_TMP_DIR}/hook_point.compat` contains the compatibility names for the hooks.
  - `${EXTENSION_MANAGER_TMP_DIR}/hook_point.exports` contains _exported_ environment variables.
  - `${EXTENSION_MANAGER_TMP_DIR}/hook_point.vars` contains _all_ environment variables.
- `${defined_hook_point_functions}` is a map of _all_ the defined hook point functions and their extension information.
- `${hook_point_function_trace_sources}` is a map of all the hook point functions _that were really called during the build_ and their BASH_SOURCE information.
- `${hook_point_function_trace_lines}` is the same, but BASH_LINENO info.
After this hook is done, the `${EXTENSION_MANAGER_TMP_DIR}` will be removed.
EXTENSION_METADATA_READY

	mv "${EXTENSION_MANAGER_LOG_FILE}" "${DEST}/${LOG_SUBPATH:-debug}/extensions.log"

	export EXTENSION_MANAGER_LOG_FILE="${DEST}/${LOG_SUBPATH:-debug}/extensions.log"

	[[ -d "${EXTENSION_MANAGER_TMP_DIR}" ]] && rm -rf "${EXTENSION_MANAGER_TMP_DIR}"
}

write_hook_point_metadata() {
	local main_hook_point_name="$1"

	[[ ! -d "${EXTENSION_MANAGER_TMP_DIR}" ]] && mkdir -p "${EXTENSION_MANAGER_TMP_DIR}"

	cat - >"${EXTENSION_MANAGER_TMP_DIR}/${main_hook_point_name}.orig.md"

	shift

	echo -n "$@" >"${EXTENSION_MANAGER_TMP_DIR}/${main_hook_point_name}.compat"

	compgen -A export >"${EXTENSION_MANAGER_TMP_DIR}/${main_hook_point_name}.exports"
	compgen -A variable >"${EXTENSION_MANAGER_TMP_DIR}/${main_hook_point_name}.vars"

	echo "${main_hook_point_name}" >>"${EXTENSION_MANAGER_TMP_DIR}/hook_point_calls.txt"
}

get_extension_hook_stracktrace() {
	local sources_str="$1" # Give this ${BASH_SOURCE[*]} - expanded
	local lines_str="$2"   # And this # Give this ${BASH_LINENO[*]} - expanded
	local sources lines index final_stack=""

	IFS=' ' read -r -a sources <<<"${sources_str}"
	IFS=' ' read -r -a lines <<<"${lines_str}"

	for index in "${!sources[@]}"; do
		local source="${sources[index]}" line="${lines[((index - 1))]}"

		[[ ${source} == */.tmp/extension_function_definition.sh ]] && continue
		[[ ${source} == *lib/extensions.sh ]] && continue
		[[ ${source} == */compile ]] && continue

		source="${source#"${SRC}/"}"
		source="${source#"lib/"}"

		arrow="$([[ "$final_stack" != "" ]] && echo "-> ")"
		final_stack="${source}:${line} ${arrow} ${final_stack} "
	done

	echo -n $final_stack
}

show_caller_full() {
	local frame=0

	while caller $frame; do
		((frame++))
	done
}

declare -i enable_extension_recurse_counter=0
declare -a enable_extension_recurse_stack

enable_extension() {
	local extension_name="$1"
	local extension_dir extension_file extension_file_in_dir extension_floating_file
	local stacktrace

	stacktrace="${ENABLE_EXTENSION_TRACE_HINT}$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"

	[[ "${LOG_ENABLE_EXTENSION}" == "yes" ]] && display_alert "Extension being added" "${extension_name} :: added by ${stacktrace}" ""

	if [[ ${initialize_extension_manager_counter} -gt 0 ]]; then
		display_alert "Extension problem" "already initialized -- too late to add '${extension_name}' (trace: ${stacktrace})" "err"

		exit 2
	fi

	if [[ $enable_extension_recurse_counter -gt 1 ]]; then
		enable_extension_recurse_stack+=("${extension_name}")

		return 0
	fi

	enable_extension_recurse_counter=$((enable_extension_recurse_counter + 1))

	for extension_base_path in "${SRC}/userpatches/extensions" "${SRC}/extensions"; do
		extension_dir="${extension_base_path}/${extension_name}"
		extension_file_in_dir="${extension_dir}/${extension_name}.sh"
		extension_floating_file="${extension_base_path}/${extension_name}.sh"

		if [[ -d "${extension_dir}" ]] && [[ -f "${extension_file_in_dir}" ]]; then
			extension_file="${extension_file_in_dir}"

			break
		elif [[ -f "${extension_floating_file}" ]]; then
			extension_dir="${extension_base_path}"
			extension_file="${extension_floating_file}"

			break
		fi
	done

	if [[ ! -f "${extension_file}" ]]; then
		echo "ERR: Extension problem -- cant find extension '${extension_name}' anywhere - called by ${BASH_SOURCE[1]}"

		exit 17
	fi

	local before_function_list after_function_list new_function_list

	before_function_list="$(compgen -A function)"

	declare -i extension_source_generated_error=0

	trap 'extension_source_generated_error=1;' ERR
	source "${extension_file}"
	trap - ERR

	enable_extension_recurse_counter=$((enable_extension_recurse_counter - 1))

	if [[ $extension_source_generated_error != 0 ]]; then
		display_alert "Extension failed to load" "${extension_file}" "err"

		exit 4
	fi

	after_function_list="$(compgen -A function)"
	new_function_list="$(comm -13 <(echo "$before_function_list" | sort) <(echo "$after_function_list" | sort))"

	for newly_defined_function in ${new_function_list}; do
		extension_function_info["${newly_defined_function}"]="EXTENSION=\"${extension_name}\" EXTENSION_DIR=\"${extension_dir}\" EXTENSION_FILE=\"${extension_file}\" EXTENSION_ADDED_BY=\"${stacktrace}\""
	done

	local -a stack_snapshot=("${enable_extension_recurse_stack[@]}")

	enable_extension_recurse_stack=()

	for stacked_extension in "${stack_snapshot[@]}"; do
		ENABLE_EXTENSION_TRACE_HINT="RECURSE ${stacktrace} ->" enable_extension "${stacked_extension}"
	done
}