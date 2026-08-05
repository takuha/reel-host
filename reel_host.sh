#!/usr/bin/env bash
#
# reel_host.sh - リール動画の一時ホスティング操作
#
# Meta Graph API は動画を「公開URLから取得」する方式なので、投稿前に動画を
# どこかに公開しておく必要がある。このスクリプトは GitHub Pages に動画を載せて
# 公開URLを発行し、投稿が済んだら消すところまでを担当する。
#
# Graph API を叩いて実際に投稿する処理はこのリポジトリの範囲外。

set -euo pipefail

BASE_URL="${REEL_HOST_BASE_URL:-https://takuha.github.io/reel-host}"
BRANCH="${REEL_HOST_BRANCH:-main}"
VIDEO_DIR="videos"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# GitHub Pages はプッシュ直後には配信が始まらない。404 のまま Graph API に
# URL を渡すと投稿が失敗するので、実際に配信されるまで待ってから URL を出す。
WAIT_TRIES="${REEL_HOST_WAIT_TRIES:-30}"
WAIT_INTERVAL="${REEL_HOST_WAIT_INTERVAL:-5}"

die() {
	printf 'reel_host: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOS'
使い方:
  reel_host.sh add <account> <video-file>  動画を公開して URL を出す
  reel_host.sh url <account> <name>        公開 URL を組み立てて出す
  reel_host.sh list [account]              ホスティング中の動画を出す
  reel_host.sh clean [account]             投稿済み動画を消す（省略時は全アカウント）

アカウントごとに videos/<account>/ に分けて置く。例:
  reel_host.sh add aoyagi ~/Movies/reel001.mp4
EOS
}

# アカウント名はそのまま URL パスになるので、安全な文字だけ通す。
validate_account() {
	case "${1:-}" in
	'') die 'アカウント名が指定されていない' ;;
	*[!A-Za-z0-9._-]*) die "アカウント名に使えるのは英数字と . _ - だけ: $1" ;;
	esac
}

safe_name() {
	printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

require_branch() {
	local current
	current="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
	[ "$current" = "$BRANCH" ] ||
		die "$BRANCH ブランチで実行すること（今は $current）。GitHub Pages は $BRANCH から配信される。"
}

push_change() {
	local message="$1"
	git -C "$REPO_ROOT" commit -q -m "$message"
	git -C "$REPO_ROOT" push -q origin "$BRANCH"
}

wait_until_live() {
	local url="$1" i
	for ((i = 1; i <= WAIT_TRIES; i++)); do
		if curl -fsI --max-time 10 "$url" >/dev/null 2>&1; then
			return 0
		fi
		sleep "$WAIT_INTERVAL"
	done
	return 1
}

cmd_add() {
	local account="${1:-}" src="${2:-}"
	validate_account "$account"
	[ -n "$src" ] || die '動画ファイルが指定されていない'
	[ -f "$src" ] || die "ファイルが見つからない: $src"

	require_branch

	local name dest
	name="$(safe_name "$(basename "$src")")"
	dest="$VIDEO_DIR/$account/$name"

	mkdir -p "$REPO_ROOT/$VIDEO_DIR/$account"
	cp "$src" "$REPO_ROOT/$dest"

	git -C "$REPO_ROOT" add -- "$dest"
	if git -C "$REPO_ROOT" diff --cached --quiet; then
		printf '同じ内容が既に公開済み\n' >&2
	else
		push_change "host: $account/$name を公開"
	fi

	local url="$BASE_URL/$dest"
	if wait_until_live "$url"; then
		printf '%s\n' "$url"
	else
		die "公開されない（$((WAIT_TRIES * WAIT_INTERVAL))秒待った）: $url
GitHub Pages が有効か、$BRANCH から配信されているか確認すること。"
	fi
}

cmd_url() {
	local account="${1:-}" name="${2:-}"
	validate_account "$account"
	[ -n "$name" ] || die 'ファイル名が指定されていない'
	printf '%s\n' "$BASE_URL/$VIDEO_DIR/$account/$(safe_name "$name")"
}

cmd_list() {
	local account="${1:-}" target="$REPO_ROOT/$VIDEO_DIR"
	if [ -n "$account" ]; then
		validate_account "$account"
		target="$target/$account"
	fi
	[ -d "$target" ] || return 0
	find "$target" -type f -print | sed "s#^$REPO_ROOT/##" | sort
}

cmd_clean() {
	local account="${1:-}" target="$VIDEO_DIR"
	if [ -n "$account" ]; then
		validate_account "$account"
		target="$VIDEO_DIR/$account"
	fi

	require_branch

	[ -d "$REPO_ROOT/$target" ] || {
		printf '消すものが無い\n' >&2
		return 0
	}

	git -C "$REPO_ROOT" rm -rq --ignore-unmatch -- "$target"
	rm -rf "${REPO_ROOT:?}/$target"

	if git -C "$REPO_ROOT" diff --cached --quiet; then
		printf '消すものが無い\n' >&2
	else
		push_change "host: ${account:-全アカウント} の公開済み動画を削除"
	fi
}

main() {
	local command="${1:-}"
	[ $# -gt 0 ] && shift

	case "$command" in
	add) cmd_add "$@" ;;
	url) cmd_url "$@" ;;
	list) cmd_list "$@" ;;
	clean) cmd_clean "$@" ;;
	'' | -h | --help | help) usage ;;
	*) die "知らないコマンド: $command（reel_host.sh --help）" ;;
	esac
}

main "$@"
