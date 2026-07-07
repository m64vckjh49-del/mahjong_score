import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_score/hand_scoring.dart' as hs;

hs.Meld seq(hs.Suit suit, int start, {bool open = false}) => hs.Meld(
      type: hs.MeldType.sequence,
      tiles: [hs.Tile(suit, start), hs.Tile(suit, start + 1), hs.Tile(suit, start + 2)],
      open: open,
    );

hs.Meld trip(hs.Suit suit, int rank, {bool open = false}) => hs.Meld(
      type: hs.MeldType.triplet,
      tiles: [hs.Tile(suit, rank), hs.Tile(suit, rank), hs.Tile(suit, rank)],
      open: open,
    );

hs.Meld pair(hs.Suit suit, int rank) => hs.Meld(
      type: hs.MeldType.pair,
      tiles: [hs.Tile(suit, rank), hs.Tile(suit, rank)],
      open: false,
    );

hs.HandInput baseHand({
  required List<hs.Meld> melds,
  required hs.WinType winType,
  required bool isDealer,
  hs.WaitType waitType = hs.WaitType.ryanmen,
  bool menzen = true,
  hs.Tile? winTile,
  bool isChiitoi = false,
  bool isKokushi = false,
  bool kokushi13Wait = false,
  bool tenhou = false,
  bool chiihou = false,
  int winningMeldIndex = -1,
}) {
  return hs.HandInput(
    melds: melds,
    winTile: winTile ?? const hs.Tile(hs.Suit.m, 1),
    waitType: waitType,
    winType: winType,
    isDealer: isDealer,
    seatWind: 1,
    roundWind: 1,
    riichi: false,
    doubleRiichi: false,
    ippatsu: false,
    menzen: menzen,
    doraCount: 0,
    akaDoraCount: 0,
    uraDoraCount: 0,
    isChiitoi: isChiitoi,
    kuitanAllowed: true,
    haitei: false,
    houtei: false,
    rinshan: false,
    chankan: false,
    isKokushi: isKokushi,
    kokushi13Wait: kokushi13Wait,
    tenhou: tenhou,
    chiihou: chiihou,
    winningMeldIndex: winningMeldIndex,
  );
}

