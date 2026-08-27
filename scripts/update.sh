#!/usr/bin/env bash
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

readonly CDN_URL="https://static.ampcode.com/cli"
readonly SYSTEMS=(
	"x86_64-linux linux-x64-baseline"
	"aarch64-linux linux-arm64"
	"x86_64-darwin darwin-x64"
	"aarch64-darwin darwin-arm64"
)

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

get_current_version() {
	sed -n 's/.*version = "\([^"]*\)".*/\1/p' package.nix | head -1
}

get_latest_version() {
	local version
	version=$(curl -fsSL "$CDN_URL/cli-version.txt" || true)
	if [ -z "$version" ]; then
		log_error "Failed to fetch latest version from $CDN_URL/cli-version.txt"
		exit 2
	fi
	printf '%s\n' "$version"
}

set_version() {
	local version="$1"
	local temp_file
	temp_file=$(mktemp)
	sed -E "s/version = \"[^\"]+\"/version = \"$version\"/" package.nix >"$temp_file"
	mv "$temp_file" package.nix
}

set_system_hash() {
	local system="$1"
	local hash="$2"
	local temp_file
	temp_file=$(mktemp)
	sed -E "s|(${system} = \")sha256-[^\"]+(\")|\1${hash}\2|" package.nix >"$temp_file"
	mv "$temp_file" package.nix
}

tarball_url() {
	local version="$1"
	local platform="$2"
	printf '%s/%s/amp-%s.gz\n' "$CDN_URL" "$version" "$platform"
}

prefetch_hash() {
	local url="$1"
	nix store prefetch-file --json "$url" 2>/dev/null | jq -r .hash
}

rollback_package() {
	local backup_dir="$1"
	cp "$backup_dir/package.nix" package.nix
	rm -rf "$backup_dir"
}

update_to_version() {
	local new_version="$1"
	local backup_dir
	backup_dir=$(mktemp -d)
	cp package.nix "$backup_dir"
	trap 'rollback_package "$backup_dir"' ERR
	trap 'rollback_package "$backup_dir"; exit 130' INT
	trap 'rollback_package "$backup_dir"; exit 143' TERM

	log_info "Updating amp-cli to version $new_version..."
	set_version "$new_version"

	local entry system platform url hash
	for entry in "${SYSTEMS[@]}"; do
		system="${entry%% *}"
		platform="${entry##* }"
		url=$(tarball_url "$new_version" "$platform")
		log_info "Prefetching $platform..."
		hash=$(prefetch_hash "$url")
		if [ -z "$hash" ] || [ "$hash" = "null" ]; then
			log_error "Failed to prefetch $url"
			return 1
		fi
		log_info "  $system: $hash"
		set_system_hash "$system" "$hash"
	done

	if command -v nixfmt >/dev/null 2>&1; then
		nixfmt package.nix || true
	elif command -v nixfmt-rfc-style >/dev/null 2>&1; then
		nixfmt-rfc-style package.nix || true
	fi

	log_info "Verifying build..."
	local output_path
	output_path=$(nix build .#amp-cli --no-link --print-out-paths --print-build-logs)
	"$output_path/bin/amp" --version

	rm -rf "$backup_dir"
	trap - ERR INT TERM
	log_info "Successfully updated amp-cli to $new_version"
}

ensure_in_repository_root() {
	if [ ! -f flake.nix ] || [ ! -f package.nix ]; then
		log_error "flake.nix or package.nix not found. Run this script from the repository root."
		exit 2
	fi
}

ensure_required_tools_installed() {
	for tool in nix curl jq; do
		command -v "$tool" >/dev/null 2>&1 || {
			log_error "$tool is required but not installed."
			exit 2
		}
	done
}

print_usage() {
	cat <<'USAGE'
Usage: scripts/update.sh [OPTIONS]

Options:
  --version VERSION  Update to a specific Amp version
  --check            Only check for updates; exits 1 when an update is available
  --help             Show this help message

Examples:
  scripts/update.sh
  scripts/update.sh --check
  scripts/update.sh --version 0.0.1787810366-g2503d7
USAGE
}

parse_arguments() {
	local target_version=""
	local check_only=false

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--version)
			target_version="${2:-}"
			if [ -z "$target_version" ]; then
				log_error "--version requires a value"
				exit 2
			fi
			shift 2
			;;
		--check)
			check_only=true
			shift
			;;
		--help)
			print_usage
			exit 0
			;;
		*)
			log_error "Unknown option: $1"
			print_usage
			exit 2
			;;
		esac
	done

	printf '%s|%s\n' "$target_version" "$check_only"
}

main() {
	ensure_in_repository_root
	ensure_required_tools_installed

	local args
	args=$(parse_arguments "$@")
	local target_version="${args%%|*}"
	local check_only="${args#*|}"
	local current_version
	current_version=$(get_current_version)
	local latest_version="$target_version"

	if [ -z "$latest_version" ]; then
		latest_version=$(get_latest_version)
	fi

	log_info "Current version: $current_version"
	log_info "Latest version: $latest_version"

	if [ "$current_version" = "$latest_version" ]; then
		log_info "Already up to date!"
		exit 0
	fi

	if [ "$check_only" = true ]; then
		log_info "Update available: $current_version → $latest_version"
		exit 1
	fi

	update_to_version "$latest_version"
	git diff --stat package.nix 2>/dev/null || true
}

main "$@"
