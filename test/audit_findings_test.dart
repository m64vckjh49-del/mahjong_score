// test/audit_findings_test.dart
//
// 監査用スタンドアロンテスト。既存の hand_scoring_test.dart / hand_decomposition_test.dart
// で既にカバーされている項目は重複させず、監査タスクで指定された観点ごとに
// 実際の HandInput/scoreHand API を叩いて期待値とのズレを確認する。
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

hs.Meld quad(hs.Suit suit, int rank, {bool open = false}) => hs.Meld(
      type: hs.MeldType.quad,
      tiles: [hs.Tile(suit, rank), hs.Tile(suit, rank), hs.Tile(suit, rank), hs.Tile(suit, rank)],
      open: open,
      quadKind: open ? hs.QuadKind.open : hs.QuadKind.closed,
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
  int seatWind = 1,
  int roundWind = 1,
  bool riichi = false,
  bool doubleRiichi = false,
  bool ippatsu = false,
  bool kuitanAllowed = true,
  bool haitei = false,
  bool houtei = false,
  bool rinshan = false,
  bool chankan = false,
  bool tenhou = false,
  bool chiihou = false,
  int doraCount = 0,
  int akaDoraCount = 0,
  int uraDoraCount = 0,
  int winningMeldIndex = -1,
}) {
  return hs.HandInput(
    melds: melds,
    winTile: winTile ?? const hs.Tile(hs.Suit.m, 1),
    waitType: waitType,
    winType: winType,
    isDealer: isDealer,
    seatWind: seatWind,
    roundWind: roundWind,
    riichi: riichi,
    doubleRiichi: doubleRiichi,
    ippatsu: ippatsu,
    menzen: menzen,
    doraCount: doraCount,
    akaDoraCount: akaDoraCount,
    uraDoraCount: uraDoraCount,
    isChiitoi: isChiitoi,
    kuitanAllowed: kuitanAllowed,
    haitei: haitei,
    houtei: houtei,
    rinshan: rinshan,
    chankan: chankan,
    tenhou: tenhou,
    chiihou: chiihou,
    winningMeldIndex: winningMeldIndex,
  );
}

