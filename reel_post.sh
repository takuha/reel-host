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

# Instagram の本文の上限。超えたぶんは切られるのではなく投稿ごと弾かれる。
CAPTION_LIMIT="${REEL_CAPTION_LIMIT:-2200}"

# --caption-file で渡された本文ファイル。resolve_caption が $CAPTION に展開する。
CAPTION_FILE="${REEL_CAPTION_FILE:-}"
CAPTION=""

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
  reel_post.sh refresh <account>              トークンを長期（60日）に延長して .env を更新
  reel_post.sh post <account> <url> [caption] 公開済みURLの動画を投稿する
  reel_post.sh publish <account> <file|url> [caption]
                                              ホスティングから投稿まで一気にやる
  reel_post.sh next <account> [caption]      キューの先頭を投稿して消す

オプション:
  -f, --caption-file <file>  本文をファイルから読む（引数での指定とは併用できない）

例:
  reel_post.sh check aoyagi
  reel_post.sh publish aoyagi ~/Movies/reel001.mp4 "今日の一本"
  reel_post.sh publish aoyagi https://vt.tiktok.com/XXXXXXXX/ "今日の一本"
  reel_post.sh next aoyagi "今日の一本"
  reel_post.sh publish aoyagi ~/Movies/reel001.mp4 -f captions/doge-mining-payments.txt

`next` は videos/<account>/ に既に置いてある（`reel_host.sh add` 済みの）動画から
ファイル名順で先頭の1本を投稿する。投稿順を決めたいときは、ファイル名にゼロ埋めの
連番を付けておく（01_, 02_, ...）。

改行の多い長文はシェルの引用符で壊れやすい。captions/ にファイルで置いて
--caption-file で渡すこと。

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

# 本文の長さは「文字数」で数える必要がある。日本語はバイト数だと3倍に出るので、
# ${#var} や wc -c では上限判定にならない。
caption_length() {
	local caption="$1"
	if [ -n "$PY" ]; then
		REEL_CAPTION="$caption" "$PY" -c 'import os; print(len(os.environ["REEL_CAPTION"]))'
	elif [ -n "$JQ" ]; then
		printf '%s' "$caption" | "$JQ" -Rs 'length'
	fi
}

# 本文を確定して $CAPTION に入れる。引数で渡すか --caption-file で渡すかの
# どちらか一方。値を返さないのは、この中の die をそのまま効かせるため
# （コマンド置換の中だと exit がサブシェルで止まる）。
resolve_caption() {
	local caption="${1:-}" length

	if [ -n "$CAPTION_FILE" ]; then
		[ -z "$caption" ] || die '本文を引数と --caption-file の両方で渡している。どちらか一方にすること。'
		[ -f "$CAPTION_FILE" ] || die "本文のファイルが見つからない: $CAPTION_FILE"
		# 末尾の改行だけ落ちる。本文中の改行はそのまま Instagram の改行になる。
		caption="$(cat "$CAPTION_FILE")"
		[ -n "$caption" ] || die "本文のファイルが空: $CAPTION_FILE"
	fi

	if [ -n "$caption" ]; then
		length="$(caption_length "$caption")"
		case "$length" in
		'' | *[!0-9]*) ;;
		*)
			if [ "$length" -gt "$CAPTION_LIMIT" ]; then
				die "本文が $length 文字。Instagram の上限は $CAPTION_LIMIT 文字なので、このままでは投稿が弾かれる。"
			fi
			;;
		esac
	fi

	CAPTION="$caption"
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

# .env の1行だけ差し替える。トークンには記号が入りうるので sed は使わない。
update_env_var() {
	local var="$1" value="$2" tmp line found=0
	tmp="$(mktemp)"
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		"$var="*)
			printf '%s=%s\n' "$var" "$value"
			found=1
			;;
		*) printf '%s\n' "$line" ;;
		esac
	done <"$ENV_FILE" >"$tmp"
	if [ "$found" -eq 0 ]; then
		printf '%s=%s\n' "$var" "$value" >>"$tmp"
	fi
	cp "$ENV_FILE" "$ENV_FILE.bak"
	mv "$tmp" "$ENV_FILE"
	chmod 600 "$ENV_FILE" "$ENV_FILE.bak"
}

