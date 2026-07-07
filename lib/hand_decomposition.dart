// lib/hand_decomposition.dart
//
// 「14枚（または副露を除いた残り枚数）の牌をまとめてタップするだけで、
//  面子・雀頭・待ちの種類を自動判定してくれる」ための自動組み立てエンジン。
//
// 従来の meld_input.dart は「面子1」「面子2」…という単位でユーザー自身が
// 順子/刻子/雀頭を手動で分類して入力する必要があったが、これは麻雀のルールを
// 理解していない初心者には負担が大きい。本モジュールは、平坦なタイル集合
// （手牌14枚 + 副露があればその面子）から、ルール上あり得る全ての分解パターンを
// 列挙し、それぞれを hand_scoring.dart の scoreHand() で採点したうえで、
// 最も点数が高くなる解釈を採用する。
//
// これは実際の麻雀のルールである「高点法」（複数の和了形の解釈が可能な場合、
// 最も点数が高くなる解釈を採用する）をそのままアルゴリズムに落とし込んだもの。

import 'hand_scoring.dart' as hs;

enum _GroupType { sequence, triplet, pair }

class _Group {
  final _GroupType type;
  final hs.Suit suit;
  final int start; // sequence: 先頭の数牌rank / triplet・pair: そのrank
  const _Group(this.type, this.suit, this.start);

  List<hs.Tile> tiles() {
    switch (type) {
      case _GroupType.sequence:
        return [
          hs.Tile(suit, start),
          hs.Tile(suit, start + 1),
          hs.Tile(suit, start + 2),
        ];
      case _GroupType.triplet:
        return List<hs.Tile>.filled(3, hs.Tile(suit, start));
      case _GroupType.pair:
        return List<hs.Tile>.filled(2, hs.Tile(suit, start));
    }
  }

  hs.Meld toMeld() {
    final meldType = switch (type) {
      _GroupType.sequence => hs.MeldType.sequence,
      _GroupType.triplet => hs.MeldType.triplet,
      _GroupType.pair => hs.MeldType.pair,
    };
    return hs.Meld(type: meldType, tiles: tiles(), open: false);
  }

  /// この組がwinningTileと同じ(suit, rank)の牌を含むかどうか。
  bool containsRankSuit(hs.Suit s, int rank) {
    if (suit != s) return false;
    if (type == _GroupType.sequence) {
      return rank >= start && rank <= start + 2;
    }
    return rank == start;
  }

  /// 一意な文字列キー（重複排除・ソート用）。
  String get _canonicalPart => '${type.index}-${suit.index}-$start';
}

/// 1スート分のカウント配列を、順子/刻子だけで（雀頭を除いた状態で）
/// 完全に分解できる全パターンを再帰的に列挙する。
/// [counts] は index=rankのタイル枚数配列（0番はダミー、未使用）。
List<List<_Group>> _decomposeSuitFull(
  List<int> counts,
  hs.Suit suit,
  bool allowSequence,
) {
  int r = -1;
  for (int i = 1; i < counts.length; i++) {
    if (counts[i] > 0) {
      r = i;
      break;
    }
  }
  if (r == -1) return [<_Group>[]];

  final results = <List<_Group>>[];

  // 刻子として消費
  if (counts[r] >= 3) {
    final next = List<int>.from(counts);
    next[r] -= 3;
    for (final sub in _decomposeSuitFull(next, suit, allowSequence)) {
      results.add([_Group(_GroupType.triplet, suit, r), ...sub]);
    }
  }

  // 順子として消費（数牌のみ）
  if (allowSequence &&
      r + 2 < counts.length &&
      counts[r + 1] > 0 &&
      counts[r + 2] > 0) {
    final next = List<int>.from(counts);
    next[r] -= 1;
    next[r + 1] -= 1;
    next[r + 2] -= 1;
    for (final sub in _decomposeSuitFull(next, suit, allowSequence)) {
      results.add([_Group(_GroupType.sequence, suit, r), ...sub]);
    }
  }

  return results;
}

Map<hs.Suit, List<int>> _buildCounts(List<hs.Tile> tiles) {
  final counts = <hs.Suit, List<int>>{
    hs.Suit.m: List<int>.filled(10, 0),
    hs.Suit.p: List<int>.filled(10, 0),
    hs.Suit.s: List<int>.filled(10, 0),
    hs.Suit.z: List<int>.filled(8, 0),
  };
  for (final t in tiles) {
    counts[t.suit]![t.rank]++;
  }
  return counts;
}

String _canonicalKey(List<_Group> groups) {
  final parts = groups.map((g) => g._canonicalPart).toList()..sort();
  return parts.join('|');
}

