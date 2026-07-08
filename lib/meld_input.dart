import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hand_scoring.dart' as hs;
import 'hand_decomposition.dart' as hd;
import 'session_page.dart';

// ======== UI用モデル ========
enum Suit { m, p, s, z }
enum MeldType { sequence, triplet, quad, pair }
enum QuadKind { none, open, closed }

class Tile {
  final Suit suit;
  final int rank;
  const Tile(this.suit, this.rank);
  @override
  String toString() => '${suit.name}$rank';
}

class MeldModel {
  MeldType type;
  Suit suit;
  int baseRank;
  bool open;
  QuadKind quadKind;

  MeldModel({
    required this.type,
    required this.suit,
    required this.baseRank,
    required this.open,
    required this.quadKind,
  });

  List<Tile> tiles() {
    if (type == MeldType.sequence) {
      return [Tile(suit, baseRank), Tile(suit, baseRank + 1), Tile(suit, baseRank + 2)];
    }
    if (type == MeldType.pair) return [Tile(suit, baseRank), Tile(suit, baseRank)];
    if (type == MeldType.triplet) return [Tile(suit, baseRank), Tile(suit, baseRank), Tile(suit, baseRank)];
    return [Tile(suit, baseRank), Tile(suit, baseRank), Tile(suit, baseRank), Tile(suit, baseRank)];
  }
}

// ======== 変換（UI → 計算エンジン） ========
hs.Suit _toHsSuit(Suit s) => switch (s) {
      Suit.m => hs.Suit.m,
      Suit.p => hs.Suit.p,
      Suit.s => hs.Suit.s,
      Suit.z => hs.Suit.z,
    };

hs.MeldType _toHsMeldType(MeldType t) => switch (t) {
      MeldType.sequence => hs.MeldType.sequence,
      MeldType.triplet => hs.MeldType.triplet,
      MeldType.quad => hs.MeldType.quad,
      MeldType.pair => hs.MeldType.pair,
    };

hs.QuadKind _toHsQuadKind(QuadKind q) => switch (q) {
      QuadKind.none => hs.QuadKind.none,
      QuadKind.open => hs.QuadKind.open,
      QuadKind.closed => hs.QuadKind.closed,
    };

// 手牌の形（通常手 / 七対子 / 国士無双）を選ぶための、UI専用の選択肢。
enum _HandShape { normal, chiitoi, kokushi }

// 入力方法（おまかせ入力＝14枚を並べるだけで自動判定 / 手動入力＝従来通り面子ごとに分類）。
enum _InputMode { bulk, manual }

class MeldInputPage extends StatefulWidget {
  const MeldInputPage({super.key});

  @override
  State<MeldInputPage> createState() => _MeldInputPageState();
}

class _HistoryEntry {
  final DateTime at;
  final String headline;
  final String detail;
  const _HistoryEntry({required this.at, required this.headline, required this.detail});
}

class _MeldInputPageState extends State<MeldInputPage> with SingleTickerProviderStateMixin {
  // 4面子 + 雀頭
  final List<MeldModel> melds = List.generate(
    5,
    (i) => MeldModel(
      type: i == 4 ? MeldType.pair : MeldType.sequence,
      suit: Suit.m,
      baseRank: 1,
      open: false,
      quadKind: QuadKind.none,
    ),
  );

  // ===== 牌パレット入力 =====
  late List<List<Tile>> _groups; // 0..3: 面子、4: 雀頭
  int _activeGroup = 0;

  // 面子0..3が「槓子（カン）」として入力されているか（trueなら4枚集める）。
  final List<bool> _isQuad = List.generate(4, (_) => false);

  late List<List<Tile>> _chiitoiGroups; // 0..6: 七対子の7ペア
  int _activeChiitoiPair = 0;

  // ===== おまかせ入力（14枚一括タップ→自動で面子・待ちを判定）=====
  // 入力方法。デフォルトは「おまかせ」＝面子の分類を知らなくても使える入力方法。
  _InputMode _inputMode = _InputMode.bulk;
  // タップした順に14枚まで保持する。最後（14枚目）が和了牌という扱い。
  final List<Tile> _bulkTiles = [];

  String? _groupError;
  late final TabController _suitTabs;

  // ===== 状況入力 =====
  hs.WinType winType = hs.WinType.tsumo;
  bool isDealer = false;
  int seatWind = 1;
  int roundWind = 1;
  bool isChiitoi = false;

  // 国士無双：通常のMeld構造で表現できないため、専用フラグで判定する特殊形。
  // trueの場合、面子/雀頭・七対子の入力UIは非表示にし、役満として直接判定する。
  bool isKokushiMode = false;

  // 国士無双：14枚の么九牌をタップして直接組み立てる（おまかせ入力と同じ考え方）。
  // 最後にタップした1枚が和了牌として扱われ、十三面待ちかどうかは
  // （手動でスイッチを立てるのではなく）ここから自動判定する。
  final List<Tile> _kokushiTiles = [];

  bool _isKokushiEligible(Tile t) => t.suit == Suit.z || t.rank == 1 || t.rank == 9;

  _HandShape get _handShape =>
      isKokushiMode ? _HandShape.kokushi : (isChiitoi ? _HandShape.chiitoi : _HandShape.normal);

  void _setHandShape(_HandShape shape) {
    setState(() {
      isChiitoi = shape == _HandShape.chiitoi;
      isKokushiMode = shape == _HandShape.kokushi;
      winningMeldIndex = -1;
    });
  }

  bool riichi = false;
  bool doubleRiichi = false;
  bool ippatsu = false;

  // 状況役
  bool haitei = false;
  bool houtei = false;
  bool rinshan = false;
  bool chankan = false;

  // 天和・地和（ツモのみ／親子で排他）
  bool tenhou = false;
  bool chiihou = false;

  // 喰いタン許可
  bool kuitanAllowed = true;

  // 待ち（入力）
  hs.WaitType waitTypeSelected = hs.WaitType.ryanmen;

  // シャンポン待ち＋ロンの場合に「どちらの刻子がロン牌で完成したか」を表す、
  // melds配列内インデックス（0..3）。-1は未選択。
  int winningMeldIndex = -1;

  int dora = 0;
  int akaDora = 0;
  int uraDora = 0;

  // 上がり牌入力は「非表示」。内部的にはダミーを入れる（m1固定でOK）
  final Suit winSuit = Suit.m;
  final int winRank = 1;

  bool get menzen => melds.take(4).every((m) => !m.open);

  // おまかせ入力は副露（鳴き）非対応のため常に門前。手動入力時は従来通り melds から判定する。
  bool get _effectiveMenzen => _inputMode == _InputMode.bulk ? true : menzen;

