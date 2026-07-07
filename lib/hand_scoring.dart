// lib/hand_scoring.dart
import 'dart:math';

enum Suit { m, p, s, z } // man, pin, sou, honors
enum MeldType { sequence, triplet, quad, pair }
enum QuadKind { none, open, closed }
enum WinType { ron, tsumo }
enum WaitType { ryanmen, kanchan, penchan, tanki, shanpon }

class Tile {
  final Suit suit;
  final int rank; // m/p/s: 1-9, z: 1-7 (1=E,2=S,3=W,4=N,5=White,6=Green,7=Red)
  const Tile(this.suit, this.rank);

  bool get isHonor => suit == Suit.z;
  bool get isTerminal => !isHonor && (rank == 1 || rank == 9);
  bool get isYaochu => isHonor || isTerminal;
  bool get isSimple => !isHonor && rank >= 2 && rank <= 8;

  @override
  String toString() => '${suit.name}$rank';

  @override
  bool operator ==(Object other) => other is Tile && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => Object.hash(suit, rank);
}

class Meld {
  final MeldType type;
  final List<Tile> tiles;
  final bool open;
  final QuadKind quadKind;

  const Meld({
    required this.type,
    required this.tiles,
    required this.open,
    this.quadKind = QuadKind.none,
  });

  bool get isSequence => type == MeldType.sequence;
  bool get isTriplet => type == MeldType.triplet;
  bool get isQuad => type == MeldType.quad;
  bool get isPair => type == MeldType.pair;

  Tile get baseTile => tiles.first;
}

class HandInput {
  final List<Meld> melds; // 通常: 5 items (4 melds + 1 pair) / 七対子: 7 pairs
  final Tile winTile; // UIで非表示でも内部で必要ならダミーでOK
  final WaitType waitType;

  final WinType winType;
  final bool isDealer;

  final int seatWind; // 1..4
  final int roundWind; // 1..4

  final bool riichi;
  final bool doubleRiichi;
  final bool ippatsu;

  final bool menzen;

  final int doraCount;
  final int akaDoraCount;
  final int uraDoraCount;

  final bool isChiitoi;

  // 追加：喰いタン許可
  final bool kuitanAllowed;

  // 追加：状況役
  final bool haitei;  // 海底摸月（ツモ）
  final bool houtei;  // 河底撈魚（ロン）
  final bool rinshan; // 嶺上開花（ツモ）
  final bool chankan; // 槍槓（ロン）

  // 追加（役満タスク1）：天和・地和
  final bool tenhou;  // 親の配牌時ツモ和了
  final bool chiihou; // 子の第一巡ツモ和了

  // 追加（役満タスク1）：国士無双
  // 通常の「4面子+雀頭」/「7対子」というMeld構造では表現できない特殊形のため、
  // フラグで入力されたことを示す。true の場合、melds の形状バリデーションはスキップする。
  final bool isKokushi;
  // 国士無双の十三面待ち（13種全てが2枚以上の状態での和了）＝ダブル役満。
  // isKokushi が true の場合のみ意味を持つ。
  final bool kokushi13Wait;

  // 追加（タスク2）：ロンで完成した面子/雀頭を判定するための、melds配列内インデックス。
  // -1 は「未指定（対象外）」を意味し、その場合は従来通り open フラグのみで暗刻/明刻を判定する。
  final int winningMeldIndex;

  HandInput({
    required this.melds,
    required this.winTile,
    required this.waitType,
    required this.winType,
    required this.isDealer,
    required this.seatWind,
    required this.roundWind,
    required this.riichi,
    required this.doubleRiichi,
    required this.ippatsu,
    required this.menzen,
    required this.doraCount,
    required this.akaDoraCount,
    required this.uraDoraCount,
    required this.isChiitoi,
    required this.kuitanAllowed,
    required this.haitei,
    required this.houtei,
    required this.rinshan,
    required this.chankan,
    this.tenhou = false,
    this.chiihou = false,
    this.isKokushi = false,
    this.kokushi13Wait = false,
    this.winningMeldIndex = -1,
  }) {
    if (seatWind < 1 || seatWind > 4) throw ArgumentError('seatWind 1..4');
    if (roundWind < 1 || roundWind > 4) throw ArgumentError('roundWind 1..4');

    // 国士無双は通常のMeld構造で表現できないため、形状バリデーションの対象外とする。
    if (!isKokushi) {
      if (!isChiitoi) {
        if (melds.length != 5) throw ArgumentError('melds must be 5 items');
        final pairCount = melds.where((m) => m.isPair).length;
        if (pairCount != 1) throw ArgumentError('must include exactly 1 pair');
      } else {
        if (melds.length != 7) throw ArgumentError('chiitoi melds must be 7 pairs');
        if (!melds.every((m) => m.isPair)) throw ArgumentError('chiitoi must be all pairs');
      }
    }
  }
}

