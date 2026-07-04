import 'package:flutter/material.dart';

import '../data/entry_store.dart';
import '../style.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late DateTime _month; // 当前显示的月份（取每月 1 号）

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _showDetail(Entry entry) {
    final d = DateTime.parse(entry.date);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: hintColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${d.year}年${d.month}月${d.day}日 ${weekdays[d.weekday - 1]}',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (entry.photo != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(entry.photo!, width: double.infinity, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
            ],
            if (entry.text.isNotEmpty)
              Text(entry.text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: EntryStore.listenable,
      builder: (context, box, _) {
        final entries = EntryStore.all();
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              _buildCalendar(context),
              const SizedBox(height: 24),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Column(
                    children: [
                      Icon(Icons.auto_stories_outlined, size: 48, color: hintColor),
                      const SizedBox(height: 12),
                      const Text('还没有记录，去「今天」写下第一条吧',
                          style: TextStyle(color: hintColor)),
                    ],
                  ),
                )
              else
                ..._buildTimeline(context, entries),
            ],
          ),
        );
      },
    );
  }

  // ── 月历 ──────────────────────────────────────────────

  Widget _buildCalendar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = DateTime(_month.year, _month.month, 1).weekday - 1;

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final entry = EntryStore.get(EntryStore.dateKey(date));
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;

      cells.add(InkWell(
        onTap: entry == null ? null : () => _showDetail(entry),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: isToday
                  ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
                  : null,
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 14,
                  color: isToday ? scheme.onPrimary : Colors.black87,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: entry != null ? scheme.primary : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardFill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${_month.year}年${_month.month}月',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              IconButton(
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: ['一', '二', '三', '四', '五', '六', '日']
                .map((w) => Expanded(
                      child: Center(
                        child: Text(w,
                            style: const TextStyle(fontSize: 12, color: hintColor)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: cells,
          ),
        ],
      ),
    );
  }

  // ── 时间轴 ────────────────────────────────────────────

  List<Widget> _buildTimeline(BuildContext context, List<Entry> entries) {
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final entry in entries) ...[
        _TimelineCard(entry: entry, scheme: scheme, onTap: () => _showDetail(entry)),
        const SizedBox(height: 12),
      ],
    ];
  }
}

class _TimelineCard extends StatelessWidget {
  final Entry entry;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _TimelineCard({
    required this.entry,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = DateTime.parse(entry.date);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardFill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.month}月${d.day}日 ${weekdays[d.weekday - 1]}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry.text.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
            if (entry.photo != null) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  entry.photo!,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
