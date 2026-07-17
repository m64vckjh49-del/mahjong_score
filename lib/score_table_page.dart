// lib/score_table_page.dart
//
// 「点数早見表」画面。
// hand_scoring.dart の実際の得点計算ロジック（calcBasePoints / resolveLimit /
// ceilTo100）をそのまま再利用して、翻・符ごとの支払い点数を一覧表示する。
// 独自に点数テーブルを持たず、実際の計算経路と常に一致することを保証する。
import 'package:flutter/material.dart';
import 'hand_scoring.dart';
import 'ui_theme.dart';

/// 1〜4翻で早見表に載せる符の一覧（実戦で登場する代表的な符）。
const List<int> _fuValues = [20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 110];

/// 5翻以上の限度役（頭打ち）を上から順に並べたもの。
/// 符に依存しないため、代表値として fu=30 で計算する（limit適用時は符を使わない）。
const List<int> _limitHans = [5, 6, 8, 11, 13];

class ScoreTablePage extends StatelessWidget {
  const ScoreTablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🀄 点数早見表'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: const GradientAppBarBackground(),
      ),
      body: ListView(
        key: const Key('scoreTableList'),
        padding: const EdgeInsets.all(12),
        children: [
          for (final han in [1, 2, 3, 4]) _HanTable(han: han),
          _LimitTable(hans: _limitHans),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// 子ロン／親ロン／子ツモ／親ツモの支払い額を1件分にまとめたもの。
///
/// ツモの支払いは和了者が子か親かで変わる（hand_scoring.dart の scoreHand 参照）。
/// - 子がツモ和了：親が base*2、他の子は base ずつ支払う（＝「子/親」表記）。
/// - 親がツモ和了：子3人が base*2 ずつ支払う（＝全員同額の「オール」表記）。
/// base*2 の値は上記どちらのケースでも同じ計算式になるため、列は3本で足りる。
class _Payouts {
  final String label;
  final int ronNonDealer;
  final int ronDealer;
  final int tsumoChildPay; // 子がツモ和了したときに、他の子が払う額
  final int tsumoParentPay; // 子がツモ和了したときに親が払う額／親がツモ和了したときに子全員が払う額

  const _Payouts({
    required this.label,
    required this.ronNonDealer,
    required this.ronDealer,
    required this.tsumoChildPay,
    required this.tsumoParentPay,
  });

  /// 通常の翻・符から計算する。
  factory _Payouts.fromHanFu(int han, int fuRounded) {
    final base = calcBasePoints(han, fuRounded);
    final limit = resolveLimit(han, fuRounded);
    return _Payouts(
      label: limit?.name ?? '$fuRounded符',
      ronNonDealer: ceilTo100(base * 4),
      ronDealer: ceilTo100(base * 6),
      tsumoChildPay: ceilTo100(base),
      tsumoParentPay: ceilTo100(base * 2),
    );
  }
}

class _HanTable extends StatelessWidget {
  const _HanTable({required this.han});

  final int han;

  @override
  Widget build(BuildContext context) {
    final rows = <_Payouts>[];
    final seenLimits = <String>{};
    for (final fu in _fuValues) {
      final payout = _Payouts.fromHanFu(han, fu);
      final limit = resolveLimit(han, fu);
      if (limit != null) {
        // 満貫などの頭打ちに達したら、以降の符違いは同じ点数なので1行だけ残す。
        if (seenLimits.contains(limit.name)) continue;
        seenLimits.add(limit.name);
      }
      rows.add(payout);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '$han翻',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            _PayoutTable(rows: rows),
          ],
        ),
      ),
    );
  }
}

class _LimitTable extends StatelessWidget {
  const _LimitTable({required this.hans});

  final List<int> hans;

  @override
  Widget build(BuildContext context) {
    final rows = <_Payouts>[];
    final seenLimits = <String>{};
    for (final han in hans) {
      final payout = _Payouts.fromHanFu(han, 30);
      final limit = resolveLimit(han, 30);
      final name = limit?.name ?? payout.label;
      if (seenLimits.contains(name)) continue;
      seenLimits.add(name);
      rows.add(payout);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '5翻以上（満貫〜役満）',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            _PayoutTable(rows: rows, showFuLabel: false),
          ],
        ),
      ),
    );
  }
}

class _PayoutTable extends StatelessWidget {
  const _PayoutTable({required this.rows, this.showFuLabel = true});

  final List<_Payouts> rows;
  final bool showFuLabel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 32,
        columns: [
          DataColumn(label: Text(showFuLabel ? '符' : '役')),
          const DataColumn(label: Text('子ロン'), numeric: true),
          const DataColumn(label: Text('親ロン'), numeric: true),
          const DataColumn(label: Text('子ツモ(子/親)'), numeric: true),
          const DataColumn(label: Text('親ツモ'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                DataCell(Text(r.label)),
                DataCell(Text('${r.ronNonDealer}')),
                DataCell(Text('${r.ronDealer}')),
                DataCell(Text('${r.tsumoChildPay}/${r.tsumoParentPay}')),
                DataCell(Text('${r.tsumoParentPay}オール')),
              ],
            ),
        ],
      ),
    );
  }
}