class Yaku {
  final String name;
  final int hanClosed;
  final int hanOpen;
  final bool yakuman;
  const Yaku(this.name, this.hanClosed, this.hanOpen, {this.yakuman = false});
  int han(bool menzen) => menzen ? hanClosed : hanOpen;
}

class BreakdownItem {
  final String label;
  final int value;
  const BreakdownItem(this.label, this.value);
}

class FuResult {
  final int fuRaw;
  final int fuRounded;
  final List<BreakdownItem> items;
  const FuResult(this.fuRaw, this.fuRounded, this.items);
}

class ScoreResult {
  final List<Yaku> yakus;
  final int han;
  final FuResult fu;
  final int? ronPoints;
  final int? tsumoFromDealer;
  final int? tsumoFromNonDealer;
  final String limitName;
  // 役満タスク1で追加：役満の合計倍率（通常役の手では0）
  final int yakumanMultiplier;
  const ScoreResult({
    required this.yakus,
    required this.han,
    required this.fu,
    required this.ronPoints,
    required this.tsumoFromDealer,
    required this.tsumoFromNonDealer,
    required this.limitName,
    this.yakumanMultiplier = 0,
  });
}

int ceilTo100(int x) => ((x + 99) ~/ 100) * 100;

bool isValueHonor(Tile t, int seatWind, int roundWind) {
  if (!t.isHonor) return false;
  if (t.rank >= 5 && t.rank <= 7) return true; // dragons
  if (t.rank == seatWind) return true;
  if (t.rank == roundWind) return true;
  return false;
}

Meld pairOf(HandInput h) => h.melds.firstWhere((m) => m.isPair);
List<Meld> groupsOf(HandInput h) => h.melds.where((m) => !m.isPair).toList();

bool _isTerminal(Tile t) => !t.isHonor && (t.rank == 1 || t.rank == 9);
bool _isYaochu(Tile t) => t.isHonor || _isTerminal(t);

bool _meldHasYaochu(Meld m) => m.tiles.any(_isYaochu);
bool _meldHasTerminal(Meld m) => m.tiles.any(_isTerminal);

bool _handHasHonor(HandInput h) => h.melds.any((m) => m.tiles.any((t) => t.isHonor));
bool _handHasSequence(HandInput h) => groupsOf(h).any((m) => m.isSequence);

bool _allTilesAreYaochu(HandInput h) => h.melds.expand((m) => m.tiles).every(_isYaochu);

bool _isTripletOrQuad(Meld m) => m.isTriplet || m.isQuad;

bool isAllSimples(HandInput h) {
  for (final m in h.melds) {
    for (final t in m.tiles) {
      if (!t.isSimple) return false;
    }
  }
  return true;
}

bool isPinfuCandidate(HandInput h) {
  if (!h.menzen) return false;
  if (h.waitType != WaitType.ryanmen) return false;
  if (!groupsOf(h).every((m) => m.isSequence)) return false;

  final pairTile = pairOf(h).tiles.first;
  if (pairTile.isHonor && isValueHonor(pairTile, h.seatWind, h.roundWind)) {
    return false;
  }
  return true;
}

bool _isClosedSet(Meld m) {
  if (m.isTriplet) return !m.open;
  if (m.isQuad) return (m.quadKind == QuadKind.closed) || (!m.open);
  return false;
}

