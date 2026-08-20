# Fat Cat 通訳（プロトタイプ）

日本語 ⇔ Español をブラウザだけでリアルタイム翻訳する、単一HTMLアプリ。
Zoom統合・3Dアバターの前段階として、まず「マイクの声を拾って画面に翻訳を出す」部分だけを作ったもの。

## 使い方

1. `index.html` を **Chrome または Edge** で開く（Safari は音声認識非対応）
2. 話したい言語側のマイクボタンを押す → マイクの使用を許可する
3. 話し終わると自動でもう片方の言語に翻訳され、画面に表示・音声で読み上げられる

ローカルで確認する場合:

```bash
cd fatcat-interpreter
python3 -m http.server 8000
# ブラウザで http://localhost:8000 を開く
```

`file://` で直接開いても動くが、環境によっては `http://` 経由の方が安定する。

## 仕組み

- **音声認識**: ブラウザ標準の Web Speech API（`webkitSpeechRecognition`）
- **翻訳**: [MyMemory Translation API](https://mymemory.translated.net/)（無料・APIキー不要）
- **読み上げ**: ブラウザ標準の `speechSynthesis`

## 既知の制限

- MyMemory は無料枠のため、翻訳精度・レート制限に限界がある（本番で使うなら DeepL API 等への差し替えを推奨）
- Web Speech API は Chrome/Edge 系のみ対応。Safari・Firefox では動作しない
- モバイルブラウザでの安定性は未検証
- 音声認識はマイクの音声をブラウザの認識サーバーに送信する仕組み（Chromeの場合Google）ため、機密性の高い会話には使わない

## 今後の展開（未着手）

1. Zoom Meeting SDK / Zoom Apps を使い、Bot としてミーティングに参加させる
2. 3Dアバター（静止画〜簡易リップシンク）をZoomの映像として送出する（仮想カメラ経由）
3. 翻訳エンジンを精度の高い有料APIに差し替える
