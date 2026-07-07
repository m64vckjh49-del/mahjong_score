// lib/session.dart
//
// 「複数局にまたがる持ち点を、1台の端末をテーブルに置いてみんなで囲んで記録する」
// ための対局スコア管理エンジン。
//
// 設計方針（ユーザーからの明示的な要望に基づく）:
//   - 複数端末間のネットワーク同期は行わない（B案：台に1台置いて共有）。
//   - サーバー・アカウント登録などのバックエンドは持たない。
//   - 面子入力側の「1翻ふ計算ができない人でも和了れる」体験と同様に、
//     持ち点計算（ウマ・オカ・本場・供託）ができない人でも対局を回せることを目指す。
//
// 使い方の想定:
//   1. 対局開始時に、プレイヤー名・開始点・ウマ・オカを設定する（start）。
//   2. 各局の結果（ロン/ツモ/流局）を記録すると、持ち点・親番・本場・供託が自動更新される。
//   3. 対局終了時に settle() を呼ぶと、着順に応じたウマと、オカ（トップ総取り分）を
//      加算した最終順位表が得られる。

import 'package:flutter/foundation.dart';

/// ウマのプリセット（着順ボーナス）。値は「1位, 2位, 3位, 4位」の順の点数。
/// プレイヤー数が4人未満の場合は、上位から必要な人数分だけを使用する。
enum UmaPreset { none, m5_10, m10_20, m10_30, m20_30 }

extension UmaPresetValues on UmaPreset {
  String get label => switch (this) {
        UmaPreset.none => 'ウマなし',
        UmaPreset.m5_10 => '5-10',
        UmaPreset.m10_20 => '10-20',
        UmaPreset.m10_30 => '10-30',
        UmaPreset.m20_30 => '20-30',
      };

  /// [1位, 2位, 3位, 4位] の順。
  List<int> get values => switch (this) {
        UmaPreset.none => const [0, 0, 0, 0],
        UmaPreset.m5_10 => const [10000, 5000, -5000, -10000],
        UmaPreset.m10_20 => const [20000, 10000, -10000, -20000],
        UmaPreset.m10_30 => const [30000, 10000, -10000, -30000],
        UmaPreset.m20_30 => const [30000, 20000, -20000, -30000],
      };
}

class SessionPlayer {
  String name;
  int score;
  SessionPlayer({required this.name, required this.score});
}

/// 1局分の記録（履歴表示用・取り消し用）。
///
/// 「取り消し（undoLast）」のために、この局を記録する直前の状態
/// （本場・供託・親番・リーチ供託の宣言状況）も保持しておく。
class HandRecord {
  final DateTime at;
  final String headline;
  final List<int> deltas;
  final int honbaAfter;
  final int kyotakuAfter;
  final int dealerIndexAfter;
  final int honbaBefore;
  final int kyotakuBefore;
  final int dealerIndexBefore;
  final int handNumberBefore;
  final List<bool> riichiBefore;
  const HandRecord({
    required this.at,
    required this.headline,
    required this.deltas,
    required this.honbaAfter,
    required this.kyotakuAfter,
    required this.dealerIndexAfter,
    required this.honbaBefore,
    required this.kyotakuBefore,
    required this.dealerIndexBefore,
    required this.handNumberBefore,
    required this.riichiBefore,
  });
}

/// 最終順位表の1行。
class SettlementRow {
  final String name;
  final int rawScore; // 素点（残った供託の加算込み）
  final int uma;
  final int oka;
  final int finalScore;
  final int rank; // 1-indexed
  const SettlementRow({
    required this.name,
    required this.rawScore,
    required this.uma,
    required this.oka,
    required this.finalScore,
    required this.rank,
  });
}

/// 複数局にまたがる持ち点を管理するセッション本体。
///
/// 1端末内で完結するシングルトンとして [session] を公開している
/// （複数端末間のネットワーク同期は意図的に実装していない）。
class MahjongSession extends ChangeNotifier {
  List<SessionPlayer> players = [];
  int startingPoints = 25000;
  int returnPoints = 30000; // オカ計算の基準となる「返し点」
  UmaPreset umaPreset = UmaPreset.m5_10;
  int honba = 0;
  int kyotaku = 0;
  int dealerIndex = 0;
  int handNumber = 1; // 東1局=1, 東2局=2 … という簡易カウンタ（風表示はしない）
  bool _started = false;
  final List<HandRecord> history = [];

