#!/usr/bin/env bash
#
# reel_series.sh - 連載シリーズの台本を持って、そのまま投稿まで運ぶ
#
# 1話 = 1ファイル。series/<series>/episodes/NNN-<slug>.md に台本と本文を書いておき、
# 話数・CTA・ハッシュタグを足した投稿本文の組み立てと、投稿後の記録をここが受け持つ。
# 実際の投稿は reel_post.sh publish に渡す。このスクリプトは「何を投稿するか」だけを扱う。
#
# 話数はファイル名の頭の番号がそのまま。ヘッダに持たせると二重管理になるので持たない。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERIES="${REEL_SERIES:-ai-business}"
SERIES_ROOT="$REPO_ROOT/series/$SERIES"

die() {
	printf 'reel_series: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOS'
使い方:
  reel_series.sh list                       全話の状態を出す
  reel_series.sh next                       次に投稿する回を出す
  reel_series.sh show <話>                  台本を出す
  reel_series.sh new <slug> <題材>          次の番号で台本を作る
  reel_series.sh caption <話>               投稿本文（話数・CTA・タグ込み）を組み立てて出す
  reel_series.sh post <話> [動画] [--dry-run]
                                            本文を組み立てて投稿し、結果を台本に書き戻す

<話> は番号でもスラッグの一部でもファイルパスでもよい。1 も 001 も hanaya も同じ回を指す。
<動画> はファイルでも共有URLでもよい。省略すると台本の video 欄を使う。

例:
  reel_series.sh new hanaya 町の花屋
  reel_series.sh post 1 ~/Movies/reel001.mp4
  REEL_SERIES=other reel_series.sh list      別のシリーズを見る
EOS
}

series_file() {
	printf '%s' "$SERIES_ROOT/series.md"
}

episodes_dir() {
	printf '%s' "$SERIES_ROOT/episodes"
}

require_series() {
	[ -f "$(series_file)" ] || die "シリーズが無い: series/$SERIES/series.md（REEL_SERIES で切り替えられる）"
}

# ファイル先頭の --- で挟まれたヘッダから値を1つ取り出す。無ければ空文字。
meta_get() {
	awk -v key="$2" '
		NR == 1 && $0 == "---" { inhead = 1; next }
		inhead && $0 == "---" { exit }
		inhead {
			i = index($0, ":")
			if (i == 0) next
			k = substr($0, 1, i - 1)
			v = substr($0, i + 1)
			gsub(/^[ \t]+|[ \t]+$/, "", k)
			gsub(/^[ \t]+|[ \t]+$/, "", v)
			if (k == key) { print v; exit }
		}
	' "$1"
}

# ヘッダの1行だけ差し替える。無いキーは閉じの --- の直前に足す。
meta_set() {
	local file="$1" key="$2" value="$3" tmp
	tmp="$(mktemp)"
	awk -v key="$key" -v value="$value" '
		NR == 1 && $0 == "---" { inhead = 1; print; next }
		inhead && $0 == "---" {
			if (!done) print key ": " value
			inhead = 0
			done = 1
			print
			next
		}
		inhead {
			i = index($0, ":")
			if (i > 0) {
				k = substr($0, 1, i - 1)
				gsub(/^[ \t]+|[ \t]+$/, "", k)
				if (k == key) { print key ": " value; done = 1; next }
			}
			print
			next
		}
		{ print }
	' "$file" >"$tmp"
	cat "$tmp" >"$file"
	rm -f "$tmp"
}

# 前後の空行を落とす。見出しの直後と次の見出しの手前は必ず空くので、そのまま
# 連結すると本文に余計な改行が入る。
trim_blank() {
	awk '
		/[^[:space:]]/ {
			started = 1
			while (blank > 0) { print ""; blank-- }
			blank = 0
			print
			next
		}
		started { blank++ }
	'
}

# 「## 見出し」から次の「## 」までを抜き出す。
section() {
	awk -v head="## $2" '
		$0 == head { on = 1; next }
		on && /^## / { exit }
		on { print }
	' "$1" | trim_blank
}

