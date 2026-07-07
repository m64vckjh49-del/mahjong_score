// test/session_test.dart
//
// session.dart（台に1台置いて共有する対局スコア管理エンジン）に対するユニットテスト。
// 素点の収支が合うこと（ゼロサム）、親番・本場・供託の自動管理、ウマ・オカを
// 加算した精算結果の正しさを確認する。

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_score/session.dart';

int totalScore(MahjongSession s) => s.players.fold(0, (sum, p) => sum + p.score);

void main() {
  group('開始', () {
    test('start() で全員が開始点を持ち、親は0番目、本場・供託は0になる', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D'], startingPoints: 25000);
      expect(s.isStarted, isTrue);
      expect(s.players.map((p) => p.score), everyElement(25000));
      expect(s.dealerIndex, 0);
      expect(s.honba, 0);
      expect(s.kyotaku, 0);
      expect(s.handNumber, 1);
    });
  });

  group('ロン', () {
    test('親（0番）以外が和了すると、親が交代し本場がリセットされる', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D']);
      s.recordRon(winnerIndex: 1, loserIndex: 2, points: 5800);
      expect(s.players[1].score, 25000 + 5800);
      expect(s.players[2].score, 25000 - 5800);
      expect(s.players[0].score, 25000);
      expect(s.players[3].score, 25000);
      expect(totalScore(s), 25000 * 4);
      expect(s.dealerIndex, 1); // 親交代
      expect(s.honba, 0);
    });

    test('親（0番）が和了すると連荘し、本場が+1される', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D']);
      s.recordRon(winnerIndex: 0, loserIndex: 2, points: 2900);
      expect(s.dealerIndex, 0); // 連荘
      expect(s.honba, 1);
      expect(totalScore(s), 25000 * 4);
    });

    test('本場がある場合、ロン点に本場×300が上乗せされる', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D']);
      s.recordRon(winnerIndex: 0, loserIndex: 1, points: 1000); // 連荘 → 本場1
      s.recordRon(winnerIndex: 2, loserIndex: 3, points: 2000);
      // 本場1 → +300 (winnerが勝者、loserが支払う)
      expect(s.players[2].score, 25000 + 2000 + 300);
      expect(s.players[3].score, 25000 - 2000 - 300);
    });

    test('供託（リーチ棒）は和了者が総取りし、供託本数は0に戻る', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D']);
      s.declareRiichi(0);
      s.declareRiichi(1);
      expect(s.players[0].score, 25000 - 1000);
      expect(s.players[1].score, 25000 - 1000);
      expect(s.kyotaku, 2);

      s.recordRon(winnerIndex: 2, loserIndex: 3, points: 1000);
      expect(s.players[2].score, 25000 + 1000 + 2000); // 和了点 + 供託2本分
      expect(s.kyotaku, 0);
      // 供託分は既に宣言時に各自の持ち点から引かれているため、全体の収支は合う。
      expect(totalScore(s), 25000 * 4);
    });
  });

  group('ツモ', () {
    test('子がツモると、親はdealerPay、他の子はnonDealerPayを支払う', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D']);
      // Bがツモ和了（親Aから2000, 子C・Dから1000ずつ）
      s.recordTsumo(winnerIndex: 1, dealerPay: 2000, nonDealerPay: 1000);
      expect(s.players[0].score, 25000 - 2000);
      expect(s.players[1].score, 25000 + 2000 + 1000 + 1000);
      expect(s.players[2].score, 25000 - 1000);
      expect(s.players[3].score, 25000 - 1000);
      expect(totalScore(s), 25000 * 4);
      expect(s.dealerIndex, 1); // 親交代
    });

    test('親がツモると全員が同額（オール）を支払い、連荘する', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D']);
      s.recordTsumo(winnerIndex: 0, dealerPay: 2000, nonDealerPay: 2000);
      expect(s.players[0].score, 25000 + 2000 * 3);
      expect(s.players[1].score, 25000 - 2000);
      expect(s.players[2].score, 25000 - 2000);
      expect(s.players[3].score, 25000 - 2000);
      expect(totalScore(s), 25000 * 4);
      expect(s.dealerIndex, 0);
      expect(s.honba, 1);
    });
  });

  group('流局', () {
    test('1人テンパイの場合、ノーテン3人が1000点ずつ払いテンパイが3000点受け取る', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D']);
      s.recordDraw(tenpaiIndexes: [2]);
      expect(s.players[2].score, 25000 + 3000);
      expect(s.players[0].score, 25000 - 1000);
      expect(s.players[1].score, 25000 - 1000);
      expect(s.players[3].score, 25000 - 1000);
      expect(totalScore(s), 25000 * 4);
    });

    test('全員テンパイ・全員ノーテンの場合は点数移動なし', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D']);
      s.recordDraw(tenpaiIndexes: [0, 1, 2, 3]);
      expect(s.players.map((p) => p.score), everyElement(25000));

      final s2 = MahjongSession();
      s2.start(names: ['A', 'B', 'C', 'D']);
      s2.recordDraw(tenpaiIndexes: []);
      expect(s2.players.map((p) => p.score), everyElement(25000));
    });

    test('親がノーテンの場合は親が流れ、親がテンパイの場合は連荘する', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D']);
      s.recordDraw(tenpaiIndexes: [1]); // 親(0)はノーテン
      expect(s.dealerIndex, 1);
      expect(s.honba, 0);

      final s2 = MahjongSession();
      s2.start(names: ['A', 'B', 'C', 'D']);
      s2.recordDraw(tenpaiIndexes: [0]); // 親(0)がテンパイ
      expect(s2.dealerIndex, 0);
      expect(s2.honba, 1);
    });
  });

  group('精算', () {
    test('ウマなし・オカなしの場合、素点の順位がそのまま最終順位になる', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D'], startingPoints: 25000, returnPoints: 25000, umaPreset: UmaPreset.none);
      s.recordRon(winnerIndex: 1, loserIndex: 2, points: 8000);
      final rows = s.settle();
      expect(rows.map((r) => r.name), ['B', 'A', 'D', 'C']);
      expect(rows.first.rank, 1);
      expect(rows.first.finalScore, 25000 + 8000);
      expect(rows.every((r) => r.uma == 0 && r.oka == 0), isTrue);
    });

    test('ウマ5-10・オカありの場合、トップにオカが加算されウマが着順どおりに配分される', () {
      final s = MahjongSession();
      s.start(
        names: ['A', 'B', 'C', 'D'],
        startingPoints: 25000,
        returnPoints: 30000,
        umaPreset: UmaPreset.m5_10,
      );
      // 素点差をつけるためロンを1回記録（親Aはそのまま/Bが最下位に沈む）
      s.recordRon(winnerIndex: 0, loserIndex: 1, points: 8000); // A: 33000, B: 17000
      final rows = s.settle();
      final oka = (30000 - 25000) * 4; // 20000
      // Aが1位: 33000 + 10000(ウマ) + 20000(オカ)
      final aRow = rows.firstWhere((r) => r.name == 'A');
      expect(aRow.rank, 1);
      expect(aRow.uma, 10000);
      expect(aRow.oka, oka);
      expect(aRow.finalScore, 33000 + 10000 + oka);

      final bRow = rows.firstWhere((r) => r.name == 'B');
      expect(bRow.rank, 4);
      expect(bRow.uma, -10000);
      expect(bRow.oka, 0);
      expect(bRow.finalScore, 17000 - 10000);

      // 同点だったC・Dは2位・3位に+5000/-5000のウマが乗る。
      final cRow = rows.firstWhere((r) => r.name == 'C');
      final dRow = rows.firstWhere((r) => r.name == 'D');
      expect({cRow.uma, dRow.uma}, {5000, -5000});
    });

    test('未収の供託はトップの精算に加算される', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D'], returnPoints: 25000, umaPreset: UmaPreset.none);
      // B・C・Dがリーチして持ち点を減らすことで、Aが手を出さないまま素点トップになる。
      s.declareRiichi(1);
      s.declareRiichi(2);
      s.declareRiichi(3);
      // この3本の供託を誰も収集しないまま対局終了（＝和了せずに精算）。
      final rows = s.settle();
      final aRow = rows.firstWhere((r) => r.name == 'A');
      expect(s.players[0].score, 25000);
      expect(aRow.rank, 1);
      // Aは素点トップ（25000）に、未収の供託3本分（3000点）が加算される。
      expect(aRow.rawScore, 25000 + 3000);
      expect(aRow.finalScore, 28000);
    });
  });

  group('履歴', () {
    test('記録するたびに履歴の先頭に追加される', () {
      final s = MahjongSession();
      s.start(names: ['A', 'B', 'C', 'D']);
      s.recordRon(winnerIndex: 1, loserIndex: 2, points: 1000);
      s.recordDraw(tenpaiIndexes: [0]);
      expect(s.history.length, 2);
      expect(s.history.first.headline, contains('流局'));
      expect(s.history.last.headline, contains('ロン和了'));
    });
  });
}