/// タスク2：ロンで完成させた面子は、手牌全体が門前でも「明刻」として扱う。
/// - ツモの場合: 常に open フラグのみで暗刻/明刻を判定する（自摸は常に暗刻扱い）。
/// - ロンかつ、この面子が winningMeldIndex（和了牌で完成した面子）と一致し、
///   かつ刻子（isTriplet）の場合: open フラグに関わらず明刻として扱う。
///   （待ちが単騎の場合、和了牌が完成させるのは雀頭であり、この面子のindexとは
///   一致しないため、暗刻のまま扱われる。シャンポン待ちの場合はどちらか一方の
///   刻子の index が winningMeldIndex と一致し、その面子だけが明刻になる。）
/// - それ以外は従来通り open フラグで判定。
bool _isConcealedAt(HandInput h, int meldIndex, Meld m) {
  if (!(m.isTriplet || m.isQuad)) return false;
  if (h.winType == WinType.ron && m.isTriplet && meldIndex == h.winningMeldIndex) {
    return false;
  }
  return _isClosedSet(m);
}

/// 手牌全体における暗刻/暗槓の数（三暗刻・四暗刻の判定に使用）。
/// melds配列のインデックスを保ったまま走査する必要があるため groupsOf(h) は使わない。
int _concealedTripletOrQuadCount(HandInput h) {
  int count = 0;
  for (int i = 0; i < h.melds.length; i++) {
    final m = h.melds[i];
    if (!_isTripletOrQuad(m)) continue;
    if (_isConcealedAt(h, i, m)) count++;
  }
  return count;
}

Set<Suit> _numberSuitsUsed(HandInput h) {
  final s = <Suit>{};
  for (final m in h.melds) {
    for (final t in m.tiles) {
      if (!t.isHonor) s.add(t.suit);
    }
  }
  return s;
}

bool _hasHonor(HandInput h) => h.melds.any((m) => m.tiles.any((t) => t.isHonor));

Map<String, int> _sequenceKeyCounts(HandInput h) {
  // key例: "m1" (萬1-2-3の順子)
  final map = <String, int>{};
  for (final m in groupsOf(h)) {
    if (!m.isSequence) continue;
    final suit = m.tiles.first.suit;
    final start = m.tiles.first.rank; // tilesが昇順である前提
    final key = '${suit.name}$start';
    map[key] = (map[key] ?? 0) + 1;
  }
  return map;
}

Map<int, Set<Suit>> _tripletRankSuits(HandInput h) {
  // rank -> {m,p,s} （字牌は除外）
  final map = <int, Set<Suit>>{};
  for (final m in groupsOf(h)) {
    if (!(_isTripletOrQuad(m))) continue;
    final t = m.tiles.first;
    if (t.isHonor) continue;
    map.putIfAbsent(t.rank, () => <Suit>{}).add(t.suit);
  }
  return map;
}

