#!/usr/bin/env bash
#
# reel_dm.sh - リールを見た人に DM を送る
#
# Instagram の DM は誰にでも送れるわけではない。API から送れるのは次の2つだけ。
#
#   1. コメントへの返信（private reply）
#      リールに来たコメント1件につき1回だけ、その相手に DM を送れる。
#      コメントから7日以内。面識のない相手に届く入口はこれしかない。
#   2. 相手から DM が届いている場合
#      相手の最後のメッセージから24時間以内なら自由に返せる。
#
# つまり「リールを出す → コメントをもらう → その人に DM」が新規 DM の唯一の順路で、
# リールを出す前に DM だけ先に送っておくことはできない。
#
# トークンと IG ユーザー ID は reel_post.sh と同じ .env を使う。ただし DM には
# 追加の権限（instagram_manage_messages / instagram_manage_comments）が要るので、
# 投稿だけできるトークンでは通らない。check で確認できる。

set -euo pipefail

GRAPH_HOST="${REEL_GRAPH_HOST:-graph.facebook.com}"
GRAPH_VERSION="${REEL_GRAPH_VERSION:-v21.0}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REEL_ENV_FILE:-$REPO_ROOT/.env}"

# 送信済みのコメントIDを残す場所。同じ人に二度送らないための台帳。
LOG_DIR="${REEL_DM_LOG_DIR:-$REPO_ROOT/.dm_sent}"

# まとめて送るときの間隔（秒）。詰めすぎるとレート制限に当たる。
SEND_INTERVAL="${REEL_DM_INTERVAL:-2}"

# 行の区切り。タブは IFS 上の空白扱いで、空のフィールドが連続すると read が
# 詰めてしまい列がずれる。空きうる列（caption や permalink）があるので US を使う。
SEP=$'\037'

JQ="$(command -v jq || true)"
PY="$(command -v python3 || true)"

die() {
	printf 'reel_dm: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOS'
使い方:
  reel_dm.sh check <account>                    DM が送れる状態か確かめる
  reel_dm.sh media <account> [件数]             直近の投稿を出す（media-id を拾う）
  reel_dm.sh comments <account> <media-id> [--match 文字列]
                                                そのリールのコメントを出す
  reel_dm.sh reply <account> <comment-id> <本文>
                                                コメント主に DM を送る（1コメント1回）
  reel_dm.sh sweep <account> <media-id> <本文> [--match 文字列] [--send]
                                                コメント主にまとめて送る（既定は下見）
  reel_dm.sh threads <account>                  DM が来ている相手を出す
  reel_dm.sh send <account> <igsid> <本文>      その相手に送る（24時間以内のみ）

例:
  reel_dm.sh check aoyagi
  reel_dm.sh media aoyagi
  reel_dm.sh sweep aoyagi 17912345 "コメントありがとう！こちらです → https://..." --match 受け取り
  reel_dm.sh sweep aoyagi 17912345 "コメントありがとう！こちらです → https://..." --match 受け取り --send

sweep は --send を付けるまで送らない。先に付けずに打って、誰に届くか確認すること。
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
# 配列は participants.data.0.username のように数字で潜れる。
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

# 本文をそのまま渡すと引用符や改行で JSON が壊れる。必ずこれを通す。
json_string() {
	if [ -n "$JQ" ]; then
		printf '%s' "$1" | "$JQ" -Rs .
	else
		REEL_TEXT="$1" "$PY" -c 'import json, os; print(json.dumps(os.environ["REEL_TEXT"], ensure_ascii=False))'
	fi
}

print_error() {
	local body="$1" context="$2" field value
	printf 'reel_dm: %s に失敗\n' "$context" >&2
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
	set -a
	# shellcheck disable=SC1090
	. "$ENV_FILE"
	set +a
}

account_prefix() {
	printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'
}

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
	curl -sS --max-time 60 -X POST "https://$GRAPH_HOST/$GRAPH_VERSION/$path" "$@"
}

