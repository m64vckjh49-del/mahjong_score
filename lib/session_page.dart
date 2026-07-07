// lib/session_page.dart
//
// 「台に1台置いて共有する」対局スコア画面。session.dart のシングルトン [session] を
// 直接参照・操作する（複数端末間の同期は行わない）。
//
// 画面構成:
//   - 対局未開始: プレイヤー名・開始点・返し点・ウマを設定する画面。
//   - 対局中: 各プレイヤーの持ち点・親番・本場・供託を表示し、
//     「和了を記録」「流局を記録」「履歴」「順位・精算」を行える。

import 'package:flutter/material.dart';
import 'session.dart';

int _firstOther(int n, int exclude) {
  for (var i = 0; i < n; i++) {
    if (i != exclude) return i;
  }
  return 0;
}

Widget _labeledDropdown<T>({
  required String label,
  required T value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) {
  return Row(
    children: [
      SizedBox(width: 70, child: Text(label)),
      const SizedBox(width: 12),
      Expanded(child: DropdownButton<T>(value: value, isExpanded: true, items: items, onChanged: onChanged)),
    ],
  );
}

class SessionPage extends StatefulWidget {
  const SessionPage({super.key});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  final List<TextEditingController> _nameCtrls =
      List.generate(4, (i) => TextEditingController(text: 'プレイヤー${i + 1}'));
  final TextEditingController _startCtrl = TextEditingController(text: '25000');
  final TextEditingController _returnCtrl = TextEditingController(text: '30000');
  UmaPreset _umaPreset = UmaPreset.m5_10;

  @override
  void dispose() {
    for (final c in _nameCtrls) {
      c.dispose();
    }
    _startCtrl.dispose();
    _returnCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('対局スコア')),
      body: AnimatedBuilder(
        animation: session,
        builder: (context, _) => session.isStarted ? _boardView(context) : _setupView(context),
      ),
    );
  }

  // ===== セットアップ画面 =====
  Widget _setupView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('対局の設定', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'この端末をテーブルに1台置いて、みんなで囲んで使う「対局スコア」です。\n'
          '和了・流局を記録すると、持ち点・親番・本場・供託を自動で計算します（他の端末とは同期しません）。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        for (int i = 0; i < 4; i++) ...[
          TextField(
            controller: _nameCtrls[i],
            decoration: InputDecoration(labelText: 'プレイヤー${i + 1}の名前'),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _startCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '開始点'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _returnCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '返し点（オカの基準）'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _labeledDropdown<UmaPreset>(
          label: 'ウマ',
          value: _umaPreset,
          items: [for (final u in UmaPreset.values) DropdownMenuItem(value: u, child: Text(u.label))],
          onChanged: (v) => setState(() => _umaPreset = v ?? UmaPreset.m5_10),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            final start = int.tryParse(_startCtrl.text) ?? 25000;
            final ret = int.tryParse(_returnCtrl.text) ?? 30000;
            session.start(
              names: _nameCtrls.map((c) => c.text).toList(),
              startingPoints: start,
              returnPoints: ret,
              umaPreset: _umaPreset,
            );
          },
          child: const Text('対局を開始'),
        ),
      ],
    );
  }

  // ===== 対局中画面 =====
  Widget _boardView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('第${session.handNumber}局'),
                Text('本場: ${session.honba}'),
                Text('供託: ${session.kyotaku}本'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < session.players.length; i++) _playerCard(context, i),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const _RecordWinDialog()),
              icon: const Icon(Icons.emoji_events),
              label: const Text('和了を記録'),
            ),
            OutlinedButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const _RecordDrawDialog()),
              icon: const Icon(Icons.replay),
              label: const Text('流局を記録'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showHistorySheet(context),
              icon: const Icon(Icons.history),
              label: const Text('履歴'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showSettlementDialog(context),
              icon: const Icon(Icons.leaderboard),
              label: const Text('順位・精算'),
            ),
            TextButton.icon(
              onPressed: () => _confirmReset(context),
              icon: const Icon(Icons.refresh),
              label: const Text('対局をリセット'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _playerCard(BuildContext context, int i) {
    final p = session.players[i];
    final isDealer = session.dealerIndex == i;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(isDealer ? '親' : '${i + 1}')),
        title: Text(p.name),
        subtitle: Text('${p.score}点'),
        trailing: OutlinedButton(
          onPressed: () => _confirmRiichi(context, i),
          child: const Text('リーチ'),
        ),
      ),
    );
  }

  void _confirmRiichi(BuildContext context, int i) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('リーチ宣言'),
        content: Text('${session.players[i].name} の持ち点から1000点引いて、供託に1本追加します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () {
              session.declareRiichi(i);
              Navigator.pop(context);
            },
            child: const Text('リーチする'),
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('対局をリセット'),
        content: const Text('記録した点数・履歴はすべて消えます。よろしいですか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () {
              session.reset();
              Navigator.pop(context);
            },
            child: const Text('リセットする'),
          ),
        ],
      ),
    );
  }

  void _showHistorySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                Text('局の履歴', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (session.history.isEmpty) const Text('まだ記録がありません。'),
                for (final h in session.history)
                  ListTile(
                    title: Text(h.headline),
                    subtitle: Text('本場${h.honbaAfter} / 供託${h.kyotakuAfter}本'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSettlementDialog(BuildContext context) {
    final rows = session.settle();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('現在の順位（ウマ・オカ込み）'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in rows)
                ListTile(
                  leading: CircleAvatar(child: Text('${r.rank}')),
                  title: Text(r.name),
                  subtitle: Text('素点 ${r.rawScore} / ウマ ${r.uma} / オカ ${r.oka}'),
                  trailing: Text('${r.finalScore}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('閉じる')),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _confirmReset(context);
            },
            child: const Text('この結果で対局を終了'),
          ),
        ],
      ),
    );
  }
}