/// ===== 役判定（役満以外）=====
List<Yaku> detectYakus(HandInput h) {
  final out = <Yaku>[];

  // =========================
  // 七対子（ここで完結）
  // =========================
  if (h.isChiitoi) {
    out.add(const Yaku('七対子', 2, 2));

    // 立直系
    if (h.doubleRiichi) out.add(const Yaku('ダブル立直', 2, 0));
    else if (h.riichi) out.add(const Yaku('立直', 1, 0));
    if ((h.riichi || h.doubleRiichi) && h.ippatsu) {
      out.add(const Yaku('一発', 1, 0));
    }

    // 門前ツモ
    if (h.winType == WinType.tsumo) {
      out.add(const Yaku('門前清自摸和', 1, 0));
    }

    // 状況役
    if (h.haitei) out.add(const Yaku('海底摸月', 1, 1));
    if (h.houtei) out.add(const Yaku('河底撈魚', 1, 1));
    if (h.rinshan) out.add(const Yaku('嶺上開花', 1, 1));
    if (h.chankan) out.add(const Yaku('槍槓', 1, 1));

    // 断么九（七対子でも成立）
    if (isAllSimples(h)) {
      out.add(const Yaku('断么九', 1, 1));
    }

    return out; // ← 七対子はここで終了
  }

  // =========================
  // 以下は「面子手専用」
  // =========================

  // 立直系
  if (h.doubleRiichi) out.add(const Yaku('ダブル立直', 2, 0));
  else if (h.riichi) out.add(const Yaku('立直', 1, 0));
  if ((h.riichi || h.doubleRiichi) && h.ippatsu) {
    out.add(const Yaku('一発', 1, 0));
  }

  // 門前ツモ
  if (h.menzen && h.winType == WinType.tsumo) {
    out.add(const Yaku('門前清自摸和', 1, 0));
  }

  // 状況役
  if (h.haitei) out.add(const Yaku('海底摸月', 1, 1));
  if (h.houtei) out.add(const Yaku('河底撈魚', 1, 1));
  if (h.rinshan) out.add(const Yaku('嶺上開花', 1, 1));
  if (h.chankan) out.add(const Yaku('槍槓', 1, 1));

  // 断么九（喰いタン考慮）
  if (isAllSimples(h)) {
    if (h.menzen || h.kuitanAllowed) {
      out.add(const Yaku('断么九', 1, 1));
    }
  }

  // 平和
  if (isPinfuCandidate(h)) {
    out.add(const Yaku('平和', 1, 0));
  }

  // 一盃口 / 二盃口（門前限定）
  // 同一順子が4面子分（1つのキーに4回）出現するレアケースでも、
  // 2組の一盃口として二盃口が成立するように c ~/ 2 で組数を数える。
  if (h.menzen) {
    final seq = _sequenceKeyCounts(h);
    int pairs = 0;
    for (final c in seq.values) {
      pairs += c ~/ 2;
    }
    if (pairs >= 2) out.add(const Yaku('二盃口', 3, 0));
    else if (pairs == 1) out.add(const Yaku('一盃口', 1, 0));
  }

  final groups = groupsOf(h);

  // 役牌
  for (final m in groups) {
    if (m.isTriplet || m.isQuad) {
      final t = m.baseTile;
      if (t.isHonor && isValueHonor(t, h.seatWind, h.roundWind)) {
        // 連風牌（自風と場風が同じ牌。例: 親の東場東）の場合は、
        // 「役牌:自風」と「役牌:場風」の両方が成立し、2翻になる。
        // ここを else if にすると連風牌のときに片方しか計上されなくなるため、
        // 自風・場風は独立した if で判定する（風牌以外の三元牌とは排他）。
        if (t.rank == h.seatWind) out.add(const Yaku('役牌:自風', 1, 1));
        if (t.rank == h.roundWind) out.add(const Yaku('役牌:場風', 1, 1));
        if (t.rank == 5) out.add(const Yaku('役牌:白', 1, 1));
        if (t.rank == 6) out.add(const Yaku('役牌:發', 1, 1));
        if (t.rank == 7) out.add(const Yaku('役牌:中', 1, 1));
      }
    }
  }

  // 対々和
  if (groups.every(_isTripletOrQuad)) {
    out.add(const Yaku('対々和', 2, 2));
  }

  // 三暗刻（ロンで完成した刻子は明刻としてカウントから除外する）
  final concealed = _concealedTripletOrQuadCount(h);
  if (concealed >= 3) {
    out.add(const Yaku('三暗刻', 2, 2));
  }

  // 混一色 / 清一色
  final suits = _numberSuitsUsed(h);
  final hasHonor = _hasHonor(h);
  if (suits.length == 1) {
    if (hasHonor) out.add(const Yaku('混一色', 3, 2));
    else out.add(const Yaku('清一色', 6, 5));
  }

  // 一気通貫
  final seq = _sequenceKeyCounts(h);
  bool hasIttsu(Suit s) =>
      (seq['${s.name}1'] ?? 0) > 0 &&
      (seq['${s.name}4'] ?? 0) > 0 &&
      (seq['${s.name}7'] ?? 0) > 0;
  if (hasIttsu(Suit.m) || hasIttsu(Suit.p) || hasIttsu(Suit.s)) {
    out.add(const Yaku('一気通貫', 2, 1));
  }

  // 三色同順
  for (int i = 1; i <= 7; i++) {
    if ((seq['m$i'] ?? 0) > 0 &&
        (seq['p$i'] ?? 0) > 0 &&
        (seq['s$i'] ?? 0) > 0) {
      out.add(const Yaku('三色同順', 2, 1));
      break;
    }
  }

  // 三色同刻
  final map = _tripletRankSuits(h);
  if (map.values.any((s) =>
      s.contains(Suit.m) && s.contains(Suit.p) && s.contains(Suit.s))) {
    out.add(const Yaku('三色同刻', 2, 2));
  }

  // 混老頭
  if (_allTilesAreYaochu(h) && groups.every((m) => !m.isSequence)) {
    out.add(const Yaku('混老頭', 2, 2));
  }

  // チャンタ
  if (h.melds.every(_meldHasYaochu) &&
      _handHasSequence(h) &&
      _handHasHonor(h)) {
    out.add(const Yaku('チャンタ', 2, 1));
  }

  // 純チャン
  if (h.melds.every(_meldHasTerminal) &&
      _handHasSequence(h) &&
      !_handHasHonor(h)) {
    out.add(const Yaku('純チャン', 3, 2));
  }

  // 小三元
  bool isDragon(Tile t) => t.isHonor && t.rank >= 5 && t.rank <= 7;
  final dragonTrip =
      groups.where((m) => _isTripletOrQuad(m) && isDragon(m.baseTile)).length;
  if (dragonTrip >= 2 && isDragon(pairOf(h).tiles.first)) {
    out.add(const Yaku('小三元', 2, 2));
  }

  // 三槓子
  if (groups.where((m) => m.isQuad).length >= 3) {
    out.add(const Yaku('三槓子', 2, 2));
  }

  return out;
}


