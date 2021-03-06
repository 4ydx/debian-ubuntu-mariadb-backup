#!/bin/bash

export LC_ALL=C

backup_owner="backup"
log_file="extract-progress.log"
number_of_args="${#}"
password_file="/etc/mysql/password.txt"
processors="$(nproc --all)"

# Use this to echo to standard error
error () {
	printf "%s: %s\n" "$(basename "${BASH_SOURCE}")" "${1}" >&2
	exit 1
}

trap 'error "An unexpected error occurred.  Try checking the \"${log_file}\" file for more information."' ERR

sanity_check () {
	# Check user running the script
	if [ "${USER}" != "${backup_owner}" ]; then
		error "Script can only be run as the \"${backup_owner}\" user"
	fi

	# Check whether any arguments were passed
	if [ "${number_of_args}" -lt 1 ]; then
		error "Script requires at least one \".xbstream\" file as an argument."
	fi

	# Check whether the encryption password file is available
	if [ ! -r "${password_file}" ]; then
		error "Cannot read password file at ${password_file}"
	fi
}

do_extraction () {
	for file in "${@}"; do
		base_filename="$(basename "${file%.xbstream}")"
		restore_dir="./restore/${base_filename}"

		printf "\n\nExtracting file %s\n\n" "${file}"

		# Extract the directory structure from the backup file
		mkdir --verbose -p "${restore_dir}"

		openssl  enc -d -aes-256-cbc -pass file:{$password_file} -in "{$file}" | gzip -d | mbstream -x -C "{$restore_dir}"

		find "${restore_dir}" -name "*.qp" -exec rm {} \;

		printf "\n\nFinished work on %s\n\n" "${file}"

	done > "${log_file}" 2>&1
}

sanity_check && do_extraction "$@"

ok_count="$(grep -c 'completed OK' "${log_file}")"

# Check the number of reported completions.  For each file, there is an
# informational "completed OK".  If the processing was successful, an
# additional "completed OK" is printed. Together, this means there should be 2
# notices per backup file if the process was successful.
if (( $ok_count !=  2 * $# )); then
	error "It looks like something went wrong. Please check the \"${log_file}\" file for additional information"
else
	printf "Extraction complete! Backup directories have been extracted to the \"restore\" directory.\n"
fi
