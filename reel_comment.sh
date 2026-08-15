#!/usr/bin/env bash
#
# reel_comment.sh - 投稿に来たコメントに公開返信する
#
# reel_dm.sh が DM（private reply）を送るのに対し、こちらはコメント欄への返信。
# POST /{comment-id}/replies で、相手のコメントにぶら下がる形で公開される。
#
# API にできないことが2つある。どう頑張っても無理なので、アプリで手動になる。
#
#   1. コメントに「いいね」を付ける — endpoint が存在しない
#   2. 投稿に「いいね」した人の一覧を取る — like_count という数しか取れない
#
# トークンと IG ユーザー ID は reel_post.sh と同じ .env を使う。ただしコメント操作には
# instagram_manage_comments が要る（check で確認できる）。.env が無くても、環境変数に
# WAKU_IG_USER_ID 等が直接入っていれば動く。Claude Code の Routine（クラウド実行）は
# .env をクローンしてこないので、そちらは環境変数で渡す。
#
# 「未返信」の判定は台帳ではなく API 側で行う。コメントに自分のアカウントからの
# 返信が付いているかを見る。クラウド実行は毎回まっさらな環境なので、ローカルの
# 台帳だけに頼ると同じコメントに二度返してしまう。台帳（.comment_replied/）は
# 送信直後の二重実行を防ぐ保険として併用する。

set -euo pipefail

GRAPH_HOST="${REEL_GRAPH_HOST:-graph.facebook.com}"
GRAPH_VERSION="${REEL_GRAPH_VERSION:-v21.0}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REEL_ENV_FILE:-$REPO_ROOT/.env}"

# 返信済みのコメントIDを残す場所。同じコメントに二度返さないための保険。
LOG_DIR="${REEL_COMMENT_LOG_DIR:-$REPO_ROOT/.comment_replied}"

# 行の区切り。reel_dm.sh と同じ理由で US を使う（空のフィールドで列がずれるため）。
SEP=$'\037'

JQ="$(command -v jq || true)"
PY="$(command -v python3 || true)"

