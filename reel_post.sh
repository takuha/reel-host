#!/usr/bin/env bash
#
# reel_post.sh - Meta Graph API でリールを投稿する
#
# 投稿は3段階に分かれる。
#   1. コンテナ作成  POST /{ig-user-id}/media       … 動画URLを渡す
#   2. 変換待ち      GET  /{container-id}           … status_code が FINISHED になるまで
#   3. 公開          POST /{ig-user-id}/media_publish
#
# トークンと IG ユーザー ID はアカウントごとに別物なので .env で分けて持つ。
# .env は .gitignore 済み。git には絶対に乗せない。

set -euo pipefail

GRAPH_HOST="${REEL_GRAPH_HOST:-graph.facebook.com}"
GRAPH_VERSION="${REEL_GRAPH_VERSION:-v21.0}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REEL_ENV_FILE:-$REPO_ROOT/.env}"

# リールの変換は数十秒〜数分かかる。終わる前に公開すると失敗する。
POLL_TRIES="${REEL_POLL_TRIES:-60}"
POLL_INTERVAL="${REEL_POLL_INTERVAL:-5}"

JQ="$(command -v jq || true)"
PY="$(command -v python3 || true)"

die() {
	printf 'reel_post: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOS'
使い方:
  reel_post.sh accounts                       .env に設定済みのアカウントを出す
  reel_post.sh check <account>                トークンがそのアカウントに通るか確かめる
  reel_post.sh post <account> <url> [caption] 公開済みURLの動画を投稿する
  reel_post.sh publish <account> <file> [caption]
                                              ホスティングから投稿まで一気にやる

例:
  reel_post.sh check aoyagi
  reel_post.sh publish aoyagi ~/Movies/reel001.mp4 "今日の一本"

つながらないときは check から。エラーの原因がそのまま出る。
EOS
}

require_tools() {
	command -v curl >/dev/null || die 'curl が無い'
	[ -n "$JQ" ] || [ -n "$PY" ] || die 'jq か python3 のどちらかが必要（brew install jq）'
}

# JSON から値を1つ取り出す。$1=JSON本体 $2=ドット区切りのキー。無ければ空文字。
json_get() {
	local body="$1" path="$2"
	if [ -n "$JQ" ]; then
		printf '%s' "$body" | "$JQ" -r ".${path} // empty"
	else
		REEL_JSON="$body" "$PY" -c '
import json, os, sys
try:
    data = json.loads(os.environ["REEL_JSON"])
except ValueError:
    sys.exit(0)
for key in sys.argv[1].split("."):
    if not isinstance(data, dict) or key not in data:
        sys.exit(0)
    data = data[key]
print(data if isinstance(data, (str, int, float)) else json.dumps(data))
' "$path"
	fi
}

# Meta のエラーはこの形で返る。原因の切り分けに必要な情報を全部出す。
print_error() {
	local body="$1" context="$2" field value
	printf 'reel_post: %s に失敗\n' "$context" >&2
	for field in message type code error_subcode error_user_msg; do
		value="$(json_get "$body" "error.$field")"
		if [ -n "$value" ]; then
			printf '  %-16s %s\n' "$field" "$value" >&2
		fi
	done
}

has_error() {
	[ -n "$(json_get "$1" error.message)" ]
}

fail_on_error() {
	if has_error "$1"; then
		print_error "$1" "$2"
		exit 1
	fi
}

load_env() {
	[ -f "$ENV_FILE" ] || die "$ENV_FILE が無い。.env.example をコピーして値を入れること。"
	# set -a で、読み込んだ変数を子プロセスと env から見える形にする。
	set -a
	# shellcheck disable=SC1090
	. "$ENV_FILE"
	set +a
}

account_prefix() {
	printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'
}

# アカウント名から <PREFIX>_IG_USER_ID / <PREFIX>_ACCESS_TOKEN を引く。
account_value() {
	local account="$1" suffix="$2" var value
	var="$(account_prefix "$account")_$suffix"
	value="${!var-}"
	if [ -z "$value" ]; then
		die "$var が .env に無い。reel_post.sh accounts で設定済みのアカウントを確認。"
	fi
	printf '%s' "$value"
}

graph_get() {
	local path="$1"
	shift
	curl -sS --max-time 60 -G "https://$GRAPH_HOST/$GRAPH_VERSION/$path" "$@"
}

graph_post() {
	local path="$1"
	shift
	curl -sS --max-time 600 -X POST "https://$GRAPH_HOST/$GRAPH_VERSION/$path" "$@"
}

cmd_accounts() {
	[ -f "$ENV_FILE" ] || die "$ENV_FILE が無い。.env.example をコピーして値を入れること。"
	# env 全体ではなく .env だけを見る。環境に元からある無関係な
	# *_ACCESS_TOKEN（クラウドSDK等）を拾わないため。
	local found
	found="$(sed -n 's/^[[:space:]]*\([A-Z0-9_]*\)_ACCESS_TOKEN[[:space:]]*=..*/\1/p' "$ENV_FILE" |
		tr '[:upper:]' '[:lower:]' | sort -u)"
	if [ -z "$found" ]; then
		die "$ENV_FILE にトークンが1つも入っていない"
	fi
	printf '%s\n' "$found"
}