/// ===== 役満判定 =====
class YakumanResult {
  final List<Yaku> yakumans; // 成立した役満のリスト（複数成立＝複合）
  final int multiplier; // 合計倍率（通常役満=1、ダブル役満=2 として合算）
  const YakumanResult(this.yakumans, this.multiplier);
}

bool _isWind(Tile t) => t.isHonor && t.rank >= 1 && t.rank <= 4;
bool _isDragon(Tile t) => t.isHonor && t.rank >= 5 && t.rank <= 7;

bool _hasDaisangen(HandInput h) {
  final dragonTriplets = groupsOf(h)
      .where((m) => _isTripletOrQuad(m) && _isDragon(m.baseTile))
      .map((m) => m.baseTile.rank)
      .toSet();
  return dragonTriplets.length == 3;
}

bool _hasShousuushi(HandInput h) {
  final windTriplets = groupsOf(h)
      .where((m) => _isTripletOrQuad(m) && _isWind(m.baseTile))
      .map((m) => m.baseTile.rank)
      .toSet();
  return windTriplets.length == 3 && _isWind(pairOf(h).tiles.first);
}

bool _hasDaisuushi(HandInput h) {
  final windTriplets = groupsOf(h)
      .where((m) => _isTripletOrQuad(m) && _isWind(m.baseTile))
      .map((m) => m.baseTile.rank)
      .toSet();
  return windTriplets.length == 4;
}

bool _hasTsuuiisou(HandInput h) =>
    h.melds.expand((m) => m.tiles).every((t) => t.isHonor);

bool _hasChinroutou(HandInput h) {
  final allTerminal =
      h.melds.expand((m) => m.tiles).every((t) => !t.isHonor && (t.rank == 1 || t.rank == 9));
  return allTerminal && groupsOf(h).every(_isTripletOrQuad);
}

bool _isGreenTile(Tile t) {
  if (t.isHonor) return t.rank == 6; // 發
  return t.suit == Suit.s && const {2, 3, 4, 6, 8}.contains(t.rank);
}

bool _hasRyuuiisou(HandInput h) =>
    h.melds.expand((m) => m.tiles).every(_isGreenTile);

bool _hasSuukantsu(HandInput h) => groupsOf(h).where((m) => m.isQuad).length == 4;