die() {
	printf 'reel_comment: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOS'
使い方:
  reel_comment.sh check <account>               コメント返信ができる状態か確かめる
  reel_comment.sh new <account> [投稿件数]      直近の投稿から未返信コメントを出す（既定10投稿）
  reel_comment.sh reply <account> <comment-id> <本文>
                                                コメントに公開返信する（1コメント1回）

例:
  reel_comment.sh check waku
  reel_comment.sh new waku
  reel_comment.sh reply waku 17912345678 "ほんまありがとう、また聞いてや"

new は「自分のコメント」「既に自分の返信が付いているコメント」を除いて出す。
いいねは API からは付けられない。返信したらアプリを開いて手動で押すこと。
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

# data[] から指定フィールドを SEP 区切りで1行ずつ出す。$1=JSON $2...=フィールド名。
# オブジェクトの値（replies など）は JSON 文字列のまま出る。
# 値の中の改行・タブ・区切り文字は空白に潰す。潰さないと1件が複数行に割れて行が壊れる。
json_rows() {
	local body="$1"
	shift
	if [ -n "$JQ" ]; then
		local expr='' field path
		for field in "$@"; do
			path="$(printf '%s' "$field" | sed 's/\.\([0-9][0-9]*\)/[\1]/g')"
			expr="$expr${expr:+ + \"\\u001f\" + }(.$path // \"\" | tostring | gsub(\"[\\n\\r\\t\\u001f]\"; \" \"))"
		done
		printf '%s' "$body" | "$JQ" -r ".data[]? | $expr"
	else
		REEL_JSON="$body" "$PY" -c '
import json, os, sys
try:
    rows = json.loads(os.environ["REEL_JSON"]).get("data") or []
except ValueError:
    sys.exit(0)
for row in rows:
    out = []
    for path in sys.argv[1:]:
        value = row
        for key in path.split("."):
            if isinstance(value, dict):
                value = value.get(key)
            elif isinstance(value, list) and key.isdigit() and int(key) < len(value):
                value = value[int(key)]
            else:
                value = None
            if value is None:
                break
        if value is None:
            value = ""
        elif not isinstance(value, str):
            value = json.dumps(value, ensure_ascii=False)
        for bad in ("\n", "\r", "\t", "\x1f"):
            value = value.replace(bad, " ")
        out.append(value)
    print("\x1f".join(out))
' "$@"
	fi
}

print_error() {
	local body="$1" context="$2" field value
	printf 'reel_comment: %s に失敗\n' "$context" >&2
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

# .env があれば読む。無くても環境変数に直接入っていれば account_value が拾うので
# ここでは落とさない（reel_dm.sh との違い。Routine 環境には .env が無い）。
load_env() {
	if [ -f "$ENV_FILE" ]; then
		set -a
		# shellcheck disable=SC1090
		. "$ENV_FILE"
		set +a
	fi
}

account_prefix() {
	printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'
}

account_value() {
	local account="$1" suffix="$2" var value
	var="$(account_prefix "$account")_$suffix"
	value="${!var-}"
	if [ -z "$value" ]; then
		die "$var が無い。.env に書くか、環境変数で渡すこと。"
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
	curl -sS --max-time 60 -X POST "https://$GRAPH_HOST/$GRAPH_VERSION/$path" "$@"
}

need_account() {
	[ -n "${1:-}" ] || die 'アカウント名が指定されていない'
	require_tools
	load_env
}

own_username() {
	local id="$1" token="$2" body
	body="$(graph_get "$id" --data-urlencode "fields=username" --data-urlencode "access_token=$token")"
	fail_on_error "$body" '自分のユーザー名の取得'
	json_get "$body" username
}

# replies の JSON 塊に自分のユーザー名があるか。jq と python で空白の入り方が
# 違うので、空白を落としてから比べる（IG のユーザー名に空白は入らない）。
replied_by_me() {
	local replies_json="$1" me="$2"
	[ -n "$replies_json" ] || return 1
	printf '%s' "$replies_json" | tr -d ' ' | grep -qF "\"username\":\"$me\""
}

sent_log() {
	printf '%s/%s.log' "$LOG_DIR" "$1"
}

already_sent() {
	local log
	log="$(sent_log "$1")"
	[ -f "$log" ] && cut -f1 "$log" | grep -qxF "$2"
}

record_sent() {
	local log
	log="$(sent_log "$1")"
	mkdir -p "$LOG_DIR"
	printf '%s\t%s\t%s\n' "$2" "$3" "$(date +%Y-%m-%dT%H:%M:%S%z)" >>"$log"
}

cmd_check() {
	local account="${1:-}"
	need_account "$account"

	local id token body username
	id="$(account_value "$account" IG_USER_ID)"
	token="$(account_value "$account" ACCESS_TOKEN)"

	body="$(graph_get "$id" --data-urlencode "fields=id,username" --data-urlencode "access_token=$token")"
	if has_error "$body"; then
		print_error "$body" "$account への接続確認"
		printf '\n投稿の時点で通っていない。まず reel_post.sh check %s を見ること。\n' "$account" >&2
		exit 1
	fi
	username="$(json_get "$body" username)"
	printf '接続OK: %s → @%s (%s)\n' "$account" "$username" "$id"

	# 権限は投稿用とは別物。投稿が通っていてもコメント操作は落ちる。
	local perms scopes missing=0
	perms="$(graph_get me/permissions --data-urlencode "access_token=$token")"
	if has_error "$perms"; then
		printf '権限一覧は取れなかった（Instagram ログイン方式では出ない）\n' >&2
	else
		scopes="$(json_rows "$perms" permission status | awk -F"$SEP" '$2 == "granted" { print $1 }')"
		if printf '%s\n' "$scopes" | grep -qxF instagram_manage_comments; then
			printf '権限OK: instagram_manage_comments\n'
		else
			printf '権限が足りない: instagram_manage_comments\n' >&2
			missing=1
		fi
	fi

	# 権限が付いていても実際に叩けるかは別。投稿を1件だけ引いて確かめる。
	body="$(graph_get "$id/media" \
		--data-urlencode "fields=id" \
		--data-urlencode "limit=1" \
		--data-urlencode "access_token=$token")"
	if has_error "$body"; then
		print_error "$body" '投稿一覧の確認'
		missing=1
	else
		printf 'コメント返信の準備OK: 投稿一覧を読めている\n'
	fi

	if [ "$missing" -ne 0 ]; then
		cat >&2 <<EOS

コメント返信は使えない状態。Graph API Explorer でトークンを取り直すこと。
そのとき投稿用の権限に加えて instagram_manage_comments にチェックを入れる。
取り直したら .env に書いて ./reel_post.sh refresh $account で60日に延長する。
EOS
		exit 1
	fi
}

cmd_new() {
	local account="${1:-}" media_limit="${2:-10}"
	need_account "$account"

	local id token me
	id="$(account_value "$account" IG_USER_ID)"
	token="$(account_value "$account" ACCESS_TOKEN)"
	me="$(own_username "$id" "$token")"

	local media_body
	media_body="$(graph_get "$id/media" \
		--data-urlencode "fields=id,permalink,timestamp" \
		--data-urlencode "limit=$media_limit" \
		--data-urlencode "access_token=$token")"
	fail_on_error "$media_body" '投稿一覧の取得'

	local total=0 media_id permalink media_ts
	while IFS="$SEP" read -r media_id permalink media_ts; do
		[ -n "$media_id" ] || continue

		local comments_body
		comments_body="$(graph_get "$media_id/comments" \
			--data-urlencode "fields=id,username,text,timestamp,replies{username}" \
			--data-urlencode "limit=100" \
			--data-urlencode "access_token=$token")"
		if has_error "$comments_body"; then
			print_error "$comments_body" "投稿 $media_id のコメント取得"
			continue
		fi

		local header_shown=0 comment_id username text timestamp replies
		while IFS="$SEP" read -r comment_id username text timestamp replies; do
			[ -n "$comment_id" ] || continue
			[ "$username" = "$me" ] && continue
			already_sent "$account" "$comment_id" && continue
			replied_by_me "$replies" "$me" && continue
			if [ "$header_shown" -eq 0 ]; then
				printf '=== 投稿 %s  %s\n' "$media_id" "$permalink"
				header_shown=1
			fi
			printf '%s  @%-20s %s\n' "$comment_id" "$username" "$timestamp"
			printf '  %s\n' "$text"
			total=$((total + 1))
		done < <(json_rows "$comments_body" id username text timestamp replies)
	done < <(json_rows "$media_body" id permalink timestamp)

	printf '未返信 %d 件（自分のコメントと返信済みは除外）\n' "$total" >&2
}

cmd_reply() {
	local account="${1:-}" comment_id="${2:-}" text="${3:-}"
	[ -n "$comment_id" ] || die 'comment-id が指定されていない（reel_comment.sh new で拾える）'
	[ -n "$text" ] || die '本文が指定されていない'
	need_account "$account"

	local token
	token="$(account_value "$account" ACCESS_TOKEN)"

	if already_sent "$account" "$comment_id"; then
		die "そのコメントには既に返信している: $comment_id"
	fi

	local body
	body="$(graph_post "$comment_id/replies" \
		--data-urlencode "message=$text" \
		--data-urlencode "access_token=$token")"
	if has_error "$body"; then
		print_error "$body" "コメント $comment_id への返信"
		printf '  返信できるのは自分の投稿の最上位コメントだけ。返信への返信はできない。\n' >&2
		exit 1
	fi

	record_sent "$account" "$comment_id" ''
	printf '返信: %s\n' "$(json_get "$body" id)"
	printf 'いいねは API から付けられない。アプリを開いて手動で押すこと。\n' >&2
}

main() {
	local cmd="${1:-}"
	shift || true
	case "$cmd" in
	check) cmd_check "$@" ;;
	new) cmd_new "$@" ;;
	reply) cmd_reply "$@" ;;
	-h | --help | help | '') usage ;;
	*)
		usage >&2
		die "知らないコマンド: $cmd"
		;;
	esac
}

main "$@"
