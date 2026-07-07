// lib/unload_guard_web.dart
//
// UnloadGuard のWeb向け実装。
//
// このアプリ（特に対局スコア画面 session_page.dart）は、対局中の持ち点・本場・
// 供託・履歴などをブラウザのメモリ上にしか保持しない（永続化していない）。
// そのため、対局の途中でうっかりタブを閉じたりリロードしたりすると、
// それまでの記録が警告なく全て消えてしまう。
// これを防ぐため、対局中（MahjongSession.isStarted）はブラウザ標準の
// 「このページを離れますか？」確認ダイアログを出すようにする。
//
// dart:html は非推奨（将来的には package:web + dart:js_interop への移行が
// 推奨されている）だが、この用途（beforeunloadイベント1つだけ）に限っては
// 現行Flutter/Dartでも問題なく動作するため使用する。影響範囲をこのファイル
// だけに限定するため、非推奨警告はこのファイル内でのみ無効化する。
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

class UnloadGuard {
  static bool _enabled = false;
  static void Function(html.Event)? _handler;

  static void enable() {
    if (_enabled) return;
    _enabled = true;
    _handler = (html.Event event) {
      // 標準に従い、returnValue を設定するとブラウザが確認ダイアログを表示する。
      // 文言自体はブラウザ側の定型文が使われ、ここでの文字列は無視されることが多いが、
      // 仕様上は空文字ではなく何かしらの値を入れておく。
      (event as html.BeforeUnloadEvent).returnValue = '対局データが保存されていません。このページを離れますか？';
    };
    html.window.addEventListener('beforeunload', _handler);
  }

  static void disable() {
    if (!_enabled) return;
    _enabled = false;
    if (_handler != null) {
      html.window.removeEventListener('beforeunload', _handler);
      _handler = null;
    }
  }
}
