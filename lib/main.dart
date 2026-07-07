import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mahjong_score/meld_input.dart'; // ← ここに追加
import 'package:mahjong_score/session.dart';
import 'package:mahjong_score/unload_guard.dart';

void main() => runApp(const MyApp());

int ceilTo100(int x) => ((x + 99) ~/ 100) * 100;

class Points {
  final int? ron;
  final int? tsumoFromDealer;
  final int? tsumoFromNonDealer;
  final String limitName;
  final int han;
  final int fuRounded;
  const Points({
    required this.han,
    required this.fuRounded,
    this.ron,
    this.tsumoFromDealer,
    this.tsumoFromNonDealer,
    this.limitName = '',
  });
}

/// 翻・符 → 点数（満貫以上込み）
Points calcPoints({
  required int han,
  required int fu,
  required bool isDealer,
  required bool isTsumo,
}) {
  // 符の丸め（七対子25は例外だがUIで選べるようにしておく）
  final fuRounded = (fu == 25) ? 25 : max(20, ((fu + 9) ~/ 10) * 10);

  // 上限判定（一般的な基準）
  String limit = '';
  int? limitBase;
  if (han >= 13) { limit = '数え役満'; limitBase = 8000; }
  else if (han >= 11) { limit = '三倍満'; limitBase = 6000; }
  else if (han >= 8) { limit = '倍満'; limitBase = 4000; }
  else if (han >= 6) { limit = '跳満'; limitBase = 3000; }
  else if (han == 5 || (han == 4 && fuRounded >= 40) || (han == 3 && fuRounded >= 70)) {
    limit = '満貫'; limitBase = 2000;
  }

  final base = limitBase ?? (fuRounded * (1 << (han + 2)));

  if (!isTsumo) {
    final mult = isDealer ? 6 : 4;
    return Points(
      han: han,
      fuRounded: fuRounded,
      ron: ceilTo100(base * mult),
      limitName: limit,
    );
  } else {
    if (isDealer) {
      final pay = ceilTo100(base * 2);
      return Points(
        han: han,
        fuRounded: fuRounded,
        tsumoFromDealer: pay,
        tsumoFromNonDealer: pay,
        limitName: limit,
      );
    } else {
      return Points(
        han: han,
        fuRounded: fuRounded,
        tsumoFromDealer: ceilTo100(base * 2),
        tsumoFromNonDealer: ceilTo100(base),
        limitName: limit,
      );
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // 対局スコア（session.dart）は永続化しておらず、メモリ上にしかデータが
    // 存在しない。対局中にタブを閉じる/リロードすると警告なく記録が消えて
    // しまうため、対局が始まっている間はブラウザの離脱確認ダイアログを出す。
    session.addListener(_syncUnloadGuard);
    _syncUnloadGuard();
  }

  void _syncUnloadGuard() {
    if (session.isStarted) {
      UnloadGuard.enable();
    } else {
      UnloadGuard.disable();
    }
  }

  @override
  void dispose() {
    session.removeListener(_syncUnloadGuard);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '麻雀点数',
      theme: ThemeData(useMaterial3: true),
      home: const MeldInputPage(),
    );
  }
}

class ScoreHome extends StatefulWidget {
  const ScoreHome({super.key});

  @override
  State<ScoreHome> createState() => _ScoreHomeState();
}

class _ScoreHomeState extends State<ScoreHome> {
  int han = 1;
  int fu = 30;
  bool isDealer = false;
  bool isTsumo = true;

  @override
  Widget build(BuildContext context) {
    final points = calcPoints(han: han, fu: fu, isDealer: isDealer, isTsumo: isTsumo);

    return Scaffold(
      appBar: AppBar(title: const Text('麻雀 点数計算（翻・符）')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row(
              label: '翻',
              child: _stepper(
                value: han,
                onChanged: (v) => setState(() => han = v.clamp(0, 20)),
              ),
            ),
            const SizedBox(height: 12),
            _row(
              label: '符',
              child: DropdownButton<int>(
                value: fu,
                items: const [20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 110]
                    .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                    .toList(),
                onChanged: (v) => setState(() => fu = v ?? 30),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('親（東）'),
              value: isDealer,
              onChanged: (v) => setState(() => isDealer = v),
            ),
            SwitchListTile(
              title: const Text('ツモ（OFFでロン）'),
              value: isTsumo,
              onChanged: (v) => setState(() => isTsumo = v),
            ),
            const Divider(height: 24),
            Text('結果', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (points.limitName.isNotEmpty)
              Text('上限: ${points.limitName}', style: Theme.of(context).textTheme.bodyLarge),
            Text('合計: ${points.han}翻 ${points.fuRounded}符', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 12),
            _resultCard(points),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(Points p) {
    if (isTsumo) {
      if (isDealer) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('親ツモ: オール ${p.tsumoFromDealer}'),
          ),
        );
      } else {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('子ツモ: 親 ${p.tsumoFromDealer} / 子 ${p.tsumoFromNonDealer}'),
          ),
        );
      }
    } else {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('ロン: ${p.ron}'),
        ),
      );
    }
  }

  Widget _row({required String label, required Widget child}) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label)),
        const SizedBox(width: 12),
        Expanded(child: Align(alignment: Alignment.centerLeft, child: child)),
      ],
    );
  }

  Widget _stepper({required int value, required ValueChanged<int> onChanged}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(onPressed: () => onChanged(value - 1), icon: const Icon(Icons.remove)),
        Text('$value', style: const TextStyle(fontSize: 18)),
        IconButton(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add)),
      ],
    );
  }
}