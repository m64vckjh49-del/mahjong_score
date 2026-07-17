// test/score_table_page_test.dart
//
// score_table_page.dart（点数早見表画面）に対するウィジェットテスト。
// 各翻ごとのカードが表示されること、表内の点数が hand_scoring.dart の
// 実際の計算結果と一致することを確認する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mahjong_score/hand_scoring.dart';
import 'package:mahjong_score/score_table_page.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('翻ごとのカードと限度役カードが表示される', (tester) async {
    await tester.pumpWidget(wrap(const ScoreTablePage()));
    await tester.pumpAndSettle();

    expect(find.text('🀄 点数早見表'), findsOneWidget);
    expect(find.text('1翻'), findsOneWidget);
    expect(find.text('2翻'), findsOneWidget);

    final scrollable = find.byKey(const Key('scoreTableList'));
    await tester.dragUntilVisible(find.text('5翻以上（満貫〜役満）'), scrollable, const Offset(0, -300));
    expect(find.text('3翻'), findsOneWidget);
    expect(find.text('4翻'), findsOneWidget);
    expect(find.text('5翻以上（満貫〜役満）'), findsOneWidget);
  });

  testWidgets('30符4翻の子ロン点数が実際の計算式と一致する', (tester) async {
    await tester.pumpWidget(wrap(const ScoreTablePage()));
    await tester.pumpAndSettle();

    final scrollable = find.byKey(const Key('scoreTableList'));
    final base = calcBasePoints(4, 30);
    final expectedRon = ceilTo100(base * 4);
    await tester.dragUntilVisible(find.text('$expectedRon'), scrollable, const Offset(0, -300));
    expect(find.text('$expectedRon'), findsWidgets);
  });

  testWidgets('数え役満（13翻以上）は満貫〜役満カードに1行で表示される', (tester) async {
    await tester.pumpWidget(wrap(const ScoreTablePage()));
    await tester.pumpAndSettle();

    final scrollable = find.byKey(const Key('scoreTableList'));
    await tester.dragUntilVisible(find.text('数え役満'), scrollable, const Offset(0, -300));
    expect(find.text('数え役満'), findsOneWidget);
  });
}