void main() {
  group('Task1: 役満判定', () {
    test('大三元：白發中の刻子3つ＋順子1つ＋雀頭、ロン、子 → 役満32000', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.z, 5), // 白
          trip(hs.Suit.z, 6), // 發
          trip(hs.Suit.z, 7), // 中
          seq(hs.Suit.m, 1),
          pair(hs.Suit.s, 5),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
      );

      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('大三元'));
      expect(yakuman.multiplier, 1);

      final result = hs.scoreHand(h);
      expect(result.ronPoints, 32000);
      expect(result.limitName, '役満');
    });

    test('四暗刻（単騎でない）、ツモ、子 → 四暗刻・ツモ 子8000/親16000', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.m, 2),
          trip(hs.Suit.p, 3),
          trip(hs.Suit.s, 7),
          trip(hs.Suit.m, 5),
          pair(hs.Suit.z, 1),
        ],
        winType: hs.WinType.tsumo,
        isDealer: false,
        waitType: hs.WaitType.ryanmen, // 単騎待ちでない
      );

      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('四暗刻'));
      expect(yakuman.yakumans.map((y) => y.name), isNot(contains('四暗刻単騎')));
      expect(yakuman.multiplier, 1);

      final result = hs.scoreHand(h);
      expect(result.tsumoFromNonDealer, 8000);
      expect(result.tsumoFromDealer, 16000);
    });

    test('四暗刻単騎（暗刻4つ、単騎待ち）、ロン、親 → ダブル役満96000', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.m, 2),
          trip(hs.Suit.p, 3),
          trip(hs.Suit.s, 7),
          trip(hs.Suit.m, 5),
          pair(hs.Suit.z, 1),
        ],
        winType: hs.WinType.ron,
        isDealer: true,
        waitType: hs.WaitType.tanki,
      );

      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('四暗刻単騎'));
      expect(yakuman.multiplier, 2);

      final result = hs.scoreHand(h);
      expect(result.ronPoints, 96000);
      expect(result.limitName, '2倍役満');
    });

    test('大三元＋字一色の複合、ロン、子 → 64000', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.z, 5), // 白
          trip(hs.Suit.z, 6), // 發
          trip(hs.Suit.z, 7), // 中
          trip(hs.Suit.z, 1, open: true), // 東（鳴き。四暗刻と誤って複合しないようopenにする）
          pair(hs.Suit.z, 2),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        menzen: false,
      );

      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), containsAll(['大三元', '字一色']));
      expect(yakuman.multiplier, 2);

      final result = hs.scoreHand(h);
      expect(result.ronPoints, 64000);
    });

    test('役満なし・平和のみ成立 → 従来通りの通常役判定', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 1),
          seq(hs.Suit.m, 4),
          seq(hs.Suit.p, 2),
          seq(hs.Suit.s, 3),
          pair(hs.Suit.p, 5),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        waitType: hs.WaitType.ryanmen,
      );

      expect(hs.detectYakumans(h), isNull);

      final result = hs.scoreHand(h);
      expect(result.yakus.map((y) => y.name), contains('平和'));
      expect(result.yakumanMultiplier, 0);
      expect(result.han, 1);
      expect(result.fu.fuRounded, 30);
      expect(result.ronPoints, 1000);
    });

    test('小四喜：風牌の刻子3つ＋風牌の雀頭 → 役満', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.z, 1),
          trip(hs.Suit.z, 2),
          trip(hs.Suit.z, 3),
          seq(hs.Suit.m, 1),
          pair(hs.Suit.z, 4),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
      );
      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('小四喜'));
      expect(yakuman.multiplier, 1);
    });

    test('大四喜：風牌の刻子4つ → ダブル役満', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.z, 1),
          trip(hs.Suit.z, 2),
          trip(hs.Suit.z, 3),
          trip(hs.Suit.z, 4, open: true), // 四暗刻と誤って複合しないようopenにする
          pair(hs.Suit.p, 5),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        menzen: false,
      );
      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('大四喜'));
      expect(yakuman.yakumans.map((y) => y.name), isNot(contains('小四喜')));
      expect(yakuman.multiplier, 2);
    });

    test('清老頭：老頭牌のみ・全て刻子 → 役満', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.m, 1),
          trip(hs.Suit.m, 9),
          trip(hs.Suit.p, 1),
          trip(hs.Suit.s, 9),
          pair(hs.Suit.p, 9),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
      );
      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('清老頭'));
    });

    test('緑一色：發と索子2,3,4,6,8のみ → 役満', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.s, 2),
          seq(hs.Suit.s, 2),
          trip(hs.Suit.s, 6),
          trip(hs.Suit.z, 6),
          pair(hs.Suit.s, 8),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
      );
      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('緑一色'));
    });

    test('四槓子：槓子4つ → 役満', () {
      hs.Meld quad(hs.Suit suit, int rank) => hs.Meld(
            type: hs.MeldType.quad,
            tiles: [hs.Tile(suit, rank), hs.Tile(suit, rank), hs.Tile(suit, rank), hs.Tile(suit, rank)],
            open: false,
            quadKind: hs.QuadKind.closed,
          );
      final h = baseHand(
        melds: [
          quad(hs.Suit.m, 2),
          quad(hs.Suit.p, 3),
          quad(hs.Suit.s, 4),
          quad(hs.Suit.z, 5),
          pair(hs.Suit.z, 1),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
      );
      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('四槓子'));
    });

    test('国士無双：フラグ入力、通常待ち → 役満32000（子ロン）', () {
      final h = baseHand(
        melds: const [],
        winType: hs.WinType.ron,
        isDealer: false,
        isKokushi: true,
      );
      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('国士無双'));
      expect(yakuman.multiplier, 1);

      final result = hs.scoreHand(h);
      expect(result.ronPoints, 32000);
    });

    test('国士無双：十三面待ち → ダブル役満64000（子ロン）', () {
      final h = baseHand(
        melds: const [],
        winType: hs.WinType.ron,
        isDealer: false,
        isKokushi: true,
        kokushi13Wait: true,
      );
      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.multiplier, 2);

      final result = hs.scoreHand(h);
      expect(result.ronPoints, 64000);
    });

    // 以下2テストは同一の14枚 (1,1,1,2,3,4,6,7,8,9,9,9,5,5) を使う。
    // 和了牌が「余分な5」を含む側（=5）だと、それを除いた13枚が
    // 標準形 1112345678999 と完全一致する＝純正（9面待ちの純正九蓮宝燈）。
    // 和了牌が「1」だと、除いた13枚は 1,1,2,3,4,5,5,6,7,8,9,9,9 となり
    // 標準形と一致しない＝非純正の九蓮宝燈。
    test('九蓮宝燈：和了牌が標準形との差分にならないケース → 九蓮宝燈（純正ではない）', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.m, 1),
          seq(hs.Suit.m, 2),
          seq(hs.Suit.m, 6),
          trip(hs.Suit.m, 9),
          pair(hs.Suit.m, 5),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        winTile: const hs.Tile(hs.Suit.m, 1),
      );
      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('九蓮宝燈'));
      expect(yakuman.yakumans.map((y) => y.name), isNot(contains('純正九蓮宝燈')));
      expect(yakuman.multiplier, 1);
    });

    test('純正九蓮宝燈：和了牌を除くと1112345678999のピュア形 → ダブル役満', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.m, 1),
          seq(hs.Suit.m, 2),
          seq(hs.Suit.m, 6),
          trip(hs.Suit.m, 9),
          pair(hs.Suit.m, 5),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        winTile: const hs.Tile(hs.Suit.m, 5),
      );
      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('純正九蓮宝燈'));
      expect(yakuman.multiplier, 2);
    });

    test('天和：フラグのみで役満成立（通常手構造と併存）', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 1),
          seq(hs.Suit.m, 4),
          seq(hs.Suit.p, 2),
          seq(hs.Suit.s, 3),
          pair(hs.Suit.p, 5),
        ],
        winType: hs.WinType.tsumo,
        isDealer: true,
        tenhou: true,
      );
      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('天和'));
      expect(yakuman.multiplier, 1);
    });
  });

  group('Task2: ロン時の暗刻/明刻判定・シャンポン待ち', () {
    test('暗刻2つ＋ロンで完成した刻子1つ＋順子1つ、門前 → 三暗刻は不成立、その面子は明刻扱い', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.m, 2), // 暗刻（そのまま）
          trip(hs.Suit.p, 3), // 暗刻（そのまま）
          trip(hs.Suit.s, 7), // ロンで完成（見た目はopen:falseだが明刻扱いになるべき）
          seq(hs.Suit.p, 5),
          pair(hs.Suit.z, 1),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        waitType: hs.WaitType.shanpon,
        menzen: true,
        winningMeldIndex: 2,
      );

      expect(hs.detectYakumans(h), isNull);

      final result = hs.scoreHand(h);
      expect(result.yakus.map((y) => y.name), isNot(contains('三暗刻')));
      expect(
        result.fu.items.any((i) => i.label == '刻子（明・中張）' && i.value == 2),
        isTrue,
        reason: 'ロンで完成した刻子は明刻（簡9九・中張=2符）として計上されるべき',
      );
    });

    test('暗刻4つ、ツモで完成 → 四暗刻（役満）として判定され、三暗刻の判定には来ない', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.m, 2),
          trip(hs.Suit.p, 3),
          trip(hs.Suit.s, 7),
          trip(hs.Suit.m, 5),
          pair(hs.Suit.z, 1),
        ],
        winType: hs.WinType.tsumo,
        isDealer: false,
        waitType: hs.WaitType.shanpon,
      );

      final result = hs.scoreHand(h);
      expect(result.yakus.map((y) => y.name), contains('四暗刻'));
      expect(result.yakus.map((y) => y.name), isNot(contains('三暗刻')));
    });

    test('シャンポン待ちでロン、対子の片方が刻子として完成 → 待ち符+2、その刻子は明刻扱い', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 1),
          seq(hs.Suit.p, 2),
          trip(hs.Suit.s, 5), // 手出しの暗刻（触れられない）
          trip(hs.Suit.m, 7), // シャンポンでロン完成
          pair(hs.Suit.z, 3),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        waitType: hs.WaitType.shanpon,
        winningMeldIndex: 3,
      );

      final result = hs.scoreHand(h);
      expect(
        result.fu.items.any((i) => i.label.contains('待ち') && i.value == 2),
        isTrue,
        reason: 'シャンポン待ちは待ち符+2',
      );
      expect(
        result.fu.items.any((i) => i.label == '刻子（明・中張）' && i.value == 2),
        isTrue,
        reason: 'ロンで完成したシャンポンの刻子は明刻扱い',
      );
    });

    test('シャンポン待ちでツモ → 待ち符+2、完成した刻子は暗刻扱い（ツモなので）', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 1),
          seq(hs.Suit.p, 2),
          trip(hs.Suit.s, 5),
          trip(hs.Suit.m, 7),
          pair(hs.Suit.z, 3),
        ],
        winType: hs.WinType.tsumo,
        isDealer: false,
        waitType: hs.WaitType.shanpon,
        winningMeldIndex: 3,
      );

      final result = hs.scoreHand(h);
      expect(
        result.fu.items.any((i) => i.label.contains('待ち') && i.value == 2),
        isTrue,
        reason: 'シャンポン待ちは待ち符+2',
      );
      expect(
        result.fu.items.any((i) => i.label == '刻子（暗・中張）' && i.value == 4),
        isTrue,
        reason: 'ツモで完成した刻子は常に暗刻扱い',
      );
    });
  });

  group('Task3: 二盃口のレアケース', () {
    test('同一順子（萬子234）が4面子分、雀頭別、門前 → 二盃口が成立する', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 2),
          seq(hs.Suit.m, 2),
          seq(hs.Suit.m, 2),
          seq(hs.Suit.m, 2),
          pair(hs.Suit.p, 5),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        waitType: hs.WaitType.tanki,
        menzen: true,
      );

      final result = hs.scoreHand(h);
      expect(result.yakus.map((y) => y.name), contains('二盃口'));
      expect(result.yakus.map((y) => y.name), isNot(contains('一盃口')));
    });

    test('同一順子が2面子＋別の同一順子が2面子（計4面子）、門前 → 二盃口が成立する（従来通り）', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 2),
          seq(hs.Suit.m, 2),
          seq(hs.Suit.p, 5),
          seq(hs.Suit.p, 5),
          pair(hs.Suit.s, 7),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        waitType: hs.WaitType.tanki,
        menzen: true,
      );

      final result = hs.scoreHand(h);
      expect(result.yakus.map((y) => y.name), contains('二盃口'));
    });
  });
}