# 短期トークンは1時間で切れる。長期に交換しておかないと、翌日には
# また「接続できない」状態に戻る。
cmd_refresh() {
	local account="${1:-}"
	[ -n "$account" ] || die 'アカウント名が指定されていない'
	require_tools
	load_env

	local token var body new_token expires
	token="$(account_value "$account" ACCESS_TOKEN)"
	var="$(account_prefix "$account")_ACCESS_TOKEN"

	if [ "$GRAPH_HOST" = "graph.instagram.com" ]; then
		# Instagram ログイン方式。長期トークンを自分で延長できる。
		body="$(curl -sS --max-time 60 -G "https://graph.instagram.com/refresh_access_token" \
			--data-urlencode "grant_type=ig_refresh_token" \
			--data-urlencode "access_token=$token")"
	else
		# Facebook ログイン方式。アプリIDとシークレットで長期トークンに交換する。
		if [ -z "${META_APP_ID-}" ] || [ -z "${META_APP_SECRET-}" ]; then
			die 'META_APP_ID と META_APP_SECRET を .env に入れること（アプリの設定→ベーシックにある）'
		fi
		body="$(graph_get oauth/access_token \
			--data-urlencode "grant_type=fb_exchange_token" \
			--data-urlencode "client_id=$META_APP_ID" \
			--data-urlencode "client_secret=$META_APP_SECRET" \
			--data-urlencode "fb_exchange_token=$token")"
	fi

	fail_on_error "$body" 'トークンの延長'
	new_token="$(json_get "$body" access_token)"
	[ -n "$new_token" ] || die "トークンが返ってこない: $body"

	update_env_var "$var" "$new_token"

	expires="$(json_get "$body" expires_in)"
	case "$expires" in
	'' | *[!0-9]*) printf '%s のトークンを延長した（%s を更新、元は %s.bak）\n' "$account" "$ENV_FILE" "$ENV_FILE" ;;
	*) printf '%s のトークンを延長した。あと %d 日（%s を更新、元は %s.bak）\n' "$account" "$((expires / 86400))" "$ENV_FILE" "$ENV_FILE" ;;
	esac
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
	local account="${1:-}" video_url="${2:-}"
	[ -n "$account" ] || die 'アカウント名が指定されていない'
	[ -n "$video_url" ] || die '動画URLが指定されていない'
	require_tools
	resolve_caption "${3:-}"
	load_env

	do_post "$account" "$video_url" "$CAPTION"
}

do_post() {
	local account="$1" video_url="$2" caption="$3"

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
	local account="${1:-}" source="${2:-}" caption="${3:-}"
	[ -n "$account" ] || die 'アカウント名が指定されていない'
	[ -n "$source" ] || die '動画ファイルか動画URLが指定されていない'
	require_tools
	# 本文の不備はホスティングの前に落とす。上げてから落ちると、投稿していない
	# 動画がリポジトリに残ったままになる。
	resolve_caption "${3:-}"
	load_env

	# 手元のファイルでも共有URLでも add がそのまま受ける。URL のときは add が
	# 落としてから載せる。Graph API に渡せるのは自分で公開したURLだけなので、
	# TikTok のページURLをそのまま投げても通らない。
	local url
	url="$("$REPO_ROOT/reel_host.sh" add "$account" "$source")"
	printf '公開URL: %s\n' "$url" >&2

	do_post "$account" "$url" "$CAPTION"

	# 投稿が通った分だけ消す。まだ投稿していない動画は残す。公開URLの末尾が
	# そのままホスティング中のファイル名なので、元がURLでも名前を特定できる。
	"$REPO_ROOT/reel_host.sh" clean "$account" "$(basename "$url")"
}

cmd_next() {
	local account="${1:-}" caption="${2:-}"
	[ -n "$account" ] || die 'アカウント名が指定されていない'

	local name url
	name="$("$REPO_ROOT/reel_host.sh" next "$account")"
	[ -n "$name" ] || die "$account のキューに動画が無い（videos/$account/ に何も無い）"

	url="$("$REPO_ROOT/reel_host.sh" url "$account" "$name")"
	printf 'キュー先頭: %s\n' "$name" >&2

	cmd_post "$account" "$url" "$caption"
	"$REPO_ROOT/reel_host.sh" clean "$account" "$name"
}

main() {
	local command
	local -a rest
	rest=()

	# オプションはどの位置に置いてもいいように、先に抜き出してから位置引数に戻す。
	while [ $# -gt 0 ]; do
		case "$1" in
		-f | --caption-file)
			[ $# -ge 2 ] || die '--caption-file にファイルが指定されていない'
			CAPTION_FILE="$2"
			shift 2
			;;
		--caption-file=*)
			CAPTION_FILE="${1#--caption-file=}"
			shift
			;;
		*)
			rest[${#rest[@]}]="$1"
			shift
			;;
		esac
	done
	set -- ${rest[@]+"${rest[@]}"}

	command="${1:-}"
	if [ $# -gt 0 ]; then shift; fi

	case "$command" in
	accounts) cmd_accounts "$@" ;;
	check) cmd_check "$@" ;;
	refresh) cmd_refresh "$@" ;;
	post) cmd_post "$@" ;;
	publish) cmd_publish "$@" ;;
	next) cmd_next "$@" ;;
	'' | -h | --help | help) usage ;;
	*) die "知らないコマンド: $command（reel_post.sh --help）" ;;
	esac
}

main "$@"