/// 14枚（副露がある場合はその分を除いた残り枚数）を、
/// 「4面子+雀頭」の形になり得る全パターンに分解する。
/// 各パターンは長さ5の _Group リスト（先頭4つが面子、最後が雀頭）で返す。
List<List<_Group>> _decomposeRegularAll(List<hs.Tile> concealedTiles) {
  final baseCounts = _buildCounts(concealedTiles);
  final results = <List<_Group>>[];

  for (final pairSuit in hs.Suit.values) {
    final maxRank = baseCounts[pairSuit]!.length - 1;
    for (int rank = 1; rank <= maxRank; rank++) {
      if (baseCounts[pairSuit]![rank] < 2) continue;

      final counts = <hs.Suit, List<int>>{
        for (final s in hs.Suit.values) s: List<int>.from(baseCounts[s]!),
      };
      counts[pairSuit]![rank] -= 2;

      final perSuitOptions = <hs.Suit, List<List<_Group>>>{};
      bool ok = true;
      for (final s in hs.Suit.values) {
        final allowSeq = s != hs.Suit.z;
        final opts = _decomposeSuitFull(counts[s]!, s, allowSeq);
        if (opts.isEmpty) {
          ok = false;
          break;
        }
        perSuitOptions[s] = opts;
      }
      if (!ok) continue;

      // スートごとの分解を総当たり（デカルト積）で組み合わせる。
      List<List<_Group>> combos = [<_Group>[]];
      for (final s in hs.Suit.values) {
        final opts = perSuitOptions[s]!;
        final newCombos = <List<_Group>>[];
        for (final c in combos) {
          for (final o in opts) {
            newCombos.add([...c, ...o]);
          }
        }
        combos = newCombos;
      }

      for (final combo in combos) {
        if (combo.length == 4) {
          results.add([...combo, _Group(_GroupType.pair, pairSuit, rank)]);
        }
      }
    }
  }

  final seen = <String>{};
  final deduped = <List<_Group>>[];
  for (final r in results) {
    if (seen.add(_canonicalKey(r))) deduped.add(r);
  }
  return deduped;
}

bool _isOrphanTile(hs.Tile t) =>
    t.isHonor || t.rank == 1 || t.rank == 9;

/// 国士無双として有効な形か（副露なし・14枚・全て么九牌・13種類ちょうど）。
bool _isValidKokushiShape(List<hs.Tile> tiles) {
  if (tiles.length != 14) return false;
  if (!tiles.every(_isOrphanTile)) return false;
  final types = tiles.map((t) => '${t.suit.name}${t.rank}').toSet();
  return types.length == 13;
}

/// 国士無双の十三面待ちかどうか（和了牌を1枚除いた13枚が13種類全てを含む＝
/// 和了前の時点で13種類が1枚ずつ揃っていた状態）。
bool _kokushiIsThirteenWait(List<hs.Tile> tiles, hs.Tile winningTile) {
  final remaining = List<hs.Tile>.from(tiles);
  final idx = remaining.indexWhere((t) => t == winningTile);
  if (idx == -1) return false;
  remaining.removeAt(idx);
  final types = remaining.map((t) => '${t.suit.name}${t.rank}').toSet();
  return types.length == 13;
}

/// 七対子として有効な形か（副露なし・全てのランクがちょうど2枚・7種類）。
bool _isValidChiitoiShape(Map<hs.Suit, List<int>> counts) {
  int pairs = 0;
  for (final s in hs.Suit.values) {
    for (final c in counts[s]!) {
      if (c == 0) continue;
      if (c != 2) return false;
      pairs++;
    }
  }
  return pairs == 7;
}

hs.WaitType _waitTypeForGroup(_Group g, hs.Tile winningTile) {
  switch (g.type) {
    case _GroupType.triplet:
      return hs.WaitType.shanpon;
    case _GroupType.pair:
      return hs.WaitType.tanki;
    case _GroupType.sequence:
      final pos = winningTile.rank - g.start; // 0,1,2
      if (pos == 1) return hs.WaitType.kanchan;
      if (pos == 0 && g.start == 7) return hs.WaitType.penchan; // 89待ち7
      if (pos == 2 && g.start == 1) return hs.WaitType.penchan; // 12待ち3
      return hs.WaitType.ryanmen;
  }
}

/// 和了形1パターン + 採点結果のペア。
class HandCandidate {
  final hs.HandInput hand;
  final hs.ScoreResult result;
  const HandCandidate(this.hand, this.result);

  /// 支払い合計（ロン/ツモ・親子の違いを吸収した比較用の点数）。
  int get totalPoints {
    if (hand.winType == hs.WinType.ron) {
      return result.ronPoints ?? 0;
    }
    if (hand.isDealer) {
      return (result.tsumoFromDealer ?? 0) * 3;
    }
    return (result.tsumoFromDealer ?? 0) + (result.tsumoFromNonDealer ?? 0) * 2;
  }
}

