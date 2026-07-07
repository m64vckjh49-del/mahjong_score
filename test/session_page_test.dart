// test/session_page_test.dart
//
// session_page.dart（台に1台置いて共有する対局スコア画面）に対するウィジェットテスト。
// セットアップ画面から対局を開始できること、和了・流局の記録がスコア表示に反映されること、
// 精算ダイアログが開けることを確認する。
//
// session はアプリ全体で1つのシングルトンなので、テスト間で状態が漏れないよう
// 各テストの直前に session.reset() を呼ぶ。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mahjong_score/session.dart';
import 'package:mahjong_score/session_page.dart';

void main() {
  setUp(() {
    session.reset();
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('対局開始前はセットアップ画面が表示され、開始すると4人分のスコアカードが並ぶ', (tester) async {
    await tester.pumpWidget(wrap(const SessionPage()));
    await tester.pumpAndSettle();

    expect(find.text('対局の設定'), findsOneWidget);
    expect(find.text('対局を開始'), findsOneWidget);

    await tester.tap(find.text('対局を開始'));
    await tester.pumpAndSettle();

    expect(session.isStarted, isTrue);
    expect(find.text('対局の設定'), findsNothing);
    expect(find.text('プレイヤー1'), findsOneWidget);
    expect(find.text('プレイヤー4'), findsOneWidget);
    expect(find.text('25000点'), findsNWidgets(4));
    expect(find.text('第1局'), findsOneWidget);
  });

  testWidgets('ロンを記録すると、和了者と放銃者の点数が更新される', (tester) async {
    session.start(names: ['A', 'B', 'C', 'D']);
    await tester.pumpWidget(wrap(const SessionPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('和了を記録'));
    await tester.pumpAndSettle();

    // デフォルトのまま（和了者=A(親), 放銃者=B, 点数=1000）で記録する。
    await tester.tap(find.text('記録する'));
    await tester.pumpAndSettle();

    expect(session.players[0].score, 25000 + 1000);
    expect(session.players[1].score, 25000 - 1000);
    expect(find.text('26000点'), findsOneWidget);
    expect(find.text('24000点'), findsOneWidget);
    // 親(A)がそのまま和了したので連荘し、本場が1に進む。
    expect(session.honba, 1);
    expect(find.text('本場: 1'), findsOneWidget);
  });

  testWidgets('流局で聴牌者にチェックを入れて記録すると、ノーテン払いが発生する', (tester) async {
    session.start(names: ['A', 'B', 'C', 'D']);
    await tester.pumpWidget(wrap(const SessionPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('流局を記録'));
    await tester.pumpAndSettle();

    // Cのみ聴牌にチェックを入れる（背後の対局中画面にも同名の表示があるため、
    // ダイアログ内の CheckboxListTile に絞って探す）。
    await tester.tap(find.descendant(of: find.byType(CheckboxListTile), matching: find.text('C')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('記録する'));
    await tester.pumpAndSettle();

    expect(session.players[2].score, 25000 + 3000);
    expect(session.players[0].score, 25000 - 1000);
  });

  testWidgets('リーチ宣言で1000点引かれ、供託が1本増える', (tester) async {
    session.start(names: ['A', 'B', 'C', 'D']);
    await tester.pumpWidget(wrap(const SessionPage()));
    await tester.pumpAndSettle();

    final riichiButtons = find.text('リーチ');
    await tester.tap(riichiButtons.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('リーチする'));
    await tester.pumpAndSettle();

    expect(session.players[0].score, 25000 - 1000);
    expect(session.kyotaku, 1);
    expect(find.text('供託: 1本'), findsOneWidget);
  });

  testWidgets('リーチ宣言後はボタンが「取消」に変わり、取消すると点数と供託が戻る', (tester) async {
    session.start(names: ['A', 'B', 'C', 'D']);
    await tester.pumpWidget(wrap(const SessionPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('リーチ').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('リーチする'));
    await tester.pumpAndSettle();

    expect(session.players[0].score, 25000 - 1000);
    expect(find.text('リーチ中'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消する'));
    await tester.pumpAndSettle();

    expect(session.players[0].score, 25000);
    expect(session.kyotaku, 0);
    expect(find.text('リーチ中'), findsNothing);
  });

  testWidgets('持ち点が1000点未満のプレイヤーはリーチを宣言できない', (tester) async {
    session.start(names: ['A', 'B', 'C', 'D']);
    session.players[0].score = 500;
    await tester.pumpWidget(wrap(const SessionPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('リーチ').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('宣言できません'), findsOneWidget);
    expect(find.text('リーチする'), findsNothing);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(session.players[0].score, 500);
  });

  testWidgets('和了ダイアログで点数を空欄のまま記録しようとすると、エラーが表示され記録されない', (tester) async {
    session.start(names: ['A', 'B', 'C', 'D']);
    await tester.pumpWidget(wrap(const SessionPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('和了を記録'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '和了点（本場・供託は自動加算）'), '');
    await tester.tap(find.text('記録する'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1以上の数字で入力してください'), findsOneWidget);
    // ダイアログは閉じておらず、点数も変わっていない。
    expect(find.text('和了を記録'), findsWidgets);
    expect(session.players[0].score, 25000);
    expect(session.history, isEmpty);
  });

  testWidgets('直前の記録を「元に戻す」ボタンで取り消せる', (tester) async {
    session.start(names: ['A', 'B', 'C', 'D']);
    await tester.pumpWidget(wrap(const SessionPage()));
    await tester.pumpAndSettle();

    // 元に戻すボタンは履歴が空の間は無効。
    final undoFinder = find.widgetWithText(OutlinedButton, '元に戻す');
    expect(tester.widget<OutlinedButton>(undoFinder).onPressed, isNull);

    await tester.tap(find.text('和了を記録'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('記録する'));
    await tester.pumpAndSettle();

    expect(session.players[0].score, 25000 + 1000);
    expect(tester.widget<OutlinedButton>(undoFinder).onPressed, isNotNull);

    await tester.tap(undoFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('元に戻す').last);
    await tester.pumpAndSettle();

    expect(session.players[0].score, 25000);
    expect(session.players[1].score, 25000);
    expect(session.history, isEmpty);
  });

  testWidgets('順位・精算ダイアログを開くと、全プレイヤーの順位が表示される', (tester) async {
    session.start(names: ['A', 'B', 'C', 'D'], returnPoints: 25000);
    await tester.pumpWidget(wrap(const SessionPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('順位・精算'));
    await tester.pumpAndSettle();

    expect(find.text('現在の順位（ウマ・オカ込み）'), findsOneWidget);
    // 背後の対局中画面にも同名のプレイヤーカードがあるため、ダイアログ内に絞って確認する。
    final dialogFinder = find.byType(AlertDialog);
    expect(find.descendant(of: dialogFinder, matching: find.text('A')), findsOneWidget);
    expect(find.descendant(of: dialogFinder, matching: find.text('B')), findsOneWidget);
    expect(find.descendant(of: dialogFinder, matching: find.text('C')), findsOneWidget);
    expect(find.descendant(of: dialogFinder, matching: find.text('D')), findsOneWidget);
  });
}