/// 四暗刻の判定。戻り値: 0=不成立, 1=四暗刻, 2=四暗刻単騎（ダブル役満）
/// ロンでシャンポン待ちを完成させた場合、その刻子は明刻扱いとなり暗刻数が3以下になるため
/// 自動的に不成立となる（_concealedTripletOrQuadCount が winningMeldIndex を考慮する）。
int _suuankouLevel(HandInput h) {
  final closedCount = _concealedTripletOrQuadCount(h);
  if (closedCount != 4) return 0;
  return h.waitType == WaitType.tanki ? 2 : 1;
}

/// 九蓮宝燈の判定。戻り値: 0=不成立, 1=九蓮宝燈, 2=純正九蓮宝燈（ダブル役満）
/// 清一色かつ 1112345678999 の13枚（＋和了牌1枚）という特殊形を、
/// 面子構造ではなく手牌全体のタイル集合から判定する。
int _chuurenLevel(HandInput h) {
  if (!h.menzen) return 0;
  if (h.melds.any((m) => m.isQuad)) return 0;

  final tiles = h.melds.expand((m) => m.tiles).toList();
  if (tiles.length != 14) return 0;

  final suits = tiles.map((t) => t.suit).toSet();
  if (suits.length != 1 || suits.first == Suit.z) return 0;
  final suit = suits.first;

  final counts = List<int>.filled(10, 0); // index 1..9
  for (final t in tiles) counts[t.rank]++;

  final base = counts[1] >= 3 &&
      counts[9] >= 3 &&
      const [2, 3, 4, 5, 6, 7, 8].every((r) => counts[r] >= 1);
  if (!base) return 0;

  if (h.winTile.suit != suit || counts[h.winTile.rank] <= 0) return 1;

  final withoutWin = List<int>.from(counts);
  withoutWin[h.winTile.rank] -= 1;
  final pureShape = withoutWin[1] == 3 &&
      withoutWin[9] == 3 &&
      const [2, 3, 4, 5, 6, 7, 8].every((r) => withoutWin[r] == 1);
  return pureShape ? 2 : 1;
}

YakumanResult? detectYakumans(HandInput h) {
  final yakumans = <Yaku>[];
  int multiplier = 0;

  void add(String name, {bool isDouble = false}) {
    yakumans.add(Yaku(name, 0, 0, yakuman: true));
    multiplier += isDouble ? 2 : 1;
  }

  // 天和・地和（手の形によらず成立しうる状況役満）
  if (h.tenhou) add('天和');
  if (h.chiihou) add('地和');

  // 国士無双（通常のMeld構造では表現不可のため専用フラグで判定）
  if (h.isKokushi) {
    add('国士無双', isDouble: h.kokushi13Wait);
    return YakumanResult(yakumans, multiplier);
  }

  if (h.isChiitoi) {
    // 七対子の構造上、刻子系の役満（大三元・四暗刻等）は成立しえないため字一色のみ判定
    if (_hasTsuuiisou(h)) add('字一色');
    if (yakumans.isEmpty) return null;
    return YakumanResult(yakumans, multiplier);
  }

  // ここから「4面子+雀頭」構造専用の役満
  if (_hasDaisangen(h)) add('大三元');

  if (_hasDaisuushi(h)) {
    add('大四喜', isDouble: true);
  } else if (_hasShousuushi(h)) {
    add('小四喜');
  }

  if (_hasTsuuiisou(h)) add('字一色');
  if (_hasChinroutou(h)) add('清老頭');
  if (_hasRyuuiisou(h)) add('緑一色');
  if (_hasSuukantsu(h)) add('四槓子');

  final chuuren = _chuurenLevel(h);
  if (chuuren == 2) {
    add('純正九蓮宝燈', isDouble: true);
  } else if (chuuren == 1) {
    add('九蓮宝燈');
  }

  final suuankou = _suuankouLevel(h);
  if (suuankou == 2) {
    add('四暗刻単騎', isDouble: true);
  } else if (suuankou == 1) {
    add('四暗刻');
  }

  if (yakumans.isEmpty) return null;
  return YakumanResult(yakumans, multiplier);
}

const Map<int, List<int>> _yakumanPointTable = {
  // multiplier: [ronNonDealer, ronDealer, tsumoFromDealer, tsumoFromNonDealer, tsumoDealerAll]
  1: [32000, 48000, 16000, 8000, 16000],
  2: [64000, 96000, 32000, 16000, 32000],
  3: [96000, 144000, 48000, 24000, 48000],
};