  /// 今回の局で各プレイヤーがリーチを宣言済みかどうか。
  /// 1局が終わる（[_applyDeltas]が呼ばれる）たびに全員falseへリセットされる。
  List<bool> riichiThisHand = [];

  bool get isStarted => _started;
  int get playerCount => players.length;

  void start({
    required List<String> names,
    int startingPoints = 25000,
    int returnPoints = 30000,
    UmaPreset umaPreset = UmaPreset.m5_10,
  }) {
    players = names.map((n) => SessionPlayer(name: n.trim().isEmpty ? '?' : n.trim(), score: startingPoints)).toList();
    this.startingPoints = startingPoints;
    this.returnPoints = returnPoints;
    this.umaPreset = umaPreset;
    honba = 0;
    kyotaku = 0;
    dealerIndex = 0;
    handNumber = 1;
    history.clear();
    riichiThisHand = List.filled(players.length, false);
    _started = true;
    notifyListeners();
  }

  void reset() {
    players = [];
    history.clear();
    riichiThisHand = [];
    _started = false;
    honba = 0;
    kyotaku = 0;
    dealerIndex = 0;
    handNumber = 1;
    notifyListeners();
  }

  void _applyDeltas(
    List<int> deltas, {
    required String headline,
    required bool dealerContinues,
    bool consumeKyotaku = false,
  }) {
    assert(deltas.length == players.length);
    final honbaBefore = honba;
    final kyotakuBefore = kyotaku;
    final dealerIndexBefore = dealerIndex;
    final handNumberBefore = handNumber;
    final riichiBefore = List<bool>.from(riichiThisHand);

    for (var i = 0; i < players.length; i++) {
      players[i].score += deltas[i];
    }
    if (consumeKyotaku) kyotaku = 0;
    if (dealerContinues) {
      honba += 1;
    } else {
      honba = 0;
      dealerIndex = (dealerIndex + 1) % players.length;
    }
    handNumber += 1;
    history.insert(
      0,
      HandRecord(
        at: DateTime.now(),
        headline: headline,
        deltas: deltas,
        honbaAfter: honba,
        kyotakuAfter: kyotaku,
        dealerIndexAfter: dealerIndex,
        honbaBefore: honbaBefore,
        kyotakuBefore: kyotakuBefore,
        dealerIndexBefore: dealerIndexBefore,
        handNumberBefore: handNumberBefore,
        riichiBefore: riichiBefore,
      ),
    );
    riichiThisHand = List.filled(players.length, false);
    notifyListeners();
  }

  /// リーチ宣言（本人の持ち点から1000点引き、供託を1本増やす）。
  ///
  /// 以下の場合は宣言できず、何も変更せずに`false`を返す:
  ///   - 持ち点が1000点未満（リーチ棒を払えない）
  ///   - この局で既にリーチ宣言済み（二重宣言防止）
  bool declareRiichi(int playerIndex) {
    if (players[playerIndex].score < 1000) return false;
    if (riichiThisHand.length > playerIndex && riichiThisHand[playerIndex]) return false;
    players[playerIndex].score -= 1000;
    kyotaku += 1;
    if (riichiThisHand.length != players.length) {
      riichiThisHand = List.filled(players.length, false);
    }
    riichiThisHand[playerIndex] = true;
    notifyListeners();
    return true;
  }

  /// リーチ宣言の取り消し（誤宣言時の訂正用）。
  /// この局でリーチ宣言済みの場合のみ有効で、1000点を返し供託を1本減らす。
  bool cancelRiichi(int playerIndex) {
    if (riichiThisHand.length <= playerIndex || !riichiThisHand[playerIndex]) return false;
    players[playerIndex].score += 1000;
    kyotaku -= 1;
    riichiThisHand[playerIndex] = false;
    notifyListeners();
    return true;
  }

  /// 直前の局の記録を取り消し、その局を記録する前の状態へ巻き戻す。
  /// 履歴が無ければ何もせず`false`を返す。
  bool undoLast() {
    if (history.isEmpty) return false;
    final last = history.first;
    for (var i = 0; i < players.length; i++) {
      players[i].score -= last.deltas[i];
    }
    honba = last.honbaBefore;
    kyotaku = last.kyotakuBefore;
    dealerIndex = last.dealerIndexBefore;
    handNumber = last.handNumberBefore;
    riichiThisHand = List<bool>.from(last.riichiBefore);
    history.removeAt(0);
    notifyListeners();
    return true;
  }

