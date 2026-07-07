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
    expect(find.text('国士無双（14枚）'), findsOneWidget);
    // 十三面待ちはスイッチではなく、実際に14枚入力した結果から自動判定される。
    expect(find.text('0 / 14枚（長押しで1枚削除）'), findsOneWidget);
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

  testWidgets('おまかせ入力で「1つ戻す」を押すと直前の1枚だけが取り消される', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    Finder paletteTile(String suit, int rank) => find.descendant(
          of: find.byType(TabBarView),
          matching: find.byWidgetPredicate(
            (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/tiles/$suit$rank.png',
          ),
        );

    // 「1つ戻す」は TextButton.icon（内部的には TextButton のサブクラス）なので、
    // byType(TextButton) では見つからない。bySubtype で探す。
    final undoButton = find.ancestor(of: find.text('1つ戻す'), matching: find.bySubtype<TextButton>());

    // 手牌が空の間は「1つ戻す」は無効。
    expect(tester.widget<TextButton>(undoButton).onPressed, isNull);

    // 3枚タップする（1m, 2m, 3m）。
    for (final r in [1, 2, 3]) {
      await tester.tap(paletteTile('m', r));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('3 / 14枚（長押しで1枚削除）'), findsOneWidget);
    expect(tester.widget<TextButton>(undoButton).onPressed, isNotNull);

    // 「1つ戻す」で末尾の1枚（3m）だけが消え、2枚に戻る。
    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(find.text('2 / 14枚（長押しで1枚削除）'), findsOneWidget);

    // もう一度押すと1枚に戻り、続けて空になれば再びボタンが無効化される。
    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(find.text('0 / 14枚（長押しで1枚削除）'), findsOneWidget);
    expect(tester.widget<TextButton>(undoButton).onPressed, isNull);
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

  testWidgets('国士無双：手動入力で実際に14枚タップすると役満として成立し、十三面待ちも自動判定される',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('手動入力'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('国士無双'));
    await tester.pumpAndSettle();

    Finder paletteTile(String suit, int rank) => find.descendant(
          of: find.byType(TabBarView),
          matching: find.byWidgetPredicate(
            (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/tiles/$suit$rank.png',
          ),
        );
    Finder paletteHonor(String kanji) => find.descendant(
          of: find.byType(TabBarView),
          matching: find.byWidgetPredicate(
            (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/tiles/$kanji.png',
          ),
        );

    // 么九牌以外（例: 2m）をタップしてもエラーになり、追加されないことを確認する。
    await tester.tap(paletteTile('m', 2));
    await tester.pumpAndSettle();
    expect(find.text('国士無双で使えるのは么九牌（1・9・字牌）のみです。'), findsOneWidget);
    expect(find.text('0 / 14枚（長押しで1枚削除）'), findsOneWidget);

    // 1m, 9m, 1p, 9p, 1s, 9sをタップ。
    await tester.tap(paletteTile('m', 1));
    await tester.pump();
    await tester.tap(paletteTile('m', 9));
    await tester.pump();
    await tester.tap(find.text('筒'));
    await tester.pumpAndSettle();
    await tester.tap(paletteTile('p', 1));
    await tester.pump();
    await tester.tap(paletteTile('p', 9));
    await tester.pump();
    await tester.tap(find.text('索'));
    await tester.pumpAndSettle();
    await tester.tap(paletteTile('s', 1));
    await tester.pump();
    await tester.tap(paletteTile('s', 9));
    await tester.pump();

    // 字牌7種（東南西北白發中）をタップ。ここまでで13種類がそろう。
    await tester.tap(find.text('字'));
    await tester.pumpAndSettle();
    for (final kanji in ['東', '南', '西', '北', '白', '發', '中']) {
      await tester.tap(paletteHonor(kanji));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('13 / 14枚（長押しで1枚削除）'), findsOneWidget);

    // 最後にもう1枚「東」をタップして14枚目（和了牌）とする。
    // 直前まで13種類が1枚ずつそろっていたので、これは十三面待ち（ダブル役満）になるはず。
    await tester.tap(paletteHonor('東'));
    await tester.pumpAndSettle();

    expect(find.text('14 / 14枚（長押しで1枚削除）'), findsOneWidget);
    expect(find.text('✓ 国士無双の形として成立しています（十三面待ち＝ダブル役満）'), findsOneWidget);

    await tester.tap(find.text('計算（門前: はい）'));
    await tester.pumpAndSettle();
    expect(find.text('結果'), findsOneWidget);
  });

  testWidgets('国士無双：同じ牌を3枚使おうとするとエラーになり、追加されない', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('手動入力'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('国士無双'));
    await tester.pumpAndSettle();

    Finder paletteTile(String suit, int rank) => find.descendant(
          of: find.byType(TabBarView),
          matching: find.byWidgetPredicate(
            (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/tiles/$suit$rank.png',
          ),
        );

    // 1mを2枚（許容範囲）。
    await tester.tap(paletteTile('m', 1));
    await tester.pump();
    await tester.tap(paletteTile('m', 1));
    await tester.pumpAndSettle();
    expect(find.text('2 / 14枚（長押しで1枚削除）'), findsOneWidget);

    // 3枚目はエラーになり、枚数は増えない。
    await tester.tap(paletteTile('m', 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('同じ牌を3枚以上使えません'), findsOneWidget);
    expect(find.text('2 / 14枚（長押しで1枚削除）'), findsOneWidget);
  });

  testWidgets('おまかせ入力：同じ牌を5枚使おうとするとエラーになり、追加されない', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    Finder paletteTile(String suit, int rank) => find.descendant(
          of: find.byType(TabBarView),
          matching: find.byWidgetPredicate(
            (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/tiles/$suit$rank.png',
          ),
        );

    for (int i = 0; i < 4; i++) {
      await tester.tap(paletteTile('m', 1));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('4 / 14枚（長押しで1枚削除）'), findsOneWidget);

    // 5枚目はエラーになり、枚数は増えない。
    await tester.tap(paletteTile('m', 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('同じ牌を5枚以上使えません'), findsOneWidget);
    expect(find.text('4 / 14枚（長押しで1枚削除）'), findsOneWidget);
  });

  testWidgets('「全部クリア」を押すと立直・ドラなどの状況フラグもリセットされる', (WidgetTester tester) async {
    // 状況フラグ群（立直など）はListView内の下の方にあり、デフォルトのテストウィンドウ
    // サイズだと画面下固定の操作バー/牌パレットに隠れてビルドされないため、
    // 十分縦長のサイズに広げておく。
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // 立直をONにしておく。
    await tester.scrollUntilVisible(
      find.text('立直'),
      300,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('立直'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '立直')).value, isTrue);

    await tester.tap(find.text('全部クリア'));
    await tester.pumpAndSettle();

    // 全部クリア後は、次の局に誤って引き継がれないよう立直もOFFに戻っているはず。
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '立直')).value, isFalse);
  });

  testWidgets('手動入力で面子を鳴き（オープン）にすると地和はオフに戻り選択不可になる',
      (WidgetTester tester) async {
    // 面子カードと状況フラグパネルの両方に届く必要があるため、十分縦長にしておく。
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('手動入力'));
    await tester.pumpAndSettle();

    final scrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );

    // デフォルト（ツモ・子）では地和が選択できるはずなのでONにしておく。
    await tester.scrollUntilVisible(find.text('地和（役満）'), 300, scrollable: scrollable);
    await tester.tap(find.text('地和（役満）'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '地和（役満）')).value, isTrue);

    // 面子1を鳴き（オープン）にする → 副露ありの手では地和は成立し得ないため、
    // 自動でOFFに戻り、以後は選択自体もできなくなるはず。
    await tester.scrollUntilVisible(find.widgetWithText(FilterChip, '鳴き（オープン）').first, 300, scrollable: scrollable);
    await tester.tap(find.widgetWithText(FilterChip, '鳴き（オープン）').first);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('地和（役満）'), 300, scrollable: scrollable);
    final chiihouSwitch = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '地和（役満）'));
    expect(chiihouSwitch.value, isFalse, reason: '鳴きが入った時点で地和は自動でOFFに戻るはず');
    expect(chiihouSwitch.onChanged, isNull, reason: '副露ありの手では地和は選択不可（スイッチが無効）になるはず');
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