List<int> _yakumanPoints(int multiplier) {
  final row = _yakumanPointTable[multiplier];
  if (row != null) return row;
  // 4倍役満以上：1倍テーブルの倍率をそのまま乗じる
  final base = _yakumanPointTable[1]!;
  return base.map((p) => p * multiplier).toList();
}

ScoreResult _scoreYakumanHand(HandInput h, YakumanResult yakumanResult) {
  final points = _yakumanPoints(yakumanResult.multiplier);
  int? ronPoints;
  int? tsumoFromDealer;
  int? tsumoFromNonDealer;

  if (h.winType == WinType.ron) {
    ronPoints = h.isDealer ? points[1] : points[0];
  } else {
    if (h.isDealer) {
      tsumoFromDealer = points[4];
      tsumoFromNonDealer = points[4];
    } else {
      tsumoFromDealer = points[2];
      tsumoFromNonDealer = points[3];
    }
  }

  return ScoreResult(
    yakus: yakumanResult.yakumans,
    han: 13 * yakumanResult.multiplier, // 表示用の目安。役満点数はhan/fuに依存しない
    fu: const FuResult(0, 0, [BreakdownItem('役満（符計算対象外）', 0)]),
    ronPoints: ronPoints,
    tsumoFromDealer: tsumoFromDealer,
    tsumoFromNonDealer: tsumoFromNonDealer,
    limitName: limitLabel(han: 0, fuRounded: 0, yakumanMultiplier: yakumanResult.multiplier),
    yakumanMultiplier: yakumanResult.multiplier,
  );
}

/// ===== 符計算 =====
FuResult calcFu(HandInput h, List<Yaku> yakus) {
  final items = <BreakdownItem>[];

  // 七対子
  if (h.isChiitoi) {
    return const FuResult(25, 25, [BreakdownItem('七対子（25符固定）', 25)]);
  }

  final hasPinfu = yakus.any((y) => y.name == '平和');
  if (hasPinfu && h.winType == WinType.tsumo) {
    return const FuResult(20, 20, [BreakdownItem('平和ツモ（20符固定）', 20)]);
  }

  int fu = 20;
  items.add(const BreakdownItem('基本符', 20));

  if (h.winType == WinType.ron && h.menzen) {
    fu += 10;
    items.add(const BreakdownItem('門前ロン', 10));
  }

  if (h.winType == WinType.tsumo) {
    fu += 2;
    items.add(const BreakdownItem('ツモ符', 2));
  }

  // 待ち符（両面0、嵌張/辺張/単騎/シャンポン2）
  final waitFu = (h.waitType == WaitType.kanchan ||
          h.waitType == WaitType.penchan ||
          h.waitType == WaitType.tanki ||
          h.waitType == WaitType.shanpon)
      ? 2
      : 0;
  if (waitFu > 0) {
    fu += waitFu;
    items.add(BreakdownItem('待ち（${h.waitType.name}）', waitFu));
  }

  // 雀頭符（役牌）
  final pairTile = pairOf(h).tiles.first;
  if (pairTile.isHonor) {
    int pairFu = 0;
    if (pairTile.rank == h.seatWind) pairFu += 2;
    if (pairTile.rank == h.roundWind) pairFu += 2;
    if (pairTile.rank >= 5 && pairTile.rank <= 7) pairFu += 2;
    if (pairFu > 0) {
      fu += pairFu;
      items.add(BreakdownItem('雀頭（役牌）', pairFu));
    }
  }

  // 刻子/槓子符
  // ロンで完成した刻子は、手牌全体が門前でも明刻として扱う（_isConcealedAt が判定）。
  for (int i = 0; i < h.melds.length; i++) {
    final m = h.melds[i];
    if (!(m.isTriplet || m.isQuad)) continue;
    final yaochu = m.baseTile.isYaochu;
    final closed = _isConcealedAt(h, i, m);

    if (m.isTriplet) {
      final add = (!closed && !yaochu) ? 2 : (!closed && yaochu) ? 4 : (closed && !yaochu) ? 4 : 8;
      fu += add;
      items.add(BreakdownItem('刻子（${closed ? "暗" : "明"}・${yaochu ? "么九" : "中張"}）', add));
    } else {
      final add = (!closed && !yaochu) ? 8 : (!closed && yaochu) ? 16 : (closed && !yaochu) ? 16 : 32;
      fu += add;
      items.add(BreakdownItem('槓子（${closed ? "暗" : "明"}・${yaochu ? "么九" : "中張"}）', add));
    }
  }

  int rounded = fu;

  // 20符ロンは実戦上発生しない（平和ロンは30符になる）
  if (rounded == 20 && h.winType == WinType.ron) {
    items.add(const BreakdownItem('ロンの最低符（20→30）', 0));
    return FuResult(fu, 30, items);
  }

  // 通常は10符切り上げ
  rounded = ((rounded + 9) ~/ 10) * 10;
  return FuResult(fu, rounded, items);
}

