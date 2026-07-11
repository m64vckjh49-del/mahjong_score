// lib/ui_theme.dart
//
// アプリ全体の見た目（配色・テーマ）をまとめたファイル。
// 「麻雀っぽい・かっこいい」を目指し、卓の緑（フェルト）をイメージした
// グリーン基調のブランドカラーを軸に、ベースは白系で見やすさを保ちつつ、
// AppBarや主要ボタンにはグラデーションでアクセントを付けている。
import 'package:flutter/material.dart';

/// ブランドカラーの定義。
class AppPalette {
  AppPalette._();

  /// Material3のColorSchemeを生成するための基準色（エメラルドグリーン）。
  static const seed = Color(0xFF15804F);

  /// グラデーションの濃い側（卓の深い緑）。
  static const gradientStart = Color(0xFF0B5D3B);

  /// グラデーションの明るい側（新緑寄りのエメラルド）。
  static const gradientEnd = Color(0xFF34B37B);

  /// 画面全体の下地（白ベースにごくわずかに緑を感じさせる色味）。
  static const background = Color(0xFFF6FBF8);
}

/// アプリ全体で使うテーマ本体。
ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppPalette.seed,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppPalette.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.gradientStart,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 1.5,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.primary),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedForegroundColor: Colors.white,
        selectedBackgroundColor: colorScheme.primary,
      ),
    ),
  );
}

/// AppBarの`flexibleSpace`に差し込む、卓の緑をイメージしたグラデーション背景。
class GradientAppBarBackground extends StatelessWidget {
  const GradientAppBarBackground({super.key});

  @override
  Widget build(BuildContext context) {
    // AppBarのflexibleSpaceはStack(fit: StackFit.passthrough)の中に置かれ、
    // 高さ方向がloose（min 0）な制約になることがある。DecoratedBoxは子を持たない
    // ため、その場合は面積0に潰れてグラデーションが全く見えなくなってしまう。
    // SizedBox.expandで明示的に利用可能な領域いっぱいに広げる。
    return const SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppPalette.gradientStart, AppPalette.gradientEnd],
          ),
        ),
      ),
    );
  }
}

/// グラデーション背景を持つ、画面の主役アクション用ボタン。
/// （計算実行・対局開始など、各画面で一番押してほしいボタンにだけ使う）
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final disabledColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);

    // 以前は Ink(decoration: ...) を使っていたが、Inkの装飾は「一番近い祖先の
    // Material」のペイント時にink featureとして描画される仕組みのため、間に
    // 挟まる各種レイヤー構成によってはグラデーションが画面に反映されないことが
    // ある（実ビルドで再現し、ボタンの背景が透明のまま文字だけが乗って見づらく
    // なっていた）。Containerは自分自身のRenderObjectで装飾を直接描画するため
    // この問題が起きない。タップ時のリップルだけをMaterial+InkWellで重ねる。
    return Container(
      decoration: BoxDecoration(
        gradient: disabled
            ? null
            : const LinearGradient(
                colors: [AppPalette.gradientStart, AppPalette.gradientEnd],
              ),
        color: disabled ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: disabled ? disabledColor : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    IconTheme(
                      data: IconThemeData(color: disabled ? disabledColor : Colors.white),
                      child: icon!,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