  // 嶺上開花は「手の中に槓（カン）が実在する」ことが前提。おまかせ入力は
  // 14枚固定でカンを表現できない（カンがあれば手牌は15枚になるため）ので、
  // 手動入力かつ実際にいずれかの面子を槓にしている場合のみ選択可能にする。
  bool get _hasAnyQuad => _inputMode == _InputMode.manual && _isQuad.any((q) => q);

  // ===== 履歴（直近3件）=====
  final List<_HistoryEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _suitTabs = TabController(length: 4, vsync: this);
    _groups = List.generate(5, (_) => <Tile>[]);
    _chiitoiGroups = List.generate(7, (_) => <Tile>[]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowOnboarding();
    });
  }

  @override
  void dispose() {
    _suitTabs.dispose();
    super.dispose();
  }

  // ===== 初回起動ガイド =====
  Future<void> _maybeShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seen_onboarding_v1') ?? false;
    if (seen) return;
    if (!mounted) return;
    await _showOnboardingDialog();
    await prefs.setBool('seen_onboarding_v1', true);
  }

  Future<void> _showOnboardingDialog() async {
    final pageController = PageController();
    int page = 0;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void goNext() {
              if (page < 2) {
                pageController.animateToPage(page + 1, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
              } else {
                Navigator.pop(ctx);
              }
            }

            return AlertDialog(
              title: const Text('使い方（3ステップ）'),
              content: SizedBox(
                width: 360,
                height: 220,
                child: Column(
                  children: [
                    Expanded(
                      child: PageView(
                        controller: pageController,
                        onPageChanged: (p) => setLocal(() => page = p),
                        children: const [
                          _OnboardPage(title: '1. 入力先を選ぶ', body: '上のカード（面子/雀頭 or ペア）をタップして入力先を選びます。'),
                          _OnboardPage(title: '2. 牌をタップで入力', body: '下の牌パレットをタップすると入力されます。\n埋まったら自動で次へ移動します。'),
                          _OnboardPage(title: '3. 計算する', body: '画面下の「計算」ボタンを押すと結果が出ます。\n「全部クリア」でやり直せます。'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        3,
                        (i) => Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == page ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる')),
                FilledButton(onPressed: goNext, child: Text(page < 2 ? '次へ' : 'はじめる')),
              ],
            );
          },
        );
      },
    );
  }

  // ===== 画像・表示 =====
  // 字牌の画像は assets/tiles/z1.png のような命名ではなく、漢字そのまま
  // （東.png/南.png/西.png/北.png/白.png/發.png/中.png）で保存されているため、
  // 数牌（萬子/筒子/索子）とは別にファイル名を組み立てる。
  static const Map<int, String> _honorLabels = {1: '東', 2: '南', 3: '西', 4: '北', 5: '白', 6: '發', 7: '中'};

  String _tileAssetPath(Tile t) {
    if (t.suit == Suit.z) {
      final label = _honorLabels[t.rank];
      return 'assets/tiles/$label.png';
    }
    return 'assets/tiles/${t.suit.name}${t.rank}.png';
  }

  String _tileLabel(Tile t) {
    if (t.suit != Suit.z) return '${t.suit.name}${t.rank}';
    return _honorLabels[t.rank] ?? 'z${t.rank}';
  }

  Widget _tileFace(Tile t) {
    return Image.asset(
      _tileAssetPath(t),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Center(child: Text(_tileLabel(t))),
    );
  }

  // ===== パレット =====
  List<Tile> _palette(Suit suit) {
    if (suit == Suit.z) return List.generate(7, (i) => Tile(Suit.z, i + 1));
    return List.generate(9, (i) => Tile(suit, i + 1));
  }

  // ===== 入力カーソル =====
  int _capacityForGroupNormal(int groupIndex) => (groupIndex == 4) ? 2 : (_isQuad[groupIndex] ? 4 : 3);

  int _cursorIndexForNormalGroup(int groupIndex) {
    final cap = _capacityForGroupNormal(groupIndex);
    final len = _groups[groupIndex].length;
    return (len < cap) ? len : (cap - 1);
  }

  bool _isCursorCellNormal(int groupIndex, int cellIndex) {
    if (_activeGroup != groupIndex) return false;
    return cellIndex == _cursorIndexForNormalGroup(groupIndex);
  }

  int _chiitoiCursorIndex(int pairIndex) {
    final len = _chiitoiGroups[pairIndex].length;
    return (len < 2) ? len : 1;
  }

  // ===== シャンポン待ち＋ロン用：面子が現在「刻子」の形になっているか =====
  bool _isGroupTriplet(int groupIndex) {
    final g = _groups[groupIndex];
    if (g.length != 3) return false;
    final r0 = g[0].rank;
    final s0 = g[0].suit;
    return g.every((t) => t.rank == r0 && t.suit == s0);
  }

  List<int> _tripletGroupIndices() => [for (int i = 0; i < 4; i++) if (_isGroupTriplet(i)) i];

  // ===== 牌の重複チェック（同じ牌は現実には4枚までしか存在しない） =====
  int _countTile(Iterable<Tile> tiles, Tile t) =>
      tiles.where((x) => x.suit == t.suit && x.rank == t.rank).length;

  String _duplicateTileError(Tile t) => '${_tileLabel(t)}は同じ牌を5枚以上使えません（同じ牌は1種類につき4枚までです）。';

  // ===== おまかせ入力：牌プールへの追加/削除/クリア =====
  void _addBulkTile(Tile t) {
    // 14枚目（和了牌スロット）を上書きする場合は、そのスロットの現在の牌を
    // 集計から除外してからチェックする（同じ牌を置き直すだけなら重複にならない）。
    final replacingLast = _bulkTiles.length >= 14;
    final countExcludingSlot = replacingLast
        ? _countTile(_bulkTiles.sublist(0, 13), t)
        : _countTile(_bulkTiles, t);
    if (countExcludingSlot >= 4) {
      setState(() => _groupError = _duplicateTileError(t));
      return;
    }
    setState(() {
      _groupError = null;
      if (!replacingLast) {
        _bulkTiles.add(t);
      } else {
        _bulkTiles[13] = t;
      }
    });
  }

  void _removeBulkTile(int index) {
    setState(() {
      _bulkTiles.removeAt(index);
    });
  }

  /// 直前にタップした1枚だけを取り消す（末尾の1枚を削除する）。
  /// 「全部クリア」しかないと、14枚並べている途中の1ミスで最初からやり直す
  /// 羽目になってしまうため、1枚単位で戻せるようにしている。
  void _undoLastBulkTile() {
    if (_bulkTiles.isEmpty) return;
    setState(() {
      _bulkTiles.removeLast();
    });
  }

  void _clearBulkTiles() {
    setState(() {
      _bulkTiles.clear();
    });
  }

  // ===== 国士無双：14枚の牌プールへの追加/削除/クリア（おまかせ入力と同じ考え方） =====
  void _addKokushiTile(Tile t) {
    if (!_isKokushiEligible(t)) {
      setState(() => _groupError = '国士無双で使えるのは么九牌（1・9・字牌）のみです。');
      return;
    }
    if (_kokushiTiles.length >= 14) {
      setState(() => _groupError = '国士無双の入力はすでに14枚そろっています（続けるには「1つ戻す」か「クリア」を使ってください）。');
      return;
    }
    if (_countTile(_kokushiTiles, t) >= 2) {
      setState(() => _groupError = '${_tileLabel(t)}は同じ牌を3枚以上使えません（国士無双は1種類につき最大2枚です）。');
      return;
    }
    setState(() {
      _groupError = null;
      _kokushiTiles.add(t);
    });
  }

  void _removeKokushiTile(int index) {
    setState(() {
      _kokushiTiles.removeAt(index);
    });
  }

  void _undoLastKokushiTile() {
    if (_kokushiTiles.isEmpty) return;
    setState(() {
      _kokushiTiles.removeLast();
    });
  }

  void _clearKokushiTiles() {
    setState(() {
      _kokushiTiles.clear();
    });
  }

  /// 国士無双として有効な形か（14枚・全て么九牌・13種類ちょうど＝どれか1種だけ2枚）。
  bool _isValidKokushiShape(List<Tile> tiles) {
    if (tiles.length != 14) return false;
    if (!tiles.every(_isKokushiEligible)) return false;
    final types = tiles.map((t) => '${t.suit.name}${t.rank}').toSet();
    return types.length == 13;
  }

  /// 国士無双の十三面待ちかどうか（和了牌を除いた13枚が13種類全てを含む＝
  /// 和了前の時点で13種類が1枚ずつ揃っていた状態）を、入力から自動判定する。
  bool _kokushiIsThirteenWait(List<Tile> tiles, Tile winningTile) {
    final remaining = List<Tile>.from(tiles);
    final idx = remaining.indexWhere((t) => t.suit == winningTile.suit && t.rank == winningTile.rank);
    if (idx == -1) return false;
    remaining.removeAt(idx);
    final types = remaining.map((t) => '${t.suit.name}${t.rank}').toSet();
    return types.length == 13;
  }

  // ===== 入力（タップで追加） =====
  void _addTileToActive(Tile t) {
    if (_inputMode == _InputMode.bulk) {
      _addBulkTile(t);
      return;
    }

    if (isKokushiMode) {
      _addKokushiTile(t);
      return;
    }

    setState(() {
      _groupError = null;

      if (isChiitoi) {
        final g = _chiitoiGroups[_activeChiitoiPair];
        const cap = 2;
        final replacingLast = g.length >= cap;

        final allChiitoiTiles = _chiitoiGroups.expand((x) => x).toList();
        final countExcludingSlot = replacingLast
            ? _countTile(allChiitoiTiles, t) - _countTile([g[cap - 1]], t)
            : _countTile(allChiitoiTiles, t);
        if (countExcludingSlot >= 4) {
          _groupError = _duplicateTileError(t);
          return;
        }

        if (g.length < cap) {
          g.add(t);
        } else {
          g[cap - 1] = t;
        }

        if (g.length >= cap && _activeChiitoiPair < 6) {
          _activeChiitoiPair += 1;
        }
        return;
      }

      final g = _groups[_activeGroup];
      final cap = _capacityForGroupNormal(_activeGroup);
      final replacingLast = g.length >= cap;

      final allGroupTiles = _groups.expand((x) => x).toList();
      final countExcludingSlot = replacingLast
          ? _countTile(allGroupTiles, t) - _countTile([g[cap - 1]], t)
          : _countTile(allGroupTiles, t);
      if (countExcludingSlot >= 4) {
        _groupError = _duplicateTileError(t);
        return;
      }

      if (g.length < cap) {
        g.add(t);
      } else {
        g[cap - 1] = t;
      }

      final filled = g.length >= cap;
      if (filled && _activeGroup < 4) _activeGroup += 1;
    });
  }

  // ===== 削除/クリア =====
  void _removeTile(int groupIndex, int tileIndex) {
    setState(() {
      _groupError = null;
      _groups[groupIndex].removeAt(tileIndex);
    });
  }

  void _clearGroup(int groupIndex) {
    setState(() {
      _groupError = null;
      _groups[groupIndex].clear();
    });
  }

  void _setActiveGroup(int idx) {
    setState(() {
      _activeGroup = idx;
      _groupError = null;
    });
  }

  // 槓（カン）フラグの切り替え。枚数の前提が変わる（3枚⇔4枚）ため、
  // 混乱を避けて入力済みの牌はクリアする。
  void _setGroupQuad(int index, bool value) {
    setState(() {
      _isQuad[index] = value;
      _groups[index].clear();
      _groupError = null;
      // 手の中に槓が1つも無くなった場合、嶺上開花は成立し得ないためオフに戻す。
      if (!_isQuad.any((q) => q)) {
        rinshan = false;
      }
    });
  }

  void _setActiveChiitoiPair(int idx) {
    setState(() {
      _activeChiitoiPair = idx;
      _groupError = null;
    });
  }

  void _removeChiitoiTile(int pairIndex, int tileIndex) {
    setState(() {
      _groupError = null;
      _chiitoiGroups[pairIndex].removeAt(tileIndex);
    });
  }

  void _clearChiitoiPair(int pairIndex) {
    setState(() {
      _groupError = null;
      _chiitoiGroups[pairIndex].clear();
    });
  }

  void _clearAll() {
    setState(() {
      _groupError = null;
      for (final g in _groups) {
        g.clear();
      }
      for (final g in _chiitoiGroups) {
        g.clear();
      }
      for (int i = 0; i < _isQuad.length; i++) {
        _isQuad[i] = false;
      }
      _bulkTiles.clear();
      _kokushiTiles.clear();
      _activeGroup = 0;
      _activeChiitoiPair = 0;
      winningMeldIndex = -1;

      // 状況系（立直・一発・ドラ・海底/嶺上/槍槓・天和/地和）は、和了ごとに変わる
      // 一発性の情報であり、「全部クリア」時に消し忘れると次の局の計算に
      // 誤って引き継がれてしまう（例: 前局の天和フラグが立ったまま次局を計算し、
      // 実際には役満ではない手が役満として計算されてしまう）ため、ここで必ず初期化する。
      riichi = false;
      doubleRiichi = false;
      ippatsu = false;
      haitei = false;
      houtei = false;
      rinshan = false;
      chankan = false;
      tenhou = false;
      chiihou = false;
      dora = 0;
      akaDora = 0;
      uraDora = 0;
    });
  }

  // ===== 面子判定（牌配列 → MeldModel） =====
  MeldModel? _toMeldModelFromTiles(
    List<Tile> tiles, {
    required bool isPair,
    required bool isQuad,
    required bool open,
  }) {
    if (isPair) {
      if (tiles.length != 2) return null;
      if (tiles[0].suit != tiles[1].suit) return null;
      if (tiles[0].rank != tiles[1].rank) return null;
      return MeldModel(
        type: MeldType.pair,
        suit: tiles[0].suit,
        baseRank: tiles[0].rank,
        open: false,
        quadKind: QuadKind.none,
      );
    }

    if (isQuad) {
      // 槓子：同じ牌4枚（暗槓/明槓とも順子にはならない）。
      // openチェック（鳴き）がONなら明槓、OFFなら暗槓として扱う。
      if (tiles.length != 4) return null;
      final suit = tiles[0].suit;
      final r0 = tiles[0].rank;
      if (tiles.any((t) => t.suit != suit || t.rank != r0)) return null;
      return MeldModel(
        type: MeldType.quad,
        suit: suit,
        baseRank: r0,
        open: open,
        quadKind: open ? QuadKind.open : QuadKind.closed,
      );
    }

    if (tiles.length != 3) return null;

    final suit = tiles[0].suit;
    if (tiles.any((t) => t.suit != suit)) return null;

    final r0 = tiles[0].rank;

    // 刻子
    if (tiles[1].rank == r0 && tiles[2].rank == r0) {
      return MeldModel(type: MeldType.triplet, suit: suit, baseRank: r0, open: open, quadKind: QuadKind.none);
    }

    // 字牌は順子不可
    if (suit == Suit.z) return null;

    // 順子
    final rs = tiles.map((t) => t.rank).toList()..sort();
    if (rs[0] + 1 == rs[1] && rs[1] + 1 == rs[2]) {
      return MeldModel(type: MeldType.sequence, suit: suit, baseRank: rs[0], open: open, quadKind: QuadKind.none);
    }

    return null;
  }

  // ===== 七対子（UIのペア7つ → hs.Meld 7つ） =====
  List<hs.Meld>? buildChiitoiMeldsFromGroups() {
    final seen = <String>{};
    final out = <hs.Meld>[];

    for (int i = 0; i < 7; i++) {
      final g = _chiitoiGroups[i];
      if (g.length != 2) return null;
      if (g[0].suit != g[1].suit || g[0].rank != g[1].rank) return null;

      final key = '${g[0].suit.name}${g[0].rank}';
      if (seen.contains(key)) return null;
      seen.add(key);

      final t = hs.Tile(_toHsSuit(g[0].suit), g[0].rank);
      out.add(hs.Meld(type: hs.MeldType.pair, tiles: [t, t], open: false, quadKind: hs.QuadKind.none));
    }
    return out;
  }

  String _waitLabel(hs.WaitType w) {
    switch (w) {
      case hs.WaitType.ryanmen:
        return '両面';
      case hs.WaitType.kanchan:
        return '嵌張';
      case hs.WaitType.penchan:
        return '辺張';
      case hs.WaitType.tanki:
        return '単騎';
      case hs.WaitType.shanpon:
        return 'シャンポン';
    }
  }

  // ===== 履歴参照（1行 → タップで一覧）=====
  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        String fmt(DateTime d) {
          String two(int n) => n.toString().padLeft(2, '0');
          return '${d.month}/${d.day} ${two(d.hour)}:${two(d.minute)}';
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('計算履歴（直近3件）', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _history.length,
                    separatorBuilder: (_, _) => const Divider(height: 16),
                    itemBuilder: (_, i) {
                      final e = _history[i];
                      return ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(e.headline),
                        subtitle: Text(fmt(e.at)),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
                              child: Text(e.detail),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _historyPanel() {
    if (_history.isEmpty) return const SizedBox.shrink();

    String fmt(DateTime d) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.month}/${d.day} ${two(d.hour)}:${two(d.minute)}';
    }

    final latest = _history.first;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        title: const Text('履歴参照'),
        subtitle: Text(
          '${fmt(latest.at)}  ${latest.headline}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _showHistorySheet,
      ),
    );
  }

  // ===== 計算（入力方法ごとの振り分け） =====
  void _calcAndShow() {
    if (_inputMode == _InputMode.bulk) {
      _calcAndShowBulk();
    } else {
      _calcAndShowManual();
    }
  }

  // ===== おまかせ入力：14枚の牌プールから自動で面子・待ちを判定して計算 =====
  void _calcAndShowBulk() {
    if (_bulkTiles.length != 14) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('入力エラー'),
          content: Text('手牌が14枚そろっていません（現在${_bulkTiles.length}枚）。\n最後の1枚が和了牌として扱われます。'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }

    final hsTiles = _bulkTiles.map((t) => hs.Tile(_toHsSuit(t.suit), t.rank)).toList();
    final winningTile = hsTiles.last;

    final outcome = hd.decomposeAndScore(
      concealedTiles: hsTiles,
      winningTile: winningTile,
      winType: winType,
      isDealer: isDealer,
      seatWind: seatWind,
      roundWind: roundWind,
      riichi: riichi,
      doubleRiichi: doubleRiichi,
      ippatsu: ippatsu,
      doraCount: dora,
      akaDoraCount: akaDora,
      uraDoraCount: uraDora,
      kuitanAllowed: kuitanAllowed,
      haitei: haitei,
      houtei: houtei,
      rinshan: rinshan,
      chankan: chankan,
      tenhou: tenhou,
      chiihou: chiihou,
    );

    if (!outcome.isValid) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('和了形が見つかりません'),
          content: const Text('入力された14枚では、有効な和了の形（4面子+雀頭・七対子・国士無双）になりませんでした。\n牌の入力を確認してください。'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }

    _presentResult(outcome.best.hand, outcome.best.result);
  }

  // ===== 手動入力：従来通り面子ごとに分類した入力から計算 =====
  void _calcAndShowManual() {
    late final List<hs.Meld> hsMelds;

    if (isKokushiMode) {
      // 国士無双は通常のMeld構造で表現できないため、面子の入力自体を行わない。
      // 代わりに、専用パネルでタップ入力した14枚（_kokushiTiles）を直接検証する。
      if (_kokushiTiles.length != 14) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('入力エラー'),
            content: Text('国士無双の牌が14枚そろっていません（現在${_kokushiTiles.length}枚）。'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        return;
      }
      if (!_isValidKokushiShape(_kokushiTiles)) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('入力エラー'),
            content: const Text(
              '国士無双として成立していません。\n'
              '么九牌（1・9・字牌）13種類がそれぞれ1〜2枚、かつそのうち1種類だけが2枚（雀頭）になるようにしてください。',
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        return;
      }
      hsMelds = const <hs.Meld>[];
    } else if (isChiitoi) {
      final chiitoiMelds = buildChiitoiMeldsFromGroups();
      if (chiitoiMelds == null) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('入力エラー'),
            content: const Text('七対子：各ペアは「同じ牌2枚」で、かつ7ペアすべて異なる牌にしてください。'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        return;
      }
      hsMelds = chiitoiMelds;
    } else {
      final mm = <MeldModel>[];
      for (int i = 0; i < 5; i++) {
        final isQuadGroup = i < 4 && _isQuad[i];
        final m = _toMeldModelFromTiles(
          _groups[i],
          isPair: i == 4,
          isQuad: isQuadGroup,
          open: melds[i].open,
        );
        if (m == null) {
          final message = i == 4
              ? '雀頭が正しくありません（同じ牌を2枚）'
              : isQuadGroup
                  ? '面子${i + 1}が正しくありません（槓子＝同じ牌4枚）'
                  : '面子${i + 1}が正しくありません（順子/刻子の3枚）';
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('入力エラー'),
              content: Text(message),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
            ),
          );
          return;
        }
        mm.add(m);
      }

      hsMelds = mm.map((m) {
        final hsTiles = m.tiles().map((t) => hs.Tile(_toHsSuit(t.suit), t.rank)).toList();
        return hs.Meld(
          type: _toHsMeldType(m.type),
          tiles: hsTiles,
          open: m.open,
          quadKind: _toHsQuadKind(m.quadKind),
        );
      }).toList();
    }

    // シャンポン待ち＋ロンの場合のみ、ロンで完成した刻子のインデックスが必要。
    final isShanponRon =
        !isChiitoi && !isKokushiMode && winType == hs.WinType.ron && waitTypeSelected == hs.WaitType.shanpon;
    if (isShanponRon) {
      final tripletIndices = _tripletGroupIndices();
      if (tripletIndices.length < 2 || !tripletIndices.contains(winningMeldIndex)) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('入力エラー'),
            content: const Text('シャンポン待ち＋ロン：ロンで完成した刻子をどちらか選んでください。'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        return;
      }
    }

    // 上がり牌UIは通常/七対子では非表示なので、内部ではダミー牌（m1）を渡す。
    // 国士無双は専用パネルで最後にタップした牌を和了牌として扱う。
    final winTileHs = isKokushiMode
        ? hs.Tile(_toHsSuit(_kokushiTiles.last.suit), _kokushiTiles.last.rank)
        : hs.Tile(_toHsSuit(winSuit), winRank);

    final hand = hs.HandInput(
      melds: hsMelds,
      winTile: winTileHs,
      winType: winType,
      waitType: (isChiitoi || isKokushiMode) ? hs.WaitType.tanki : waitTypeSelected,
      isDealer: isDealer,
      seatWind: seatWind,
      roundWind: roundWind,
      riichi: riichi,
      doubleRiichi: doubleRiichi,
      ippatsu: ippatsu,
      menzen: (isChiitoi || isKokushiMode) ? true : menzen,
      doraCount: dora,
      akaDoraCount: akaDora,
      uraDoraCount: uraDora,
      isChiitoi: isChiitoi,
      kuitanAllowed: kuitanAllowed,
      haitei: haitei,
      houtei: houtei,
      rinshan: rinshan,
      chankan: chankan,
      winningMeldIndex: isShanponRon ? winningMeldIndex : -1,
      tenhou: tenhou,
      chiihou: chiihou,
      isKokushi: isKokushiMode,
      kokushi13Wait: isKokushiMode ? _kokushiIsThirteenWait(_kokushiTiles, _kokushiTiles.last) : false,
    );

    final result = hs.scoreHand(hand);
    _presentResult(hand, result);
  }

  // ===== 結果表示（おまかせ入力・手動入力の両方から共通で呼ばれる） =====
  void _presentResult(hs.HandInput hand, hs.ScoreResult result) {
    final totalDora = dora + akaDora + uraDora;
    final hasAnyYaku = result.yakus.isNotEmpty;

    if (!hasAnyYaku) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('和了できません'),
          content: Text(totalDora > 0 ? 'ドラは役になりません。\n（役が無いので点数計算できません）' : '役がありません。\n（点数計算できません）'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }

    final yakuLines = result.yakus.map((y) => '・${y.name}（${y.han(hand.menzen)}翻）').join('\n');
    final fuLines = result.fu.items.map((i) => '・${i.label}: ${i.value}').join('\n');

    final scoreLine = () {
      if (hand.winType == hs.WinType.ron) {
        final p = result.ronPoints ?? 0;
        return 'ロン: $p';
      }
      final fromDealer = result.tsumoFromDealer ?? 0;
      final fromNonDealer = result.tsumoFromNonDealer ?? 0;

      if (hand.isDealer) {
        final total = fromDealer * 3;
        return 'ツモ: $fromDealerオール（計 $total）';
      } else {
        final total = fromDealer + fromNonDealer * 2;
        return 'ツモ: 親 $fromDealer / 子 $fromNonDealer（計 $total）';
      }
    }();

    final headline = [
      if (result.limitName.isNotEmpty) result.limitName,
      '${result.fu.fuRounded}符 ${result.han}翻',
      scoreLine,
    ].join(' / ');

    final detail = [
      if (result.limitName.isNotEmpty) '上限: ${result.limitName}',
      '翻: ${result.han}（ドラ含む）',
      '符: ${result.fu.fuRounded}（生=${result.fu.fuRaw}）',
      '',
      '【待ち】\n${_waitLabel(hand.waitType)}',
      '',
      '【役】\n$yakuLines',
      '',
      '【符内訳】\n$fuLines',
      '',
      '【点数】\n$scoreLine',
    ].join('\n');

    setState(() {
      _history.insert(0, _HistoryEntry(at: DateTime.now(), headline: headline, detail: detail));
      if (_history.length > 3) _history.removeRange(3, _history.length);
    });

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('結果'),
        content: SingleChildScrollView(child: Text(detail)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  // ===== 共通UI部品 =====
  Widget _row(String label, Widget child) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text(label)),
        const SizedBox(width: 12),
        Expanded(child: Align(alignment: Alignment.centerLeft, child: child)),
      ],
    );
  }

  Widget _windDropdown({required int value, required ValueChanged<int> onChanged}) {
    const winds = [
      DropdownMenuItem(value: 1, child: Text('東')),
      DropdownMenuItem(value: 2, child: Text('南')),
      DropdownMenuItem(value: 3, child: Text('西')),
      DropdownMenuItem(value: 4, child: Text('北')),
    ];
    return DropdownButton<int>(value: value, items: winds, onChanged: (v) => onChanged(v ?? 1));
  }

  Widget _stepper(int value, ValueChanged<int>? onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(onPressed: onChanged == null ? null : () => onChanged(value - 1), icon: const Icon(Icons.remove)),
        Text('$value', style: const TextStyle(fontSize: 18)),
        IconButton(onPressed: onChanged == null ? null : () => onChanged(value + 1), icon: const Icon(Icons.add)),
      ],
    );
  }

  // ===== 通常手：面子カード =====
  Widget _groupCard({
    required int index,
    required String title,
    required int capacity,
    required bool isPair,
  }) {
    final selected = (!isChiitoi && _activeGroup == index);

    return InkWell(
      onTap: () => _setActiveGroup(index),
      child: Card(
        elevation: selected ? 2.5 : 1,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('$title（$capacity枚）', style: Theme.of(context).textTheme.titleMedium)),
                  TextButton(onPressed: () => _clearGroup(index), child: const Text('クリア')),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: List.generate(capacity, (i) {
                    final isCursor = selected && _isCursorCellNormal(index, i);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onLongPress: (i < _groups[index].length) ? () => _removeTile(index, i) : null,
                        child: Container(
                          width: 42,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCursor ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                              width: isCursor ? 3 : 1,
                            ),
                          ),
                          child: (i < _groups[index].length)
                              ? Padding(padding: const EdgeInsets.all(4), child: _tileFace(_groups[index][i]))
                              : const Center(child: Text('□')),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),
              if (!isPair && index < 4)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    FilterChip(
                      label: const Text('槓（カン）'),
                      selected: _isQuad[index],
                      onSelected: (v) => _setGroupQuad(index, v),
                    ),
                    FilterChip(
                      label: Text(_isQuad[index] ? '明槓（鳴き）' : '鳴き（オープン）'),
                      selected: melds[index].open,
                      onSelected: (v) => setState(() {
                        melds[index].open = v;
                        // 副露（鳴き）が入った時点で天和・地和・立直系（いずれも
                        // 完全な門前が前提）は成立し得ないため、誤って
                        // 引き継がれないようオフに戻す。
                        if (v) {
                          tenhou = false;
                          chiihou = false;
                          riichi = false;
                          doubleRiichi = false;
                          ippatsu = false;
                          uraDora = 0;
                        }
                      }),
                    ),
                  ],
                ),
              if (selected) ...[
                const SizedBox(height: 6),
                Text('下の牌パレットをタップして追加（埋まったら次へ移動）', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ===== 七対子：ペアカード =====
  Widget _chiitoiPairCard({required int index}) {
    final selected = (isChiitoi && _activeChiitoiPair == index);
    final cursor = _chiitoiCursorIndex(index);

    return InkWell(
      onTap: () => _setActiveChiitoiPair(index),
      child: Card(
        elevation: selected ? 2.5 : 1,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('ペア${index + 1}（2枚）', style: Theme.of(context).textTheme.titleMedium)),
                  TextButton(onPressed: () => _clearChiitoiPair(index), child: const Text('クリア')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(2, (i) {
                  final isCursor = selected && (i == cursor);
                  final hasTile = i < _chiitoiGroups[index].length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPress: hasTile ? () => _removeChiitoiTile(index, i) : null,
                      child: Container(
                        width: 42,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCursor ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                            width: isCursor ? 3 : 1,
                          ),
                        ),
                        child: hasTile
                            ? Padding(padding: const EdgeInsets.all(4), child: _tileFace(_chiitoiGroups[index][i]))
                            : const Center(child: Text('□')),
                      ),
                    ),
                  );
                }),
              ),
              if (selected) ...[
                const SizedBox(height: 6),
                Text('下の牌パレットをタップして追加（埋まったら次へ移動）', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ===== おまかせ入力：14枚の牌プール（面子分類はしない） =====
  Widget _bulkPoolCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('手牌（14枚）', style: Theme.of(context).textTheme.titleMedium)),
                TextButton.icon(
                  onPressed: _bulkTiles.isEmpty ? null : _undoLastBulkTile,
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('1つ戻す'),
                ),
                TextButton(onPressed: _clearBulkTiles, child: const Text('クリア')),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '先に13枚並べてから、最後にアガった牌（和了牌）を1枚タップしてください。\n面子の分類は自動で判定します。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(14, (i) {
                final hasTile = i < _bulkTiles.length;
                final isWinningSlot = i == 13;
                return GestureDetector(
                  onLongPress: hasTile ? () => _removeBulkTile(i) : null,
                  child: Container(
                    width: 42,
                    height: 54,
                    decoration: BoxDecoration(
                      color: isWinningSlot
                          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isWinningSlot ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                        width: isWinningSlot ? 2 : 1,
                      ),
                    ),
                    child: hasTile
                        ? Padding(padding: const EdgeInsets.all(4), child: _tileFace(_bulkTiles[i]))
                        : Center(
                            child: Text(
                              isWinningSlot ? '和了' : '□',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            Text('${_bulkTiles.length} / 14枚（長押しで1枚削除）', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  // ===== 下固定：牌パレット =====
  Widget _tileGrid(List<Tile> tiles) {
    return GridView.count(
      crossAxisCount: 9,
      childAspectRatio: 1.2,
      padding: const EdgeInsets.all(6),
      children: [
        for (final t in tiles)
          InkWell(
            onTap: () => _addTileToActive(t),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: _tileFace(t),
              ),
            ),
          ),
      ],
    );
  }

  // ===== 計算ボタン（画面下固定） =====
  Widget _fixedActionBar() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            OutlinedButton(onPressed: _clearAll, child: const Text('全部クリア')),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _calcAndShow,
                child: Text('計算（門前: ${_effectiveMenzen ? "はい" : "いいえ"}）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 国士無双：専用パネル（通常の面子入力の代わりに表示） =====
  // おまかせ入力の牌プールと同じ考え方で、么九牌13種を実際にタップして
  // 14枚を組み立ててもらう。以前はスイッチひとつで役満を確定させていたが、
  // それだと実際の手牌を確認せずに役満が成立してしまうため、
  // 必ず具体的な牌の入力→形の検証を経るようにしている。
  Widget _kokushiPanel() {
    final has14 = _kokushiTiles.length == 14;
    final validShape = has14 && _isValidKokushiShape(_kokushiTiles);
    final thirteenWait = validShape ? _kokushiIsThirteenWait(_kokushiTiles, _kokushiTiles.last) : false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('国士無双（14枚）', style: Theme.of(context).textTheme.titleMedium)),
                TextButton.icon(
                  onPressed: _kokushiTiles.isEmpty ? null : _undoLastKokushiTile,
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('1つ戻す'),
                ),
                TextButton(onPressed: _clearKokushiTiles, child: const Text('クリア')),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '下の牌パレットで么九牌（1・9・字牌）をタップして14枚並べてください（それ以外の牌は使えません）。\n'
              '最後にタップした1枚が和了牌として扱われ、十三面待ちかどうかは自動で判定します。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(14, (i) {
                final hasTile = i < _kokushiTiles.length;
                final isWinningSlot = i == 13;
                return GestureDetector(
                  onLongPress: hasTile ? () => _removeKokushiTile(i) : null,
                  child: Container(
                    width: 42,
                    height: 54,
                    decoration: BoxDecoration(
                      color: isWinningSlot
                          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isWinningSlot ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                        width: isWinningSlot ? 2 : 1,
                      ),
                    ),
                    child: hasTile
                        ? Padding(padding: const EdgeInsets.all(4), child: _tileFace(_kokushiTiles[i]))
                        : Center(
                            child: Text(
                              isWinningSlot ? '和了' : '□',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            Text('${_kokushiTiles.length} / 14枚（長押しで1枚削除）', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            if (has14)
              Text(
                validShape
                    ? '✓ 国士無双の形として成立しています（${thirteenWait ? "十三面待ち＝ダブル役満" : "単騎待ち＝役満"}）'
                    : '✕ まだ国士無双の形になっていません（么九牌13種類、うち1種類だけ2枚になるようにしてください）',
                style: TextStyle(
                  color: validShape ? Colors.green.shade700 : Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===== シャンポン待ち＋ロン：どちらの刻子が明刻になるか選択 =====
  Widget _wonMeldSelectorPanel() {
    final tripletIndices = _tripletGroupIndices();

    if (tripletIndices.length < 2) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'シャンポン待ちには刻子が2つ必要です。面子の入力を確認してください。',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ロン牌で完成したのはどちらの刻子？', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'シャンポン待ちは片方の刻子だけがロン牌で完成（明刻扱い）します。もう片方は暗刻のままです。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            RadioGroup<int>(
              groupValue: tripletIndices.contains(winningMeldIndex) ? winningMeldIndex : null,
              onChanged: (v) => setState(() => winningMeldIndex = v ?? -1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final i in tripletIndices)
                    RadioListTile<int>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('面子${i + 1}（${_groups[i].map(_tileLabel).join("")}）'),
                      value: i,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 状況役（海底/河底/嶺上/槍槓） =====
  Widget _specialWinFlagsPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('特殊（状況）', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('海底摸月（ツモ）'),
              value: haitei,
              onChanged: (winType == hs.WinType.tsumo)
                  ? (v) => setState(() {
                        haitei = v;
                        if (v) {
                          houtei = false;
                          chankan = false;
                        }
                      })
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('嶺上開花（ツモ）'),
              subtitle: const Text('槓（カン）した後の嶺上牌でのツモ和了'),
              value: rinshan,
              onChanged: (winType == hs.WinType.tsumo && _hasAnyQuad)
                  ? (v) => setState(() {
                        rinshan = v;
                        if (v) {
                          houtei = false;
                          chankan = false;
                        }
                      })
                  : null,
            ),
            if (!_hasAnyQuad)
              Text(
                '※ 嶺上開花は手の中に槓（カン）がある場合のみ選択できます',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('河底撈魚（ロン）'),
              value: houtei,
              onChanged: (winType == hs.WinType.ron)
                  ? (v) => setState(() {
                        houtei = v;
                        if (v) {
                          haitei = false;
                          rinshan = false;
                        }
                      })
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('槍槓（ロン）'),
              value: chankan,
              onChanged: (winType == hs.WinType.ron)
                  ? (v) => setState(() {
                        chankan = v;
                        if (v) {
                          haitei = false;
                          rinshan = false;
                        }
                      })
                  : null,
            ),

            Text(
              winType == hs.WinType.tsumo ? '※ ロン系（河底・槍槓）はオフになります' : '※ ツモ系（海底・嶺上）はオフになります',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            const Divider(height: 20),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('天和（役満）'),
              subtitle: const Text('親の配牌時点でのツモ和了'),
              value: tenhou,
              onChanged: (winType == hs.WinType.tsumo && isDealer && _effectiveMenzen)
                  ? (v) => setState(() => tenhou = v)
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('地和（役満）'),
              subtitle: const Text('子の第一巡でのツモ和了（副露なし）'),
              value: chiihou,
              onChanged: (winType == hs.WinType.tsumo && !isDealer && _effectiveMenzen)
                  ? (v) => setState(() => chiihou = v)
                  : null,
            ),
            Text(
              _effectiveMenzen
                  ? '※ 天和は親、地和は子のツモ時のみ選択できます'
                  : '※ 副露（鳴き）がある手では天和・地和は選択できません',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  // ===== 画面構成 =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('面子入力（牌パレット）'),
        actions: [
          IconButton(
            tooltip: '対局スコア（台に1台置いて共有）',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SessionPage()),
            ),
            icon: const Icon(Icons.leaderboard),
          ),
          IconButton(tooltip: '使い方', onPressed: _showOnboardingDialog, icon: const Icon(Icons.help_outline)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<_InputMode>(
                  segments: const [
                    ButtonSegment(value: _InputMode.bulk, label: Text('おまかせ入力（推奨）')),
                    ButtonSegment(value: _InputMode.manual, label: Text('手動入力')),
                  ],
                  selected: {_inputMode},
                  onSelectionChanged: (v) => setState(() {
                    _inputMode = v.first;
                    // おまかせ入力（14枚固定）は槓を表現できないため、
                    // 嶺上開花が残っていたらオフに戻す。
                    if (_inputMode == _InputMode.bulk) {
                      rinshan = false;
                    }
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  _inputMode == _InputMode.bulk
                      ? '14枚並べるだけで、面子・待ちを自動判定します（副露がある手は「手動入力」を使ってください）。'
                      : '面子ごとに手動で入力します（副露・カンなど特殊な形もこちらで対応できます）。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),

                _historyPanel(),
                if (_history.isNotEmpty) const SizedBox(height: 12),

                if (_groupError != null) ...[
                  Text(_groupError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                ],

                if (_inputMode == _InputMode.bulk) ...[
                  _bulkPoolCard(),
                ] else ...[
                  SegmentedButton<_HandShape>(
                    segments: const [
                      ButtonSegment(value: _HandShape.normal, label: Text('通常手')),
                      ButtonSegment(value: _HandShape.chiitoi, label: Text('七対子')),
                      ButtonSegment(value: _HandShape.kokushi, label: Text('国士無双')),
                    ],
                    selected: {_handShape},
                    onSelectionChanged: (v) => _setHandShape(v.first),
                  ),
                  const SizedBox(height: 12),

                  if (isKokushiMode) ...[
                    _kokushiPanel(),
                  ] else if (!isChiitoi) ...[
                    _groupCard(index: 0, title: '面子1', capacity: _capacityForGroupNormal(0), isPair: false),
                    _groupCard(index: 1, title: '面子2', capacity: _capacityForGroupNormal(1), isPair: false),
                    _groupCard(index: 2, title: '面子3', capacity: _capacityForGroupNormal(2), isPair: false),
                    _groupCard(index: 3, title: '面子4', capacity: _capacityForGroupNormal(3), isPair: false),
                    _groupCard(index: 4, title: '雀頭', capacity: 2, isPair: true),
                  ] else ...[
                    const Text('七対子：牌を2枚ずつ選んでください'),
                    const SizedBox(height: 8),
                    for (int i = 0; i < 7; i++) _chiitoiPairCard(index: i),
                  ],
                ],

                const Divider(height: 28),

                Text('状況', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),

                _row(
                  '和了',
                  SegmentedButton<hs.WinType>(
                    segments: const [
                      ButtonSegment(value: hs.WinType.tsumo, label: Text('ツモ')),
                      ButtonSegment(value: hs.WinType.ron, label: Text('ロン')),
                    ],
                    selected: {winType},
                    onSelectionChanged: (s) => setState(() {
                      winType = s.first;
                      winningMeldIndex = -1;
                      if (winType == hs.WinType.tsumo) {
                        houtei = false;
                        chankan = false;
                      } else {
                        haitei = false;
                        rinshan = false;
                        tenhou = false;
                        chiihou = false;
                      }
                    }),
                  ),
                ),
                const SizedBox(height: 10),

                SwitchListTile(
                  title: const Text('親（東）'),
                  value: isDealer,
                  onChanged: (v) => setState(() {
                    isDealer = v;
                    if (isDealer) {
                      chiihou = false;
                    } else {
                      tenhou = false;
                    }
                  }),
                ),

                _row('自風', _windDropdown(value: seatWind, onChanged: (v) => setState(() => seatWind = v))),
                const SizedBox(height: 8),
                _row('場風', _windDropdown(value: roundWind, onChanged: (v) => setState(() => roundWind = v))),
                const SizedBox(height: 10),

                // ===== 待ち入力（手動入力モードのみ。おまかせ入力は自動判定）=====
                if (_inputMode == _InputMode.manual && !isKokushiMode) ...[
                  _row(
                    '待ち',
                    SegmentedButton<hs.WaitType>(
                      segments: const [
                        ButtonSegment(value: hs.WaitType.ryanmen, label: Text('両面')),
                        ButtonSegment(value: hs.WaitType.kanchan, label: Text('嵌張')),
                        ButtonSegment(value: hs.WaitType.penchan, label: Text('辺張')),
                        ButtonSegment(value: hs.WaitType.tanki, label: Text('単騎')),
                        ButtonSegment(value: hs.WaitType.shanpon, label: Text('シャンポン')),
                      ],
                      selected: {isChiitoi ? hs.WaitType.tanki : waitTypeSelected},
                      onSelectionChanged: isChiitoi
                          ? null
                          : (s) => setState(() {
                                waitTypeSelected = s.first;
                                winningMeldIndex = -1;
                              }),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isChiitoi ? '七対子は単騎固定です' : '選んだ待ちで符（待ち符）が決まります',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),

                  if (!isChiitoi && winType == hs.WinType.ron && waitTypeSelected == hs.WaitType.shanpon) ...[
                    const SizedBox(height: 10),
                    _wonMeldSelectorPanel(),
                  ],

                  const SizedBox(height: 10),

                  // 喰いタン
                  SwitchListTile(
                    title: const Text('喰いタンあり（副露の断么九を許可）'),
                    value: kuitanAllowed,
                    onChanged: (v) => setState(() => kuitanAllowed = v),
                  ),
                ],

                SwitchListTile(
                  title: const Text('立直'),
                  value: riichi,
                  onChanged: _effectiveMenzen
                      ? (v) => setState(() {
                            riichi = v;
                            if (!v) {
                              doubleRiichi = false;
                              ippatsu = false;
                              uraDora = 0;
                            }
                          })
                      : null,
                ),
                SwitchListTile(
                  title: const Text('ダブル立直'),
                  value: doubleRiichi,
                  onChanged: (riichi && _effectiveMenzen) ? (v) => setState(() => doubleRiichi = v) : null,
                ),
                SwitchListTile(
                  title: const Text('一発'),
                  value: ippatsu,
                  onChanged: (riichi && _effectiveMenzen) ? (v) => setState(() => ippatsu = v) : null,
                ),
                if (!_effectiveMenzen)
                  Text(
                    '※ 副露（鳴き）がある手では立直・ダブル立直・一発は成立しません',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),

                const SizedBox(height: 8),
                _row('ドラ', _stepper(dora, (v) => setState(() => dora = v.clamp(0, 20)))),
                const SizedBox(height: 8),
                _row('赤ドラ', _stepper(akaDora, (v) => setState(() => akaDora = v.clamp(0, 20)))),
                const SizedBox(height: 8),
                _row(
                  '裏ドラ',
                  _stepper(uraDora, riichi ? (v) => setState(() => uraDora = v.clamp(0, 20)) : null),
                ),
                if (!riichi)
                  Text(
                    '※ 裏ドラは立直時のみ加算できます',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),

                const SizedBox(height: 12),

                _specialWinFlagsPanel(),

                const SizedBox(height: 18),

                // スクロール末尾の余白（固定バー＋パレット分）
                const SizedBox(height: 260),
              ],
            ),
          ),

          _fixedActionBar(),

          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _inputMode == _InputMode.bulk
                                ? '入力先: 手牌（${_bulkTiles.length}/14枚）'
                                : (isKokushiMode
                                    ? '入力先: 国士無双（${_kokushiTiles.length}/14枚・么九牌のみ）'
                                    : (isChiitoi ? '入力先: ペア${_activeChiitoiPair + 1}' : '入力先: ${_activeGroup == 4 ? "雀頭" : "面子${_activeGroup + 1}"}')),
                          ),
                        ),
                        Text('タップで追加', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _suitTabs,
                    tabs: const [
                      Tab(text: '萬'),
                      Tab(text: '筒'),
                      Tab(text: '索'),
                      Tab(text: '字'),
                    ],
                  ),
                  SizedBox(
                    height: 140,
                    child: TabBarView(
                      controller: _suitTabs,
                      children: [
                        _tileGrid(_palette(Suit.m)),
                        _tileGrid(_palette(Suit.p)),
                        _tileGrid(_palette(Suit.s)),
                        _tileGrid(_palette(Suit.z)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  final String title;
  final String body;
  const _OnboardPage({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Text(body),
        ],
      ),
    );
  }
}