enum _WinKind { ron, tsumo }

class _RecordWinDialog extends StatefulWidget {
  const _RecordWinDialog();

  @override
  State<_RecordWinDialog> createState() => _RecordWinDialogState();
}

class _RecordWinDialogState extends State<_RecordWinDialog> {
  _WinKind _kind = _WinKind.ron;
  late int _winnerIndex;
  late int _loserIndex;
  final TextEditingController _pointsCtrl = TextEditingController(text: '1000');
  final TextEditingController _dealerPayCtrl = TextEditingController(text: '1000');
  final TextEditingController _nonDealerPayCtrl = TextEditingController(text: '500');

  @override
  void initState() {
    super.initState();
    _winnerIndex = 0;
    _loserIndex = _firstOther(session.players.length, _winnerIndex);
  }

  @override
  void dispose() {
    _pointsCtrl.dispose();
    _dealerPayCtrl.dispose();
    _nonDealerPayCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = session.players.map((p) => p.name).toList();
    final isDealerWin = _winnerIndex == session.dealerIndex;
    return AlertDialog(
      title: const Text('和了を記録'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_WinKind>(
              segments: const [
                ButtonSegment(value: _WinKind.ron, label: Text('ロン')),
                ButtonSegment(value: _WinKind.tsumo, label: Text('ツモ')),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            const SizedBox(height: 12),
            _labeledDropdown<int>(
              label: '和了者',
              value: _winnerIndex,
              items: [for (int i = 0; i < names.length; i++) DropdownMenuItem(value: i, child: Text(names[i]))],
              onChanged: (v) => setState(() {
                _winnerIndex = v ?? 0;
                if (_loserIndex == _winnerIndex) {
                  _loserIndex = _firstOther(names.length, _winnerIndex);
                }
              }),
            ),
            const SizedBox(height: 12),
            if (_kind == _WinKind.ron) ...[
              _labeledDropdown<int>(
                label: '放銃者',
                value: _loserIndex,
                items: [
                  for (int i = 0; i < names.length; i++)
                    if (i != _winnerIndex) DropdownMenuItem(value: i, child: Text(names[i])),
                ],
                onChanged: (v) => setState(() => _loserIndex = v ?? _firstOther(names.length, _winnerIndex)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pointsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '和了点（本場・供託は自動加算）'),
              ),
            ] else ...[
              if (isDealerWin) ...[
                TextField(
                  controller: _dealerPayCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '子3人が払う点数（オール）'),
                ),
              ] else ...[
                TextField(
                  controller: _dealerPayCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '親が払う点数'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nonDealerPayCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '子（他2人）が払う点数'),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: () {
            if (_kind == _WinKind.ron) {
              final points = int.tryParse(_pointsCtrl.text) ?? 0;
              session.recordRon(winnerIndex: _winnerIndex, loserIndex: _loserIndex, points: points);
            } else {
              final dealerPay = int.tryParse(_dealerPayCtrl.text) ?? 0;
              final nonDealerPay = isDealerWin ? dealerPay : (int.tryParse(_nonDealerPayCtrl.text) ?? 0);
              session.recordTsumo(winnerIndex: _winnerIndex, dealerPay: dealerPay, nonDealerPay: nonDealerPay);
            }
            Navigator.pop(context);
          },
          child: const Text('記録する'),
        ),
      ],
    );
  }
}

class _RecordDrawDialog extends StatefulWidget {
  const _RecordDrawDialog();

  @override
  State<_RecordDrawDialog> createState() => _RecordDrawDialogState();
}

class _RecordDrawDialogState extends State<_RecordDrawDialog> {
  late List<bool> _tenpai;

  @override
  void initState() {
    super.initState();
    _tenpai = List.filled(session.players.length, false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('流局を記録'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('聴牌していたプレイヤーにチェックを入れてください。'),
          for (int i = 0; i < session.players.length; i++)
            CheckboxListTile(
              title: Text(session.players[i].name),
              value: _tenpai[i],
              onChanged: (v) => setState(() => _tenpai[i] = v ?? false),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: () {
            final tenpaiIndexes = [for (int i = 0; i < _tenpai.length; i++) if (_tenpai[i]) i];
            session.recordDraw(tenpaiIndexes: tenpaiIndexes);
            Navigator.pop(context);
          },
          child: const Text('記録する'),
        ),
      ],
    );
  }
}
