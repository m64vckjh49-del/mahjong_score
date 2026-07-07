// アプリ本体（麻雀点数計算アプリ）に対するウィジェットスモークテスト。
//
// 元々このファイルにはFlutterのデフォルトテンプレート（カウンターアプリ）用の
// テストが残っていたが、本アプリのホーム画面は MeldInputPage であり、
// カウンターは存在しないため常に失敗していた。実アプリの構造に合わせて置き換える。
//
// アプリの入力方法は「おまかせ入力」（14枚一括タップ→自動判定）がデフォルトで、
// 従来の「手動入力」（面子ごとに手動分類）は切り替えて使う設計になっている。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mahjong_score/main.dart';
import 'package:mahjong_score/meld_input.dart';

void main() {
  setUp(() {
    // 初回起動ガイド（オンボーディングダイアログ）は既読扱いにしてスキップする。
    SharedPreferences.setMockInitialValues({'seen_onboarding_v1': true});
  });

  testWidgets('MyApp launches directly into MeldInputPage in bulk-input mode by default',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byType(MeldInputPage), findsOneWidget);
    expect(find.text('面子入力（牌パレット）'), findsOneWidget);
    // デフォルトは「おまかせ入力」なので、14枚一括入力用のカードが表示される。
    expect(find.text('手牌（14枚）'), findsOneWidget);
    expect(find.text('面子1（3枚）'), findsNothing);
  });

  testWidgets('Switching to manual input mode shows the per-meld cards',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('手動入力'));
    await tester.pumpAndSettle();

    expect(find.text('手牌（14枚）'), findsNothing);
    expect(find.text('面子1（3枚）'), findsOneWidget);
  });

  testWidgets('Selecting 国士無双 in manual mode hides normal meld input and shows the kokushi panel',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('手動入力'));
    await tester.pumpAndSettle();

    expect(find.text('面子1（3枚）'), findsOneWidget);

    await tester.tap(find.text('国士無双'));
    await tester.pumpAndSettle();

    expect(find.text('面子1（3枚）'), findsNothing);
    expect(find.text('十三面待ち'), findsOneWidget);
  });

  testWidgets('Tapping 14 tiles in bulk-input mode auto-decomposes the hand and shows a score result',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // 牌パレット（画面下固定のTabBarView内）に表示されるタイルは、
    // assets/tiles/*.png の実画像（Image.asset）として描画される（フォールバックの
    // テキスト表示にはならない）。手牌プールのタイル表示も同じ画像を使うため、
    // アセット名で該当画像を探しつつ TabBarView の範囲に絞ってタップする。
    Finder paletteTile(String suit, int rank) => find.descendant(
          of: find.byType(TabBarView),
          matching: find.byWidgetPredicate(
            (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/tiles/$suit$rank.png',
          ),
        );

    // 萬子タブ（初期表示）で 1m〜9m をタップ（123m/456m/789mの3面子分）。
    for (final r in [1, 2, 3, 4, 5, 6, 7, 8, 9]) {
      await tester.tap(paletteTile('m', r));
      await tester.pump();
    }

    // 筒子タブへ切り替えて 1p を3回タップ（刻子）。
    await tester.tap(find.text('筒'));
    await tester.pumpAndSettle();
    for (int i = 0; i < 3; i++) {
      await tester.tap(paletteTile('p', 1));
      await tester.pump();
    }

    // 索子タブへ切り替えて 2s を2回タップ（雀頭＝和了牌）。
    await tester.tap(find.text('索'));
    await tester.pumpAndSettle();
    for (int i = 0; i < 2; i++) {
      await tester.tap(paletteTile('s', 2));
      await tester.pump();
    }

    await tester.pumpAndSettle();
    expect(find.text('14 / 14枚（長押しで1枚削除）'), findsOneWidget);

    await tester.tap(find.text('計算（門前: はい）'));
    await tester.pumpAndSettle();

    expect(find.text('結果'), findsOneWidget);
  });

  testWidgets('手動入力で面子を槓（カン）に切り替えると4枚集められ、暗槓として計算結果に反映される',
      (WidgetTester tester) async {
    // 手動入力画面は「面子カード（スクロール領域）」の上に「画面下固定の牌パレット/入力先表示」が
    // 重なるレイアウトのため、デフォルトのテストウィンドウサイズだと面子1のチップが
    // 固定パレット領域と重なってヒットテストに失敗する。十分縦長のサイズに広げておく。
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('手動入力'));
    await tester.pumpAndSettle();

    Finder paletteTile(String suit, int rank) => find.descendant(
          of: find.byType(TabBarView),
          matching: find.byWidgetPredicate(
            (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/tiles/$suit$rank.png',
          ),
        );

    // 面子1のカードを「槓（カン）」に切り替える。4枚集める前提に変わるはず。
    expect(find.text('面子1（3枚）'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, '槓（カン）').first);
    await tester.pumpAndSettle();
    expect(find.text('面子1（4枚）'), findsOneWidget);

    // 面子1：1m を4枚（暗槓）。萬子タブは初期表示のまま。
    for (int i = 0; i < 4; i++) {
      await tester.tap(paletteTile('m', 1));
      await tester.pump();
    }

    // 面子2：2p/3p/4p（順子）。
    await tester.tap(find.text('筒'));
    await tester.pumpAndSettle();
    for (final r in [2, 3, 4]) {
      await tester.tap(paletteTile('p', r));
      await tester.pump();
    }

    // 面子3：5s/6s/7s、面子4：8s×3（刻子）、雀頭：9s×2。
    await tester.tap(find.text('索'));
    await tester.pumpAndSettle();
    for (final r in [5, 6, 7]) {
      await tester.tap(paletteTile('s', r));
      await tester.pump();
    }
    for (int i = 0; i < 3; i++) {
      await tester.tap(paletteTile('s', 8));
      await tester.pump();
    }
    for (int i = 0; i < 2; i++) {
      await tester.tap(paletteTile('s', 9));
      await tester.pump();
    }

    await tester.pumpAndSettle();

    await tester.tap(find.text('計算（門前: はい）'));
    await tester.pumpAndSettle();

    expect(find.text('結果'), findsOneWidget);
    // 1mは么九牌なので、暗槓のふ加算（么九・暗槓=32符）が明細に出ているはず。
    expect(find.textContaining('槓子（暗・么九）'), findsOneWidget);
  });

  testWidgets('字牌パレットは漢字ファイル名の実画像として描画され、フォールバックのテキスト表示にならない',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('手動入力'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('字'));
    await tester.pumpAndSettle();

    // 字牌タブ内の「東」は Image.asset(assets/tiles/東.png) として描画されるはず
    // （フォールバックのテキスト表示だと Image ウィジェット自体が存在しない）。
    final honorTile = find.descendant(
      of: find.byType(TabBarView),
      matching: find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/tiles/東.png',
      ),
    );
    expect(honorTile, findsOneWidget);
  });
}