cmd_check() {
	local account="${1:-}"
	[ -n "$account" ] || die 'アカウント名が指定されていない'
	require_tools
	load_env

	local id token body username
	id="$(account_value "$account" IG_USER_ID)"
	token="$(account_value "$account" ACCESS_TOKEN)"

	body="$(graph_get "$id" --data-urlencode "fields=id,username" --data-urlencode "access_token=$token")"

	if ! has_error "$body"; then
		username="$(json_get "$body" username)"
		printf '接続OK: %s → @%s (%s)\n' "$account" "$username" "$id"
		return 0
	fi

	print_error "$body" "$account への接続確認"

	# トークンが「どのアカウントに通るのか」が分かれば原因はほぼ確定する。
	# 一覧に目的のアカウントが出てこない＝そのトークンでは投稿できない。
	printf '\nこのトークンで使えるアカウント:\n' >&2
	local pages
	pages="$(graph_get me/accounts \
		--data-urlencode "fields=name,instagram_business_account{id,username}" \
		--data-urlencode "access_token=$token")"
	if has_error "$pages"; then
		printf '  一覧も取得できない（トークン自体が無効か期限切れの可能性）\n' >&2
	elif [ -n "$JQ" ]; then
		printf '%s' "$pages" |
			"$JQ" -r '.data[]? | "  \(.name): @\(.instagram_business_account.username // "IG未連携") \(.instagram_business_account.id // "")"' >&2
	else
		printf '%s\n' "$pages" >&2
	fi
	exit 1
}

# コンテナが FINISHED になるまで待つ。ERROR なら理由を出して止める。
wait_for_container() {
	local container="$1" token="$2" i body status detail
	for ((i = 1; i <= POLL_TRIES; i++)); do
		body="$(graph_get "$container" \
			--data-urlencode "fields=status_code,status" \
			--data-urlencode "access_token=$token")"
		fail_on_error "$body" 'コンテナの状態確認'

		status="$(json_get "$body" status_code)"
		case "$status" in
		FINISHED) return 0 ;;
		ERROR | EXPIRED)
			detail="$(json_get "$body" status)"
			printf 'reel_post: 動画の変換に失敗（%s）\n  %s\n' "$status" "$detail" >&2
			printf '  動画URLに Meta から到達できているか、形式がリール対応か確認すること。\n' >&2
			exit 1
			;;
		esac
		sleep "$POLL_INTERVAL"
	done
	die "変換が終わらない（$((POLL_TRIES * POLL_INTERVAL))秒待った）"
}

cmd_post() {
	local account="${1:-}" video_url="${2:-}" caption="${3:-}"
	[ -n "$account" ] || die 'アカウント名が指定されていない'
	[ -n "$video_url" ] || die '動画URLが指定されていない'
	require_tools
	load_env

	local id token body container media_id
	id="$(account_value "$account" IG_USER_ID)"
	token="$(account_value "$account" ACCESS_TOKEN)"

	printf 'コンテナ作成中...\n' >&2
	local args=(
		--data-urlencode "media_type=REELS"
		--data-urlencode "video_url=$video_url"
		--data-urlencode "access_token=$token"
	)
	if [ -n "$caption" ]; then
		args+=(--data-urlencode "caption=$caption")
	fi

	body="$(graph_post "$id/media" "${args[@]}")"
	fail_on_error "$body" 'コンテナ作成'
	container="$(json_get "$body" id)"
	[ -n "$container" ] || die "コンテナIDが返ってこない: $body"

	printf '変換待ち (%s)...\n' "$container" >&2
	wait_for_container "$container" "$token"

	printf '公開中...\n' >&2
	body="$(graph_post "$id/media_publish" \
		--data-urlencode "creation_id=$container" \
		--data-urlencode "access_token=$token")"
	fail_on_error "$body" '公開'

	media_id="$(json_get "$body" id)"
	printf '投稿完了: %s\n' "$media_id"
}

cmd_publish() {
	local account="${1:-}" file="${2:-}" caption="${3:-}"
	[ -n "$account" ] || die 'アカウント名が指定されていない'
	[ -n "$file" ] || die '動画ファイルが指定されていない'
	[ -f "$file" ] || die "ファイルが見つからない: $file"

	local url
	url="$("$REPO_ROOT/reel_host.sh" add "$account" "$file")"
	printf '公開URL: %s\n' "$url" >&2

	cmd_post "$account" "$url" "$caption"

	# 投稿が通った分だけ消す。まだ投稿していない動画は残す。
	"$REPO_ROOT/reel_host.sh" clean "$account" "$(basename "$file")"
}

main() {
	local command="${1:-}"
	[ $# -gt 0 ] && shift

	case "$command" in
	accounts) cmd_accounts "$@" ;;
	check) cmd_check "$@" ;;
	post) cmd_post "$@" ;;
	publish) cmd_publish "$@" ;;
	'' | -h | --help | help) usage ;;
	*) die "知らないコマンド: $command（reel_post.sh --help）" ;;
	esac
}

main "$@"
