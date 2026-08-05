#!/usr/bin/env bash
# 投稿済みとみなせる動画を削除する。
# 判定は「そのファイルを最後に変更したコミットが RETENTION_DAYS 日以上前かどうか」。
# --dry-run を付けると削除せず対象だけ表示する。
set -euo pipefail

RETENTION_DAYS="${RETENTION_DAYS:-3}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

cd "$(dirname "$0")"
git rev-parse --git-dir >/dev/null

cutoff=$(( $(date +%s) - RETENTION_DAYS * 86400 ))
targets=()

# プロセス置換だと git の失敗を拾えず「対象なし」に見えてしまうので、先に受け取る
videos=$(git ls-files -- '*.mp4' '*.mov' '*.m4v' '*.webm')

while IFS= read -r file; do
  [ -n "$file" ] || continue
  committed=$(git log -1 --format=%ct -- "$file")
  # 履歴が引けないものは判定できないので触らない
  [ -n "$committed" ] || continue
  [ "$committed" -lt "$cutoff" ] || continue
  targets+=("$file")
done <<< "$videos"

if [ ${#targets[@]} -eq 0 ]; then
  echo "削除対象なし (保持期間: ${RETENTION_DAYS}日)"
  exit 0
fi

echo "削除対象 (${RETENTION_DAYS}日以上前):"
printf '  %s\n' "${targets[@]}"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "--dry-run のため削除しません"
  exit 0
fi

git rm --quiet -- "${targets[@]}"
git commit --quiet -m "clean: 投稿済みの動画を削除 (${#targets[@]}件)"
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
echo "${#targets[@]}件を削除して push しました"