/// decomposeAndScore の結果。候補は点数の高い順にソート済み。
class DecomposeOutcome {
  final List<HandCandidate> candidates;
  const DecomposeOutcome(this.candidates);

  bool get isValid => candidates.isNotEmpty;
  HandCandidate get best => candidates.first;
}

/// 平坦なタイル集合（手牌 + 和了牌）から、あり得る全ての和了形を自動分解し、
/// それぞれを採点したうえで最高点の解釈を返す（＝「高点法」の実装）。
///
/// [concealedTiles] は和了牌を含む手牌（副露を除いた残り）。
/// 長さは `14 - 3*calledMelds.length` である必要がある。
/// [calledMelds] は副露（チー・ポン・カン）。V1では閉じた手（空リスト）のみを想定。
DecomposeOutcome decomposeAndScore({
  required List<hs.Tile> concealedTiles,
  required hs.Tile winningTile,
  List<hs.Meld> calledMelds = const [],
  required hs.WinType winType,
  required bool isDealer,
  required int seatWind,
  required int roundWind,
  bool riichi = false,
  bool doubleRiichi = false,
  bool ippatsu = false,
  int doraCount = 0,
  int akaDoraCount = 0,
  int uraDoraCount = 0,
  bool kuitanAllowed = true,
  bool haitei = false,
  bool houtei = false,
  bool rinshan = false,
  bool chankan = false,
  bool tenhou = false,
  bool chiihou = false,
}) {
  final candidates = <HandCandidate>[];
  final menzen = calledMelds.isEmpty;

  hs.HandInput buildHand({
    required List<hs.Meld> melds,
    required hs.WaitType waitType,
    required bool isChiitoi,
    bool isKokushi = false,
    bool kokushi13Wait = false,
    int winningMeldIndex = -1,
  }) {
    return hs.HandInput(
      melds: melds,
      winTile: winningTile,
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
      isKokushi: isKokushi,
      kokushi13Wait: kokushi13Wait,
      winningMeldIndex: winningMeldIndex,
    );
  }

  void addCandidate(hs.HandInput hand) {
    final result = hs.scoreHand(hand);
    candidates.add(HandCandidate(hand, result));
  }

  // ===== 国士無双 =====
  if (calledMelds.isEmpty && _isValidKokushiShape(concealedTiles)) {
    final thirteenWait = _kokushiIsThirteenWait(concealedTiles, winningTile);
    addCandidate(buildHand(
      melds: const <hs.Meld>[],
      waitType: hs.WaitType.tanki,
      isChiitoi: false,
      isKokushi: true,
      kokushi13Wait: thirteenWait,
    ));
  }

  // ===== 七対子 =====
  if (calledMelds.isEmpty) {
    final counts = _buildCounts(concealedTiles);
    if (_isValidChiitoiShape(counts)) {
      final melds = <hs.Meld>[];
      for (final s in hs.Suit.values) {
        for (int rank = 0; rank < counts[s]!.length; rank++) {
          if (counts[s]![rank] == 2) {
            melds.add(_Group(_GroupType.pair, s, rank).toMeld());
          }
        }
      }
      addCandidate(buildHand(
        melds: melds,
        waitType: hs.WaitType.tanki,
        isChiitoi: true,
      ));
    }
  }

  // ===== 通常形（4面子+雀頭） =====
  final neededGroups = 4 - calledMelds.length;
  if (neededGroups >= 0) {
    final decompositions = _decomposeRegularAll(concealedTiles);
    for (final groups in decompositions) {
      // groups は長さ5固定（4面子+雀頭）。副露がある場合は先頭側から必要数だけ使う想定だが、
      // V1では calledMelds は空である前提のため、常に5要素をそのまま使う。
      if (groups.length != neededGroups + 1) continue;

      // 和了牌を含む組み（複数あり得る＝待ちの解釈が複数あるケース）ごとに候補を生成する。
      for (int i = 0; i < groups.length; i++) {
        final g = groups[i];
        if (!g.containsRankSuit(winningTile.suit, winningTile.rank)) continue;

        final waitType = _waitTypeForGroup(g, winningTile);
        final melds = <hs.Meld>[
          ...calledMelds,
          ...groups.map((gr) => gr.toMeld()),
        ];
        final meldIndexInFull = calledMelds.length + i;
        final isShanponRon =
            winType == hs.WinType.ron && waitType == hs.WaitType.shanpon;

        addCandidate(buildHand(
          melds: melds,
          waitType: waitType,
          isChiitoi: false,
          winningMeldIndex: isShanponRon ? meldIndexInFull : -1,
        ));
      }
    }
  }

  candidates.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
  return DecomposeOutcome(candidates);
}