int calcHan(HandInput h, List<Yaku> yakus) {
  int han = 0;
  for (final y in yakus) {
    if (y.yakuman) continue;
    han += y.han(h.menzen);
  }
  han += h.doraCount + h.akaDoraCount + h.uraDoraCount;
  return han;
}

class LimitBase {
  final String name;
  final int basePoints;
  const LimitBase(this.name, this.basePoints);
}

LimitBase? resolveLimit(int han, int fuRounded) {
  if (han >= 13) return const LimitBase('数え役満', 8000);
  if (han >= 11) return const LimitBase('三倍満', 6000);
  if (han >= 8) return const LimitBase('倍満', 4000);
  if (han >= 6) return const LimitBase('跳満', 3000);
  if (han == 5) return const LimitBase('満貫', 2000);
  if (han == 4 && fuRounded >= 40) return const LimitBase('満貫', 2000);
  if (han == 3 && fuRounded >= 70) return const LimitBase('満貫', 2000);
  return null;
}

int calcBasePoints(int han, int fuRounded) {
  final limit = resolveLimit(han, fuRounded);
  if (limit != null) return limit.basePoints;
  return fuRounded * (1 << (han + 2));
}

String limitLabel({
  required int han,
  required int fuRounded,
  required int yakumanMultiplier, // 0なら通常手
}) {
  if (yakumanMultiplier > 0) return yakumanMultiplier == 1 ? '役満' : '${yakumanMultiplier}倍役満';
  if (han >= 13) return '数え役満';
  if (han >= 11) return '三倍満';
  if (han >= 8) return '倍満';
  if (han >= 6) return '跳満';
  if (han >= 5) return '満貫';
  if (han == 4 && fuRounded >= 40) return '満貫';
  if (han == 3 && fuRounded >= 70) return '満貫';
  return '';
}

ScoreResult scoreHand(HandInput h) {
  final yakumanResult = detectYakumans(h);
  if (yakumanResult != null) {
    return _scoreYakumanHand(h, yakumanResult);
  }

  final yakus = detectYakus(h);
  final han = calcHan(h, yakus);
  final fu = calcFu(h, yakus);

  final base = calcBasePoints(han, fu.fuRounded);

  int? ronPoints;
  int? tsumoFromDealer;
  int? tsumoFromNonDealer;

  if (h.winType == WinType.ron) {
    final mult = h.isDealer ? 6 : 4;
    ronPoints = ceilTo100(base * mult);
  } else {
    if (h.isDealer) {
      final pay = ceilTo100(base * 2);
      tsumoFromDealer = pay;
      tsumoFromNonDealer = pay;
    } else {
      tsumoFromDealer = ceilTo100(base * 2);
      tsumoFromNonDealer = ceilTo100(base);
    }
  }

  return ScoreResult(
    yakus: yakus,
    han: han,
    fu: fu,
    ronPoints: ronPoints,
    tsumoFromDealer: tsumoFromDealer,
    tsumoFromNonDealer: tsumoFromNonDealer,
    limitName: limitLabel(han: han, fuRounded: fu.fuRounded, yakumanMultiplier: 0),
  );
}