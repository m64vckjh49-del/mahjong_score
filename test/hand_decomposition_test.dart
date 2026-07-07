// test/hand_decomposition_test.dart
//
// hand_decomposition.dart（14枚一括タップ入力からの自動組み立てエンジン）に対する
// ユニットテスト。待ちの種類ごとの判定、複数解釈がある場合の高点法による
// 最高点選択、七対子・国士無双の自動検出を確認する。

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_score/hand_scoring.dart' as hs;
import 'package:mahjong_score/hand_decomposition.dart';

hs.Tile m(int r) => hs.Tile(hs.Suit.m, r);
hs.Tile p(int r) => hs.Tile(hs.Suit.p, r);
hs.Tile s(int r) => hs.Tile(hs.Suit.s, r);
hs.Tile z(int r) => hs.Tile(hs.Suit.z, r);

void main() {
  group('通常形の待ち判定', () {
    test('リャンメン（2-3待ちの4を除いたケース: 3,4 + 5で完成 → ryanmen）', () {
      // 手牌: 3m4m + 5m(和了) / 2p3p4p / 5s6s7s / 8s8s8s / 9s9s
      final tiles = [
        m(3), m(4), m(5),
        p(2), p(3), p(4),
        s(5), s(6), s(7),
        s(8), s(8), s(8),
        s(9), s(9),
      ];
      final outcome = decomposeAndScore(
        concealedTiles: tiles,
        winningTile: m(5),
        winType: hs.WinType.ron,
        isDealer: false,
        seatWind: 1,
        roundWind: 1,
      );
      expect(outcome.isValid, isTrue);
      expect(outcome.best.hand.waitType, hs.WaitType.ryanmen);
    });

    test('カンチャン（3m + 5m和了 + 4mを待つ）', () {
      final tiles = [
        m(3), m(4), m(5),
        p(2), p(3), p(4),
        s(5), s(6), s(7),
        s(8), s(8), s(8),
        s(9), s(9),
      ];
      // 4mが和了牌でカンチャン
      final outcome = decomposeAndScore(
        concealedTiles: tiles,
        winningTile: m(4),
        winType: hs.WinType.ron,
        isDealer: false,
        seatWind: 1,
        roundWind: 1,
      );
      expect(outcome.isValid, isTrue);
      expect(outcome.best.hand.waitType, hs.WaitType.kanchan);
    });

    test('ペンチャン（1m2m + 3m和了）', () {
      final tiles = [
        m(1), m(2), m(3),
        p(2), p(3), p(4),
        s(5), s(6), s(7),
        s(8), s(8), s(8),
        s(9), s(9),
      ];
      final outcome = decomposeAndScore(
        concealedTiles: tiles,
        winningTile: m(3),
        winType: hs.WinType.ron,
        isDealer: false,
        seatWind: 1,
        roundWind: 1,
      );
      expect(outcome.isValid, isTrue);
      expect(outcome.best.hand.waitType, hs.WaitType.penchan);
    });

    test('ペンチャン（8m9m + 7m和了）', () {
      final tiles = [
        m(7), m(8), m(9),
        p(2), p(3), p(4),
        s(5), s(6), s(7),
        s(8), s(8), s(8),
        s(9), s(9),
      ];
      final outcome = decomposeAndScore(
        concealedTiles: tiles,
        winningTile: m(7),
        winType: hs.WinType.ron,
        isDealer: false,
        seatWind: 1,
        roundWind: 1,
      );
      expect(outcome.isValid, isTrue);
      expect(outcome.best.hand.waitType, hs.WaitType.penchan);
    });

    test('タンキ（雀頭待ち）', () {
      final tiles = [
        m(2), m(3), m(4),
        p(2), p(3), p(4),
        s(5), s(6), s(7),
        s(8), s(8), s(8),
        z(1), z(1),
      ];
      final outcome = decomposeAndScore(
        concealedTiles: tiles,
        winningTile: z(1),
        winType: hs.WinType.ron,
        isDealer: false,
        seatWind: 1,
        roundWind: 1,
      );
      expect(outcome.isValid, isTrue);
      expect(outcome.best.hand.waitType, hs.WaitType.tanki);
    });

    test('シャンポン待ち：ロンで完成した刻子は明刻扱い（winningMeldIndexが設定される）', () {
      final tiles = [
        m(2), m(3), m(4),
        p(2), p(3), p(4),
        s(5), s(6), s(7),
        z(1), z(1), z(1),
        z(2), z(2),
      ];
      final outcome = decomposeAndScore(
        concealedTiles: tiles,
        winningTile: z(1),
        winType: hs.WinType.ron,
        isDealer: false,
        seatWind: 3,
        roundWind: 1,
      );
      expect(outcome.isValid, isTrue);
      expect(outcome.best.hand.waitType, hs.WaitType.shanpon);
      expect(outcome.best.hand.winningMeldIndex, isNot(-1));
      final winningMeld = outcome.best.hand.melds[outcome.best.hand.winningMeldIndex];
      expect(winningMeld.isTriplet, isTrue);
      expect(winningMeld.baseTile, z(1));
    });
  });

  test('あいまいな待ち（2m3m4m4m4m）はリャンメン解釈とタンキ解釈のうち最高点を採用する', () {
    // 2m3m4m + 4m4m(雀頭) という唯一の分解パターンにおいて、和了牌4mは
    // 「seq(2,3,4)の一部（リャンメン）」「pair(4,4)の一部（タンキ）」の
    // 両方の組に属するため、同一分解の中で2通りの待ち解釈が生じる。
    final tiles = [
      m(2), m(3), m(4), m(4), m(4),
      p(2), p(3), p(4),
      s(5), s(6), s(7),
      z(5), z(5), z(5),
    ];
    final outcome = decomposeAndScore(
      concealedTiles: tiles,
      winningTile: m(4),
      winType: hs.WinType.tsumo,
      isDealer: false,
      seatWind: 1,
      roundWind: 1,
    );
    expect(outcome.isValid, isTrue);
    // 複数の解釈が候補として生成されていること（あいまい性が正しく検出されている）。
    expect(outcome.candidates.length, greaterThan(1));
    // 最高点の解釈が採用されていること。
    final maxPoints = outcome.candidates.map((c) => c.totalPoints).reduce((a, b) => a > b ? a : b);
    expect(outcome.best.totalPoints, maxPoints);
  });

  group('七対子', () {
    test('7つの対子から自動的に七対子として検出される', () {
      final tiles = [
        m(1), m(1),
        m(9), m(9),
        p(3), p(3),
        s(7), s(7),
        z(1), z(1),
        z(3), z(3),
        z(5), z(5),
      ];
      final outcome = decomposeAndScore(
        concealedTiles: tiles,
        winningTile: z(5),
        winType: hs.WinType.ron,
        isDealer: false,
        seatWind: 1,
        roundWind: 1,
      );
      expect(outcome.isValid, isTrue);
      final chiitoiCandidate = outcome.candidates.firstWhere(
        (c) => c.hand.isChiitoi,
        orElse: () => throw StateError('chiitoi candidate not found'),
      );
      expect(chiitoiCandidate.hand.melds.length, 7);
      expect(chiitoiCandidate.result.yakus.any((y) => y.name == '七対子'), isTrue);
    });
  });

  group('国士無双', () {
    test('13種の么九牌+1枚重複で国士無双として検出される（シングル待ち）', () {
      // 重複している種類はz(7)。和了牌がその重複牌とは別の種類（z(1)）である場合、
      // 和了前の13枚は「z(7)が対子、z(1)が欠けている」というシングル待ちの形になる。
      final tiles = [
        m(1), m(9), p(1), p(9), s(1), s(9),
        z(1), z(2), z(3), z(4), z(5), z(6), z(7),
        z(7), // 重複（対子）
      ];
      final outcome = decomposeAndScore(
        concealedTiles: tiles,
        winningTile: z(1),
        winType: hs.WinType.ron,
        isDealer: false,
        seatWind: 1,
        roundWind: 1,
      );
      expect(outcome.isValid, isTrue);
      final kokushi = outcome.candidates.firstWhere((c) => c.hand.isKokushi);
      expect(kokushi.hand.kokushi13Wait, isFalse);
      expect(kokushi.result.yakumanMultiplier, 1);
    });

    test('13面待ちで和了した場合はダブル役満として検出される', () {
      final tiles = [
        m(1), m(9), p(1), p(9), s(1), s(9),
        z(1), z(2), z(3), z(4), z(5), z(6), z(7),
        z(7), // 和了牌としてz(7)がもう1枚（＝和了前は13種類1枚ずつ揃っていた）
      ];
      final outcome = decomposeAndScore(
        concealedTiles: tiles,
        winningTile: z(7),
        winType: hs.WinType.tsumo,
        isDealer: false,
        seatWind: 1,
        roundWind: 1,
      );
      final kokushi = outcome.candidates.firstWhere((c) => c.hand.isKokushi);
      expect(kokushi.hand.kokushi13Wait, isTrue);
      expect(kokushi.result.yakumanMultiplier, 2);
    });
  });
}