# 番号・スラッグ・パスのどれでも1話に解決する。曖昧なら止める。
resolve_episode() {
	local ref="${1:-}" dir file base glob
	local -a matches=()
	[ -n "$ref" ] || die '話が指定されていない（reel_series.sh list で一覧）'

	if [ -f "$ref" ]; then
		printf '%s' "$ref"
		return 0
	fi

	dir="$(episodes_dir)"
	[ -d "$dir" ] || die "台本のディレクトリが無い: series/$SERIES/episodes"

	case "$ref" in
	'' | *[!0-9]*) glob="*$ref*.md" ;;
	*) glob="$(printf '%03d' "$((10#$ref))")-*.md" ;;
	esac

	for file in "$dir"/*.md; do
		[ -f "$file" ] || continue
		base="$(basename "$file")"
		# shellcheck disable=SC2254 # glob はパターンとして展開させる
		case "$base" in
		$glob) matches+=("$file") ;;
		esac
	done

	case "${#matches[@]}" in
	0) die "その話が見つからない: $ref" ;;
	1) printf '%s' "${matches[0]}" ;;
	*)
		printf 'reel_series: %s に当てはまる話が複数ある:\n' "$ref" >&2
		printf '  %s\n' "${matches[@]##*/}" >&2
		exit 1
		;;
	esac
}

# 1行1件で出す。番号を数えるときにパイプで受けるので、改行を落とさない。
episode_number() {
	local base
	base="$(basename "$1")"
	printf '%s\n' "${base%%-*}"
}

status_label() {
	case "$1" in
	draft | '') printf '下書き' ;;
	ready) printf '撮影済' ;;
	posted) printf '投稿済' ;;
	*) printf '%s' "$1" ;;
	esac
}