need_account() {
	[ -n "${1:-}" ] || die 'アカウント名が指定されていない'
	require_tools
	load_env
}

# DM の送信本体。宛先の指定の仕方だけが private reply と通常返信で違う。
# $1=IGユーザーID $2=トークン $3=recipient のJSON $4=本文
send_message() {
	local id="$1" token="$2" recipient="$3" text="$4"
	graph_post "$id/messages" \
		--data-urlencode "recipient=$recipient" \
		--data-urlencode "message={\"text\":$(json_string "$text")}" \
		--data-urlencode "access_token=$token"
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

	# 権限は投稿用とは別物。投稿が通っていても DM は落ちる。
	local perms scopes missing=0 scope
	perms="$(graph_get me/permissions --data-urlencode "access_token=$token")"
	if has_error "$perms"; then
		printf '権限一覧は取れなかった（Instagram ログイン方式では出ない）\n' >&2
	else
		scopes="$(json_rows "$perms" permission status | awk -F"$SEP" '$2 == "granted" { print $1 }')"
		for scope in instagram_manage_messages instagram_manage_comments; do
			if printf '%s\n' "$scopes" | grep -qxF "$scope"; then
				printf '権限OK: %s\n' "$scope"
			else
				printf '権限が足りない: %s\n' "$scope" >&2
				missing=1
			fi
		done
	fi

	# 権限が付いていても実際に叩けるかは別。受信箱を1件だけ引いて確かめる。
	body="$(graph_get "$id/conversations" \
		--data-urlencode "platform=instagram" \
		--data-urlencode "limit=1" \
		--data-urlencode "access_token=$token")"
	if has_error "$body"; then
		print_error "$body" 'DM の受信箱の確認'
		missing=1
	else
		printf 'DM 送信の準備OK: 受信箱を読めている\n'
	fi

	if [ "$missing" -ne 0 ]; then
		cat >&2 <<EOS

DM は使えない状態。Graph API Explorer でトークンを取り直すこと。
そのとき投稿用の権限に加えて、次の2つにチェックを入れる。

  instagram_manage_messages    DM の送受信
  instagram_manage_comments    コメントの取得（private reply の宛先になる）

取り直したら .env に書いて ./reel_post.sh refresh $account で60日に延長する。
EOS
		exit 1
	fi
}

cmd_media() {
	local account="${1:-}" limit="${2:-10}"
	need_account "$account"

	local id token body
	id="$(account_value "$account" IG_USER_ID)"
	token="$(account_value "$account" ACCESS_TOKEN)"

	body="$(graph_get "$id/media" \
		--data-urlencode "fields=id,media_type,permalink,timestamp,caption" \
		--data-urlencode "limit=$limit" \
		--data-urlencode "access_token=$token")"
	fail_on_error "$body" '投稿一覧の取得'

	local media_id media_type permalink timestamp caption
	while IFS="$SEP" read -r media_id media_type permalink timestamp caption; do
		[ -n "$media_id" ] || continue
		printf '%s  %s  %s\n' "$media_id" "$media_type" "$timestamp"
		[ -n "$permalink" ] && printf '  %s\n' "$permalink"
		[ -n "$caption" ] && printf '  %s\n' "$caption"
	done < <(json_rows "$body" id media_type permalink timestamp caption)
}

# コメントを取得して「コメントID/ユーザー名/本文」のタブ区切りで返す。
fetch_comments() {
	local id="$1" token="$2" media="$3" match="$4" body
	body="$(graph_get "$media/comments" \
		--data-urlencode "fields=id,username,text,timestamp" \
		--data-urlencode "limit=100" \
		--data-urlencode "access_token=$token")"
	if has_error "$body"; then
		print_error "$body" 'コメントの取得'
		printf '  media-id がそのアカウントの投稿か、instagram_manage_comments が付いているか確認すること。\n' >&2
		exit 1
	fi
	if [ -n "$match" ]; then
		json_rows "$body" id username text timestamp | grep -F -- "$match" || true
	else
		json_rows "$body" id username text timestamp
	fi
}

