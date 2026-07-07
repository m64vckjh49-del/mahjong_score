// lib/unload_guard_stub.dart
//
// UnloadGuard の非Web環境向け実装（何もしない）。
// dart:html が使えないプラットフォーム（モバイル/デスクトップ/テスト実行のVM）
// では、そもそも「ブラウザタブを閉じる」という概念自体が存在しないため、
// 何もしないダミー実装を使う。
// unload_guard.dart から条件付きインポートで自動的に選択される。
class UnloadGuard {
  static void enable() {}
  static void disable() {}
}