each_episode() {
	local dir file
	dir="$(episodes_dir)"
	[ -d "$dir" ] || return 0
	for file in "$dir"/*.md; do
		[ -f "$file" ] && printf '%s\n' "$file"
	done
}

cmd_list() {
	require_series
	local file found=0 status posted
	printf '%s（series/%s）\n\n' "$(meta_get "$(series_file)" title)" "$SERIES"
	while IFS= read -r file; do
		found=1
		status="$(meta_get "$file" status)"
		posted="$(meta_get "$file" posted_at)"
		printf '  %s  %s  %s%s\n' \
			"$(episode_number "$file")" \
			"$(status_label "$status")" \
			"$(meta_get "$file" title)" \
			"${posted:+  ($posted)}"
	done < <(each_episode)
	[ "$found" -eq 1 ] || printf '  まだ1話も無い（reel_series.sh new <slug> <題材>）\n'
}

# 未投稿のうち番号が一番若いもの。撮影済があればそれを優先する。
cmd_next() {
	require_series
	local file ready='' draft=''
	while IFS= read -r file; do
		case "$(meta_get "$file" status)" in
		posted) continue ;;
		ready) [ -n "$ready" ] || ready="$file" ;;
		*) [ -n "$draft" ] || draft="$file" ;;
		esac
	done < <(each_episode)

	file="${ready:-$draft}"
	[ -n "$file" ] || die '未投稿の回が無い'
	printf '%s %s（%s）\n  %s\n' \
		"$(episode_number "$file")" \
		"$(meta_get "$file" title)" \
		"$(status_label "$(meta_get "$file" status)")" \
		"${file#"$REPO_ROOT"/}"
}

cmd_show() {
	require_series
	# 解決に失敗したら止める。$(...) を引数に直接書くと、中で exit しても
	# 呼び出し側は素通りしてしまうので、一度変数で受ける。
	local file
	file="$(resolve_episode "${1:-}")"
	cat "$file"
}

cmd_new() {
	local slug="${1:-}" title="${2:-}"
	require_series
	[ -n "$slug" ] || die 'スラッグが指定されていない（例: reel_series.sh new hanaya 町の花屋）'
	[ -n "$title" ] || die '題材が指定されていない'
	case "$slug" in
	*[!a-z0-9-]*) die "スラッグに使えるのは英小文字・数字・- だけ: $slug" ;;
	esac

	local template dir file number last
	template="$SERIES_ROOT/template.md"
	[ -f "$template" ] || die "台本のテンプレートが無い: series/$SERIES/template.md"

	dir="$(episodes_dir)"
	mkdir -p "$dir"

	# 既にある番号の次を採る。歯抜けは埋めない（話数が入れ替わると混乱する）。
	last="$(each_episode | while IFS= read -r f; do episode_number "$f"; done | sort -n | tail -n 1)"
	number="$(printf '%03d' "$((10#${last:-0} + 1))")"
	file="$dir/$number-$slug.md"
	[ -e "$file" ] && die "もうある: ${file#"$REPO_ROOT"/}"

	# テンプレの {{番号}} {{題材}} を埋めるだけ。中身の書き方はテンプレ側に置く。
	awk -v number="$((10#$number))" -v title="$title" '
		{ gsub(/\{\{番号\}\}/, number); gsub(/\{\{題材\}\}/, title); print }
	' "$template" >"$file"

	printf '%s\n' "${file#"$REPO_ROOT"/}"
}

# 話数・本文・CTA・ハッシュタグをつないで投稿本文にする。
build_caption() {
	local file="$1" series body cta tags ep_tags caption
	series="$(series_file)"

	body="$(section "$file" キャプション)"
	[ -n "$body" ] || die "「## キャプション」が空: ${file#"$REPO_ROOT"/}"

	caption="$(printf '第%d話｜%s' "$((10#$(episode_number "$file")))" "$(meta_get "$file" title)")"
	caption="$caption"$'\n\n'"$body"

	cta="$(section "$series" CTA)"
	[ -n "$cta" ] && caption="$caption"$'\n\n'"$cta"

	tags="$(meta_get "$series" hashtags)"
	ep_tags="$(meta_get "$file" hashtags)"
	tags="$tags${ep_tags:+ $ep_tags}"
	[ -n "$tags" ] && caption="$caption"$'\n\n'"$tags"

	printf '%s\n' "$caption"
}

cmd_caption() {
	require_series
	local file
	file="$(resolve_episode "${1:-}")"
	build_caption "$file"
}

cmd_post() {
	require_series
	local dry_run=0 arg
	local -a rest=()
	for arg in "$@"; do
		case "$arg" in
		--dry-run) dry_run=1 ;;
		*) rest+=("$arg") ;;
		esac
	done

	local file video account caption status output media_id
	file="$(resolve_episode "${rest[0]-}")"
	video="${rest[1]-}"
	[ -n "$video" ] || video="$(meta_get "$file" video)"

	status="$(meta_get "$file" status)"
	if [ "$status" = posted ]; then
		die "第$((10#$(episode_number "$file")))話 は投稿済み（media_id: $(meta_get "$file" media_id)）。
撮り直して出し直すなら台本の status を ready に戻すこと。"
	fi

	account="$(meta_get "$file" account)"
	[ -n "$account" ] || account="$(meta_get "$(series_file)" account)"
	[ -n "$account" ] || die "アカウントが決まらない。台本かシリーズの account を埋めること。"
	[ -n "$video" ] || die "動画が無い。引数で渡すか、台本の video 欄を埋めること。"

	caption="$(build_caption "$file")"

	if [ "$dry_run" -eq 1 ]; then
		printf '投稿しない（--dry-run）\n  アカウント: %s\n  動画: %s\n\n' "$account" "$video"
		printf '%s\n' "$caption"
		return 0
	fi

	# publish は進捗を標準エラーに出すので、そのまま素通しでよい。標準出力に来る
	# 「投稿完了: <id>」だけ受け取って台本に書き戻す。
	output="$("$REPO_ROOT/reel_post.sh" publish "$account" "$video" "$caption")" ||
		die '投稿に失敗した。台本は変更していない。'
	printf '%s\n' "$output"

	media_id="$(printf '%s\n' "$output" | sed -n 's/^投稿完了: //p' | tail -n 1)"
	meta_set "$file" status posted
	meta_set "$file" media_id "$media_id"
	meta_set "$file" posted_at "$(date +%F)"
	printf '%s に記録した\n' "${file#"$REPO_ROOT"/}"
}

main() {
	local command="${1:-}"
	[ $# -gt 0 ] && shift

	case "$command" in
	list) cmd_list "$@" ;;
	next) cmd_next "$@" ;;
	show) cmd_show "$@" ;;
	new) cmd_new "$@" ;;
	caption) cmd_caption "$@" ;;
	post) cmd_post "$@" ;;
	'' | -h | --help | help) usage ;;
	*) die "知らないコマンド: $command（reel_series.sh --help）" ;;
	esac
}

main "$@"