cmd_comments() {
	local account='' media='' match='' args=()
	while [ $# -gt 0 ]; do
		case "$1" in
		--match)
			match="${2:-}"
			[ -n "$match" ] || die '--match に文字列が無い'
			shift 2
			;;
		*)
			args+=("$1")
			shift
			;;
		esac
	done
	account="${args[0]:-}"
	media="${args[1]:-}"
	[ -n "$media" ] || die 'media-id が指定されていない（reel_dm.sh media で拾える）'
	need_account "$account"

	local id token
	id="$(account_value "$account" IG_USER_ID)"
	token="$(account_value "$account" ACCESS_TOKEN)"

	# プロセス置換だと取得の失敗を拾えず「コメント0件」に見えてしまうので、先に受け取る。
	local rows
	rows="$(fetch_comments "$id" "$token" "$media" "$match")"

	local comment_id username text timestamp mark
	while IFS="$SEP" read -r comment_id username text timestamp; do
		[ -n "$comment_id" ] || continue
		mark=' '
		already_sent "$account" "$comment_id" && mark='*'
		printf '%s %s  @%-20s %s\n' "$mark" "$comment_id" "$username" "$text"
	done <<<"$rows"
	printf '（* は送信済み）\n' >&2
}

cmd_reply() {
	local account="${1:-}" comment_id="${2:-}" text="${3:-}"
	[ -n "$comment_id" ] || die 'comment-id が指定されていない'
	[ -n "$text" ] || die '本文が指定されていない'
	need_account "$account"

	local id token body
	id="$(account_value "$account" IG_USER_ID)"
	token="$(account_value "$account" ACCESS_TOKEN)"

	if already_sent "$account" "$comment_id"; then
		die "そのコメントには既に送っている: $comment_id"
	fi

	body="$(send_message "$id" "$token" "{\"comment_id\":$(json_string "$comment_id")}" "$text")"
	if has_error "$body"; then
		print_error "$body" "コメント $comment_id への DM"
		printf '  1コメントにつき送れるのは1回だけ。コメントから7日を過ぎたものにも送れない。\n' >&2
		exit 1
	fi

	record_sent "$account" "$comment_id" ''
	printf '送信: %s\n' "$(json_get "$body" message_id)"
}

cmd_sweep() {
	local account='' media='' text='' match='' do_send=0 args=()
	while [ $# -gt 0 ]; do
		case "$1" in
		--send)
			do_send=1
			shift
			;;
		--match)
			match="${2:-}"
			[ -n "$match" ] || die '--match に文字列が無い'
			shift 2
			;;
		*)
			args+=("$1")
			shift
			;;
		esac
	done
	account="${args[0]:-}"
	media="${args[1]:-}"
	text="${args[2]:-}"
	[ -n "$media" ] || die 'media-id が指定されていない（reel_dm.sh media で拾える）'
	[ -n "$text" ] || die '本文が指定されていない'
	need_account "$account"

	local id token
	id="$(account_value "$account" IG_USER_ID)"
	token="$(account_value "$account" ACCESS_TOKEN)"

	# プロセス置換だと取得の失敗を拾えず「宛先0件」に見えてしまうので、先に受け取る。
	local rows
	rows="$(fetch_comments "$id" "$token" "$media" "$match")"

	local targets=() names=() comment_id username text_body timestamp skipped=0
	while IFS="$SEP" read -r comment_id username text_body timestamp; do
		[ -n "$comment_id" ] || continue
		if already_sent "$account" "$comment_id"; then
			skipped=$((skipped + 1))
			continue
		fi
		targets+=("$comment_id")
		names+=("$username")
	done <<<"$rows"

	if [ "${#targets[@]}" -eq 0 ]; then
		printf '送る相手がいない（送信済み %d 件を除外）\n' "$skipped"
		return 0
	fi

	printf '宛先 %d 件（送信済み %d 件は除外）:\n' "${#targets[@]}" "$skipped"
	local i
	for i in "${!targets[@]}"; do
		printf '  @%-20s %s\n' "${names[$i]}" "${targets[$i]}"
	done
	printf '本文:\n  %s\n' "$text"

	if [ "$do_send" -eq 0 ]; then
		printf '\n--send を付けていないので送っていない。宛先を確認してから付け直すこと。\n'
		return 0
	fi

	local sent=0 failed=0 body
	for i in "${!targets[@]}"; do
		body="$(send_message "$id" "$token" "{\"comment_id\":$(json_string "${targets[$i]}")}" "$text")"
		if has_error "$body"; then
			# 1件落ちても残りは送る。理由は相手ごとに違う（7日超過、返信済み等）。
			print_error "$body" "@${names[$i]} への DM"
			failed=$((failed + 1))
		else
			record_sent "$account" "${targets[$i]}" "${names[$i]}"
			printf '送信: @%s\n' "${names[$i]}"
			sent=$((sent + 1))
		fi
		sleep "$SEND_INTERVAL"
	done

	printf '完了: 送信 %d 件 / 失敗 %d 件（台帳: %s）\n' "$sent" "$failed" "$(sent_log "$account")"
	[ "$failed" -eq 0 ]
}

