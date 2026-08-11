#!/usr/bin/env bash
#
# reel_fetch.sh - 動画URLから元ファイルを取ってくる
#
# TikTok などの共有URLは「ページのURL」であって動画そのものではない。ページを
# 解析して実体を取り出す必要があるので、そこは yt-dlp に任せる。URL が直接
# .mp4 を指しているなら curl だけで済むので yt-dlp は要らない。
#
# 取ってきたファイルの**パスだけ**を標準出力に出す。進捗やエラーは標準エラーに
# 出す。呼び出し側が $(...) でパスを受け取るため、ここを混ぜてはいけない。

set -euo pipefail

die() {
	printf 'reel_fetch: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOS'
使い方:
  reel_fetch.sh <url> [出力先ディレクトリ]

動画URLから元ファイルを取ってきて、そのパスを出す。出力先を省略したときは
一時ディレクトリに置く。

  reel_fetch.sh https://vt.tiktok.com/XXXXXXXX/
  reel_fetch.sh https://example.com/video.mp4 ~/Movies

ログインが要る動画は Cookie を渡す:
  REEL_FETCH_COOKIES_FROM_BROWSER=chrome reel_fetch.sh <url>
  REEL_FETCH_COOKIES=~/cookies.txt       reel_fetch.sh <url>
EOS
}

# クエリ文字列を落としてから拡張子を見る。?a=b が付いていても判定できるように。
is_direct_media() {
	local path="${1%%\?*}"
	case "${path##*/}" in
	*.mp4 | *.mov | *.m4v | *.webm) return 0 ;;
	*) return 1 ;;
	esac
}

safe_name() {
	printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

fetch_direct() {
	local url="$1" outdir="$2" path name
	path="${url%%\?*}"
	name="$(safe_name "${path##*/}")"
	[ -n "$name" ] || name='video.mp4'

	curl -fL --progress-bar --max-time 600 -o "$outdir/$name" -- "$url" >&2 ||
		die "取得できない: $url"

	printf '%s\n' "$outdir/$name"
}

fetch_with_ytdlp() {
	local url="$1" outdir="$2" stage file name
	command -v yt-dlp >/dev/null || die "yt-dlp が無い。ページのURLから動画を取り出すのに必要。
  brew install yt-dlp   または   pipx install yt-dlp
URL が直接 .mp4 を指しているなら yt-dlp 無しでも取れる。"

	# 落とし先を毎回空のディレクトリにして、その中の1本を拾う。yt-dlp は
	# 最終的なファイル名を自分で決めるので、こちらから決め打ちできない。
	stage="$(mktemp -d)"

	local args=(
		--no-playlist
		--merge-output-format mp4
		# リールに渡すので mp4 を優先する。無ければ何でも取って mp4 に寄せる。
		-f 'bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b'
		-o "$stage/%(id)s.%(ext)s"
	)

	# ログインが要る動画は Cookie が無いと取れない。ブラウザから直接読むか、
	# エクスポートした Netscape 形式のファイルを渡すか。
	if [ -n "${REEL_FETCH_COOKIES-}" ]; then
		[ -f "$REEL_FETCH_COOKIES" ] || die "Cookie ファイルが見つからない: $REEL_FETCH_COOKIES"
		args+=(--cookies "$REEL_FETCH_COOKIES")
	elif [ -n "${REEL_FETCH_COOKIES_FROM_BROWSER-}" ]; then
		args+=(--cookies-from-browser "$REEL_FETCH_COOKIES_FROM_BROWSER")
	fi

	if ! yt-dlp "${args[@]}" -- "$url" >&2; then
		rm -rf "$stage"
		die "動画を取得できない: $url
ログインが要る動画かもしれない。ブラウザでログイン済みなら Cookie を渡して試すこと:
  REEL_FETCH_COOKIES_FROM_BROWSER=chrome $0 '$url'"
	fi

	# 分割ダウンロードの残骸が混ざることがあるので、一番大きいものを本体とみなす。
	file="$(find "$stage" -type f -exec ls -S {} + 2>/dev/null | head -n 1)"
	if [ -z "$file" ]; then
		rm -rf "$stage"
		die "取得はできたがファイルが見つからない: $url"
	fi

	name="$(safe_name "$(basename "$file")")"
	mv "$file" "$outdir/$name"
	rm -rf "$stage"

	printf '%s\n' "$outdir/$name"
}

main() {
	local url="${1:-}" outdir="${2:-}"

	case "$url" in
	'' | -h | --help | help)
		usage
		return 0
		;;
	http://* | https://*) ;;
	*) die "URL を渡すこと（http:// か https:// で始まるもの）: $url" ;;
	esac

	command -v curl >/dev/null || die 'curl が無い'

	local temp_outdir=''
	if [ -n "$outdir" ]; then
		mkdir -p "$outdir"
	else
		outdir="$(mktemp -d)"
		temp_outdir="$outdir"
	fi
	outdir="$(cd "$outdir" && pwd)"

	# 取得に失敗すると、自分で作った一時ディレクトリが空のまま残る。rmdir は
	# 中身があれば何もしないので、成功したときの出力先は消えない。
	if [ -n "$temp_outdir" ]; then
		trap "rmdir '$temp_outdir' 2>/dev/null || true" EXIT
	fi

	if is_direct_media "$url"; then
		fetch_direct "$url" "$outdir"
	else
		fetch_with_ytdlp "$url" "$outdir"
	fi
}

main "$@"