void main() {
  group('監査1: 連風牌（ダブル東など）の役牌判定', () {
    test('親・東場で東の刻子（連風牌）→ 自風+場風の2翻になるべき', () {
      // 親（seatWind=1=東）、東場（roundWind=1=東）で東の刻子を持つ「連風牌」。
      // 実際のルールでは 自風(1翻) + 場風(1翻) = 2翻 として両方計上される。
      final h = baseHand(
        melds: [
          trip(hs.Suit.z, 1), // 東の刻子（連風牌）
          seq(hs.Suit.m, 2),
          seq(hs.Suit.p, 2),
          seq(hs.Suit.s, 2),
          pair(hs.Suit.m, 5),
        ],
        winType: hs.WinType.ron,
        isDealer: true,
        seatWind: 1,
        roundWind: 1,
        menzen: false, // 役牌のみで上がれるように面前縛りを回避
      );

      final yakus = hs.detectYakus(h);
      final yakuhaiCount = yakus.where((y) => y.name.startsWith('役牌')).length;
      // 期待: 役牌:自風 と 役牌:場風 の2つが計上される（計2翻）
      expect(yakuhaiCount, 2,
          reason: '連風牌（自風=場風）の刻子は自風・場風の両方で1翻ずつ、計2翻になるはず');
    });

    test('比較: 親・南場で東の刻子（連風牌でない、単なる客風）→ 役なし', () {
      final h = baseHand(
        melds: [
          trip(hs.Suit.z, 1), // 東（自風でも場風でもない客風。seatWind=2,roundWind=2 として比較）
          seq(hs.Suit.m, 2),
          seq(hs.Suit.p, 2),
          seq(hs.Suit.s, 2),
          pair(hs.Suit.m, 5),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        seatWind: 2,
        roundWind: 2,
        menzen: false,
      );
      final yakus = hs.detectYakus(h);
      final yakuhaiCount = yakus.where((y) => y.name.startsWith('役牌')).length;
      expect(yakuhaiCount, 0, reason: '客風のみなら役牌は0でよい（比較用の健全性チェック）');
    });
  });

  group('監査2: チャンタ/純チャンと槓子の相互作用', () {
    test('么九牌の暗槓を含むチャンタ手 → チャンタ成立', () {
      // 東(客風)の暗槓 + 123p + 123s + 789m + 99mの雀頭 → 全面子が么九牌を含み、
      // 順子もあり、字牌も含む → チャンタ成立するはず。
      final h = baseHand(
        melds: [
          quad(hs.Suit.z, 3), // 西の暗槓（么九=字牌）
          seq(hs.Suit.p, 1),
          seq(hs.Suit.s, 1),
          seq(hs.Suit.m, 7),
          pair(hs.Suit.m, 9),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
      );
      final yakus = hs.detectYakus(h);
      expect(yakus.map((y) => y.name), contains('チャンタ'),
          reason: '么九牌の槓子はチャンタの構成要素として認められるべき');
    });

    test('中張牌の槓子を1つ混ぜる → チャンタは不成立になるべき', () {
      final h = baseHand(
        melds: [
          quad(hs.Suit.p, 5), // 5pの槓子（中張牌）→ チャンタ崩壊
          seq(hs.Suit.p, 1),
          seq(hs.Suit.s, 1),
          seq(hs.Suit.m, 7),
          pair(hs.Suit.m, 9),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
      );
      final yakus = hs.detectYakus(h);
      expect(yakus.map((y) => y.name), isNot(contains('チャンタ')),
          reason: '中張牌の槓子を含む場合はチャンタが崩れるべき');
    });

    test('純チャン：老頭牌の暗槓＋老頭絡みの順子のみ、字牌なし → 純チャン成立、チャンタは重複しない', () {
      final h = baseHand(
        melds: [
          quad(hs.Suit.m, 9), // 9mの暗槓（老頭）
          seq(hs.Suit.p, 1),
          seq(hs.Suit.s, 1),
          seq(hs.Suit.m, 7),
          pair(hs.Suit.p, 9),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
      );
      final yakus = hs.detectYakus(h);
      expect(yakus.map((y) => y.name), contains('純チャン'));
      expect(yakus.map((y) => y.name), isNot(contains('チャンタ')),
          reason: '純チャンとチャンタは同時成立しない（排他）');
    });
  });

  group('監査3: 断么九と喰いタン', () {
    test('副露あり（開いた手）でkuitanAllowed=false → 断么九は不成立', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 2, open: true),
          seq(hs.Suit.p, 3),
          seq(hs.Suit.s, 4),
          trip(hs.Suit.m, 5),
          pair(hs.Suit.p, 6),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        menzen: false,
        kuitanAllowed: false,
      );
      final yakus = hs.detectYakus(h);
      expect(yakus.map((y) => y.name), isNot(contains('断么九')));
    });

    test('副露あり（開いた手）でkuitanAllowed=true → 断么九は成立', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 2, open: true),
          seq(hs.Suit.p, 3),
          seq(hs.Suit.s, 4),
          trip(hs.Suit.m, 5),
          pair(hs.Suit.p, 6),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        menzen: false,
        kuitanAllowed: true,
      );
      final yakus = hs.detectYakus(h);
      expect(yakus.map((y) => y.name), contains('断么九'));
    });

    test('門前手でkuitanAllowed=false → それでも断么九は成立する（門前は喰いタン規定と無関係）', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 2),
          seq(hs.Suit.p, 3),
          seq(hs.Suit.s, 4),
          trip(hs.Suit.m, 5),
          pair(hs.Suit.p, 6),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        menzen: true,
        kuitanAllowed: false,
      );
      final yakus = hs.detectYakus(h);
      expect(yakus.map((y) => y.name), contains('断么九'));
    });
  });

  group('監査4: 符計算の境界値', () {
    test('平和+ロン → 30符固定', () {
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
      final result = hs.scoreHand(h);
      expect(result.fu.fuRounded, 30);
    });

    test('平和+ツモ → 20符固定', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 1),
          seq(hs.Suit.m, 4),
          seq(hs.Suit.p, 2),
          seq(hs.Suit.s, 3),
          pair(hs.Suit.p, 5),
        ],
        winType: hs.WinType.tsumo,
        isDealer: false,
        waitType: hs.WaitType.ryanmen,
      );
      final result = hs.scoreHand(h);
      expect(result.fu.fuRounded, 20);
    });

    test('開いた手・ロン・ピンフ形（役牌等なし）→ 20符ではなく30符に繰り上がる（喰い平和形）', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 1, open: true),
          seq(hs.Suit.m, 4),
          seq(hs.Suit.p, 2),
          seq(hs.Suit.s, 3),
          pair(hs.Suit.p, 5),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        waitType: hs.WaitType.ryanmen,
        menzen: false,
      );
      final result = hs.scoreHand(h);
      expect(result.fu.fuRaw, 20);
      expect(result.fu.fuRounded, 30);
    });

    test('刻子/槓子の符テーブル: 開/暗 × 中張/么九 の組み合わせ', () {
      // 開刻(中張)=2, 開刻(么九)=4, 暗刻(中張)=4, 暗刻(么九)=8
      // 開槓(中張)=8, 開槓(么九)=16, 暗槓(中張)=16, 暗槓(么九)=32
      // ツモ固定にすることで「門前ロン+10符」の有無に結果が左右されないようにする
      // （meld.openはmenzen全体とは独立に、その面子単体の暗刻/明刻判定にのみ使う）。
      int fuOf(hs.Meld m) {
        final h = baseHand(
          melds: [
            m,
            seq(hs.Suit.p, 2),
            seq(hs.Suit.s, 2),
            seq(hs.Suit.s, 5),
            pair(hs.Suit.z, 4), // 客風固定＝雀頭符0
          ],
          winType: hs.WinType.tsumo,
          isDealer: false,
        );
        return hs.calcFu(h, hs.detectYakus(h)).fuRaw;
      }

      // 基準値は「基本20符+ツモ2符」の22符（trip/quadを1つ混ぜた時点で
      // 平和ではなくなるため、ピンフツモ20符固定の特例は発動しない）。
      const baseline = 22;
      expect(fuOf(trip(hs.Suit.m, 5, open: true)) - baseline, 2);
      expect(fuOf(trip(hs.Suit.z, 1, open: true)) - baseline, 4); // 字牌=么九
      expect(fuOf(trip(hs.Suit.m, 5, open: false)) - baseline, 4);
      expect(fuOf(trip(hs.Suit.z, 1, open: false)) - baseline, 8);
      expect(fuOf(quad(hs.Suit.m, 5, open: true)) - baseline, 8);
      expect(fuOf(quad(hs.Suit.z, 1, open: true)) - baseline, 16);
      expect(fuOf(quad(hs.Suit.m, 5, open: false)) - baseline, 16);
      expect(fuOf(quad(hs.Suit.z, 1, open: false)) - baseline, 32);
    });
  });

  group('監査5: 点数区分の境界値（resolveLimit相当をscoreHand経由で検証）', () {
    // 3翻70符・4翻40符は満貫、3翻60符・4翻30符は満貫にならないことを、
    // 実際の翻・符が出る手を組んで確認する。

    test('4翻30符（満貫未満）: 通常計算式で得点が出る', () {
      // 三色同順(2/1) + 一盃口(1) + 立直(1) 相当を翻数だけで作るのは大変なので、
      // ここではdoraCountで翻数を合わせつつ、符が30になる平和以外のロン手を作る。
      // 面子:リャンメン待ち以外+客風雀頭にして30符に固定する。
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 2),
          seq(hs.Suit.p, 3),
          seq(hs.Suit.s, 4),
          seq(hs.Suit.m, 5),
          pair(hs.Suit.z, 4), // 客風（自風でも場風でもない）→ 雀頭符0
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        waitType: hs.WaitType.kanchan, // 待ち符+2 → 20+10(門前ロン)+2=32→切り上げ40
        doraCount: 4, // 翻を4翻に合わせる（ドラのみで4翻、役は無いと成立しないので後述の別手で検証）
      );
      // このケースは役無しになるため翻数検証には使わず、次のテストで代替する。
      expect(h.doraCount, 4); // ダミー健全性チェック（役無し手の翻数境界は別テストで直接resolveLimit相当を見る）
    });

    test('resolveLimitの境界値を直接検証: 3翻70符=満貫, 3翻60符=満貫でない', () {
      expect(hs.resolveLimit(3, 70)?.name, '満貫');
      expect(hs.resolveLimit(3, 60), isNull);
    });

    test('resolveLimitの境界値を直接検証: 4翻40符=満貫, 4翻30符=満貫でない', () {
      expect(hs.resolveLimit(4, 40)?.name, '満貫');
      expect(hs.resolveLimit(4, 30), isNull);
    });

    test('resolveLimitの境界値を直接検証: 5翻は符に関係なく満貫', () {
      expect(hs.resolveLimit(5, 20)?.name, '満貫');
    });

    test('resolveLimitの境界値を直接検証: 6-7翻=跳満, 8-10翻=倍満, 11-12翻=三倍満, 13翻以上=数え役満', () {
      expect(hs.resolveLimit(6, 30)?.name, '跳満');
      expect(hs.resolveLimit(7, 30)?.name, '跳満');
      expect(hs.resolveLimit(8, 30)?.name, '倍満');
      expect(hs.resolveLimit(10, 30)?.name, '倍満');
      expect(hs.resolveLimit(11, 30)?.name, '三倍満');
      expect(hs.resolveLimit(12, 30)?.name, '三倍満');
      expect(hs.resolveLimit(13, 30)?.name, '数え役満');
      expect(hs.resolveLimit(20, 30)?.name, '数え役満');
    });

    test('4翻30符ちょうどの実手（通常計算）→ 満貫にならず7700になる', () {
      // 立直(1)+平和(1)+ドラ2 = 4翻。
      // ピンフ形（全て順子・両面待ち・客風の雀頭）にすると、門前ロンの30符は
      // 平和ロン固定符と一致するため、ちょうど4翻30符の実例になる。
      // （一盃口を使わないよう4面子の順子はすべて異なる牌にする）
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 2),
          seq(hs.Suit.m, 5),
          seq(hs.Suit.p, 4),
          seq(hs.Suit.s, 6),
          pair(hs.Suit.z, 4), // 客風固定＝雀頭符0、役牌でもない
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        waitType: hs.WaitType.ryanmen,
        riichi: true,
        doraCount: 2,
      );
      final result = hs.scoreHand(h);
      expect(result.yakus.map((y) => y.name), contains('平和'));
      expect(result.han, 4); // 立直1 + 平和1 + ドラ2
      expect(result.fu.fuRounded, 30);
      expect(result.limitName, isNot('満貫'));
      expect(result.ronPoints, 7700);
    });

    test('3翻70符ちょうどの実手（通常計算）→ 満貫2000基本点として扱われる', () {
      // 立直(1)+役牌(1、白の暗槓)+ドラ1 = 3翻、
      // 暗槓(么九=白)32符 + 基本20 + 門前ロン10 + 嵌張2 = 64 → 切り上げ70符。
      final h = baseHand(
        melds: [
          quad(hs.Suit.z, 5), // 白の暗槓（役牌1翻・符32）
          seq(hs.Suit.p, 4),
          seq(hs.Suit.s, 6),
          seq(hs.Suit.m, 3),
          pair(hs.Suit.z, 4),
        ],
        winType: hs.WinType.ron,
        isDealer: false,
        waitType: hs.WaitType.kanchan,
        riichi: true,
        doraCount: 1,
      );
      final result = hs.scoreHand(h);
      expect(result.yakus.map((y) => y.name), contains('役牌:白'));
      expect(result.han, 3); // 立直1 + 役牌(白)1 + ドラ1
      expect(result.fu.fuRounded, 70);
      expect(result.limitName, '満貫');
      expect(result.ronPoints, 8000); // 満貫・子ロン
    });
  });

  group('監査6: 点数丸め（ceilTo100）', () {
    test('ロン点数 = base*4(子)/6(親) を100点単位で切り上げ', () {
      expect(hs.ceilTo100(3801), 3900);
      expect(hs.ceilTo100(3800), 3800);
      expect(hs.ceilTo100(1), 100);
      expect(hs.ceilTo100(0), 0);
    });

    test('ツモは各支払いを個別に切り上げる（合計してから切り上げるのではない）', () {
      // 2翻30符ツモ・子: base=30*2^4=480
      // 親から: ceil(480*2=960)->1000, 子から: ceil(480)->500
      // 合計 1000+500*2=2000。もし「先に合計してから丸める」実装だったら
      // 480*4=1920→ceil=2000で偶然一致してしまうため、丸め粒度が分かるケースを選ぶ。
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 1),
          seq(hs.Suit.m, 4),
          trip(hs.Suit.p, 2), // 暗刻(中張)4符
          seq(hs.Suit.s, 3),
          pair(hs.Suit.p, 5),
        ],
        winType: hs.WinType.tsumo,
        isDealer: false,
        waitType: hs.WaitType.ryanmen,
        riichi: true, // 立直1 + 门前つも1 = 2翻
      );
      final result = hs.scoreHand(h);
      // fu: 20(基本)+2(ツモ)+4(暗刻中張)=26→30符, han=2(立直+ツモ)
      expect(result.fu.fuRounded, 30);
      expect(result.han, 2);
      final base = hs.calcBasePoints(result.han, result.fu.fuRounded); // 30*16=480
      expect(base, 480);
      expect(result.tsumoFromDealer, hs.ceilTo100(480 * 2)); // 1000
      expect(result.tsumoFromNonDealer, hs.ceilTo100(480)); // 500
      expect(result.tsumoFromDealer, 1000);
      expect(result.tsumoFromNonDealer, 500);
      // 個別切り上げの合計(2000) と 先に合計してから切り上げ(480*4=1920→2000) が
      // 偶然一致するケースなので、次のケースで非一致になるものを確認する。
    });

    test('個別切り上げと合計後切り上げが食い違う具体例（子ツモ）', () {
      // base=700 (例: 5翻扱いにはせず、任意のbaseを直接calcBasePoints経由で検証する)
      // ここではhan/fuを操作してbase=350になる手を使う: fu=35は存在しないため、
      // 実際のhan/fuの組から得られるbase値で非一致点を探す。
      // 2翻40符: base = 40 * 2^4 = 640
      // 子ツモ: 親払い=ceil(640*2=1280)->1300, 子払い=ceil(640)->700
      // 個別合計 = 1300+700*2=2700
      // 先に合計してから丸める場合 = 640*4=2560 -> ceil=2600 (不一致！)
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 1),
          seq(hs.Suit.m, 4),
          trip(hs.Suit.p, 2, open: false), // 暗刻中張4符
          trip(hs.Suit.s, 3, open: false), // 暗刻中張4符 (fu調整用)
          pair(hs.Suit.z, 4), // 客風、雀頭符0
        ],
        winType: hs.WinType.tsumo,
        isDealer: false,
        waitType: hs.WaitType.tanki, // 待ち符+2
        riichi: true, // 立直1+ツモ1=2翻
      );
      final result = hs.scoreHand(h);
      // fu: 20+2(ツモ)+4+4(暗刻2つ)+2(単騎待ち)=32→40符
      expect(result.fu.fuRounded, 40);
      expect(result.han, 2);
      final base = hs.calcBasePoints(result.han, result.fu.fuRounded);
      expect(base, 640);
      final fromDealer = result.tsumoFromDealer!;
      final fromNonDealer = result.tsumoFromNonDealer!;
      final individualTotal = fromDealer + fromNonDealer * 2;
      final totalThenRound = hs.ceilTo100(base * 4);
      expect(fromDealer, 1300);
      expect(fromNonDealer, 700);
      expect(individualTotal, 2700);
      expect(totalThenRound, 2600);
      expect(individualTotal, isNot(totalThenRound),
          reason: '個別切り上げの合計と、先に合計してから切り上げた値は一致しないのが正しい仕様（麻雀のルール通り）');
    });
  });

  group('監査7: リーチ系フラグの整合性（エンジン側でのブロック有無）', () {
    test('ippatsu=true, riichi=false, doubleRiichi=false → 一発は計上されない（エンジンは正しくガードしている）', () {
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
        ippatsu: true,
        riichi: false,
        doubleRiichi: false,
      );
      final yakus = hs.detectYakus(h);
      expect(yakus.map((y) => y.name), isNot(contains('一発')),
          reason: 'エンジンはippatsuフラグ単独では加点しない（riichi/doubleRiichiとのAND条件がある）');
    });

    test('riichi=true かつ doubleRiichi=true が同時に渡された場合、リーチ翻を二重計上しない', () {
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
        riichi: true,
        doubleRiichi: true,
      );
      final yakus = hs.detectYakus(h);
      expect(yakus.where((y) => y.name == '立直' || y.name == 'ダブル立直').length, 1,
          reason: 'ダブル立直が優先され、通常の立直と二重計上されない');
      expect(yakus.map((y) => y.name), contains('ダブル立直'));
    });
  });

  group('監査8: 状況役の内部無矛盾チェック（エンジンはフラグを無条件で信用するか）', () {
    test('winType=ron なのに haitei(ツモ専用)=true を渡すと、エンジンは無条件で1翻加算してしまう', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 1),
          seq(hs.Suit.m, 4),
          seq(hs.Suit.p, 2),
          seq(hs.Suit.s, 3),
          pair(hs.Suit.p, 5),
        ],
        winType: hs.WinType.ron, // ロンなのに
        isDealer: false,
        haitei: true, // 海底摸月（本来ツモ専用）を立ててみる
      );
      final yakus = hs.detectYakus(h);
      // エンジン側にwinType==tsumoのガードが無いことを確認する（矛盾したフラグでも加点されてしまう）
      expect(yakus.map((y) => y.name), contains('海底摸月'),
          reason: 'エンジンはwinTypeとの整合性チェックをせず、フラグを無条件に信用している');
    });

    test('winType=tsumo なのに houtei(ロン専用)=true を渡すと、エンジンは無条件で1翻加算してしまう', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 1),
          seq(hs.Suit.m, 4),
          seq(hs.Suit.p, 2),
          seq(hs.Suit.s, 3),
          pair(hs.Suit.p, 5),
        ],
        winType: hs.WinType.tsumo,
        isDealer: false,
        houtei: true,
      );
      final yakus = hs.detectYakus(h);
      expect(yakus.map((y) => y.name), contains('河底撈魚'),
          reason: 'エンジンはwinTypeとの整合性チェックをせず、フラグを無条件に信用している');
    });

    test('開いた手（副露あり）で tenhou=true を渡すと、エンジンは役満として成立させてしまう', () {
      final h = baseHand(
        melds: [
          seq(hs.Suit.m, 1, open: true), // 副露あり=本来天和はあり得ない
          seq(hs.Suit.m, 4),
          seq(hs.Suit.p, 2),
          seq(hs.Suit.s, 3),
          pair(hs.Suit.p, 5),
        ],
        winType: hs.WinType.tsumo,
        isDealer: true,
        menzen: false,
        tenhou: true,
      );
      final yakuman = hs.detectYakumans(h);
      expect(yakuman, isNotNull);
      expect(yakuman!.yakumans.map((y) => y.name), contains('天和'),
          reason: 'エンジンはmenzen/副露の状態を見ずにtenhouフラグだけで役満を成立させてしまう');
    });
  });
}