cmd_threads() {
	local account="${1:-}"
	need_account "$account"

	local id token body
	id="$(account_value "$account" IG_USER_ID)"
	token="$(account_value "$account" ACCESS_TOKEN)"

	body="$(graph_get "$id/conversations" \
		--data-urlencode "platform=instagram" \
		--data-urlencode "fields=participants,updated_time" \
		--data-urlencode "limit=50" \
		--data-urlencode "access_token=$token")"
	fail_on_error "$body" 'DM 一覧の取得'

	# participants には自分も入る。自分の IG ユーザー ID の側を落として相手だけ出す。
	json_rows "$body" updated_time \
		participants.data.0.id participants.data.0.username \
		participants.data.1.id participants.data.1.username |
		awk -F"$SEP" -v me="$id" '
			{
				if ($2 != me && $2 != "") { print $2 "\t@" $3 "\t" $1 }
				else if ($4 != me && $4 != "") { print $4 "\t@" $5 "\t" $1 }
			}'
}

cmd_send() {
	local account="${1:-}" igsid="${2:-}" text="${3:-}"
	[ -n "$igsid" ] || die '宛先の IGSID が指定されていない（reel_dm.sh threads で拾える）'
	[ -n "$text" ] || die '本文が指定されていない'
	need_account "$account"

	local id token body
	id="$(account_value "$account" IG_USER_ID)"
	token="$(account_value "$account" ACCESS_TOKEN)"

	body="$(send_message "$id" "$token" "{\"id\":$(json_string "$igsid")}" "$text")"
	if has_error "$body"; then
		print_error "$body" "$igsid への DM"
		printf '  相手の最後のメッセージから24時間を過ぎていると送れない。\n' >&2
		printf '  相手から届いていない場合は、コメント経由（reel_dm.sh reply）でしか送れない。\n' >&2
		exit 1
	fi
	printf '送信: %s\n' "$(json_get "$body" message_id)"
}

main() {
	local command="${1:-}"
	[ $# -gt 0 ] && shift

	case "$command" in
	check) cmd_check "$@" ;;
	media) cmd_media "$@" ;;
	comments) cmd_comments "$@" ;;
	reply) cmd_reply "$@" ;;
	sweep) cmd_sweep "$@" ;;
	threads) cmd_threads "$@" ;;
	send) cmd_send "$@" ;;
	'' | -h | --help | help) usage ;;
	*) die "知らないコマンド: $command（reel_dm.sh --help）" ;;
	esac
}

main "$@"