  /// ロン和了を記録する。[points] は和了点そのもの（本場・供託は自動加算するため含めない）。
  void recordRon({
    required int winnerIndex,
    required int loserIndex,
    required int points,
  }) {
    final honbaBonus = honba * 300;
    final deltas = List<int>.filled(players.length, 0);
    deltas[winnerIndex] += points + honbaBonus + kyotaku * 1000;
    deltas[loserIndex] -= points + honbaBonus;
    final dealerContinues = winnerIndex == dealerIndex;
    _applyDeltas(
      deltas,
      headline: '${players[winnerIndex].name} のロン和了（${players[loserIndex].name}から $points点）',
      dealerContinues: dealerContinues,
      consumeKyotaku: true,
    );
  }

  /// ツモ和了を記録する。[dealerPay] は親の支払い額、[nonDealerPay] は子の支払い額
  /// （親がツモった場合は同額を渡せば「オール」を表現できる）。
  void recordTsumo({
    required int winnerIndex,
    required int dealerPay,
    required int nonDealerPay,
  }) {
    final honbaBonus = honba * 100; // 1人あたり100点（総取り300点/本場）が通例
    final deltas = List<int>.filled(players.length, 0);
    var total = 0;
    for (var i = 0; i < players.length; i++) {
      if (i == winnerIndex) continue;
      final pay = (i == dealerIndex) ? dealerPay : nonDealerPay;
      final payWithHonba = pay + honbaBonus;
      deltas[i] -= payWithHonba;
      total += payWithHonba;
    }
    deltas[winnerIndex] += total + kyotaku * 1000;
    final dealerContinues = winnerIndex == dealerIndex;
    _applyDeltas(
      deltas,
      headline: '${players[winnerIndex].name} のツモ和了',
      dealerContinues: dealerContinues,
      consumeKyotaku: true,
    );
  }

  /// 流局（ノーテン罰符）を記録する。[tenpaiIndexes] は聴牌していたプレイヤーの
  /// インデックス一覧（0人〜全員まで指定可）。
  void recordDraw({required List<int> tenpaiIndexes}) {
    final n = players.length;
    final tenpaiCount = tenpaiIndexes.length;
    final deltas = List<int>.filled(n, 0);
    if (tenpaiCount > 0 && tenpaiCount < n) {
      final notenCount = n - tenpaiCount;
      const totalPenalty = 3000;
      final payEach = totalPenalty ~/ notenCount;
      final receiveEach = totalPenalty ~/ tenpaiCount;
      for (var i = 0; i < n; i++) {
        if (tenpaiIndexes.contains(i)) {
          deltas[i] += receiveEach;
        } else {
          deltas[i] -= payEach;
        }
      }
    }
    final dealerTenpai = tenpaiIndexes.contains(dealerIndex);
    final headline = tenpaiCount == 0
        ? '流局（全員ノーテン）'
        : tenpaiCount == n
            ? '流局（全員テンパイ）'
            : '流局（テンパイ: ${tenpaiIndexes.map((i) => players[i].name).join('、')}）';
    _applyDeltas(
      deltas,
      headline: headline,
      dealerContinues: dealerTenpai,
      consumeKyotaku: false,
    );
  }

  /// ウマ・オカを加算した最終順位表を返す（対局中いつでも「暫定順位」として呼べる）。
  List<SettlementRow> settle() {
    final n = players.length;
    final indexed = List.generate(n, (i) => i)..sort((a, b) => players[b].score.compareTo(players[a].score));
    final umaValues = umaPreset.values;
    final oka = (returnPoints - startingPoints) * n;
    final leftoverKyotaku = kyotaku * 1000;
    final rows = <SettlementRow>[];
    for (var rank = 0; rank < n; rank++) {
      final idx = indexed[rank];
      final p = players[idx];
      final uma = rank < umaValues.length ? umaValues[rank] : 0;
      final okaForThis = rank == 0 ? oka : 0;
      final rawScore = p.score + (rank == 0 ? leftoverKyotaku : 0);
      rows.add(SettlementRow(
        name: p.name,
        rawScore: rawScore,
        uma: uma,
        oka: okaForThis,
        finalScore: rawScore + uma + okaForThis,
        rank: rank + 1,
      ));
    }
    return rows;
  }
}

/// アプリ全体で1つだけ存在する対局セッション。
/// 「台に1台置いて共有する」運用を想定しているため、複数端末間の同期は行わない。
final MahjongSession session = MahjongSession();
