import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/audio_frame.dart';

class StftDataTableView extends StatefulWidget {
  final List<AudioFrame> frames;

  const StftDataTableView({super.key, required this.frames});

  @override
  State<StftDataTableView> createState() => _StftDataTableViewState();
}

class _StftDataTableViewState extends State<StftDataTableView> {
  final ScrollController _scrollController = ScrollController();
  String _searchFilter = '';
  bool _showOnlyNonZero = true;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(StftDataTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When frames grow, auto-scroll to bottom if in live mode
    if (widget.frames.length > oldWidget.frames.length && _autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    // If more than 60px from bottom, user is browsing history
    _autoScroll = (maxScroll - current) <= 60;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > 0) {
      _scrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 50),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Lazy row computation ──

  int _binCount() {
    if (widget.frames.isEmpty) return 0;
    return widget.frames.first.binCount;
  }

  /// Total visible rows with current filter.
  int _totalRows() {
    if (_searchFilter.isEmpty && !_showOnlyNonZero) {
      return widget.frames.length * _binCount();
    }
    int count = 0;
    final bc = _binCount();
    final q = _searchFilter.toLowerCase();
    for (final frame in widget.frames) {
      final t = frame.time.toStringAsFixed(3);
      for (int bi = 0; bi < bc; bi++) {
        if (_showOnlyNonZero && frame.magnitudes[bi] == 0) continue;
        if (q.isNotEmpty) {
          final freq = frame.frequencies[bi].toStringAsFixed(1);
          final amp = frame.magnitudes[bi].toStringAsFixed(6);
          final phase = frame.phases[bi].toStringAsFixed(6);
          if (!t.contains(q) &&
              !freq.contains(q) &&
              !amp.contains(q) &&
              !phase.contains(q)) continue;
        }
        count++;
      }
    }
    return count;
  }

  /// Get row data at [idx] (0-based among visible rows).
  Map<String, String>? _rowAt(int idx) {
    if (_searchFilter.isEmpty && !_showOnlyNonZero) {
      // Fast path: direct index → frame/bin
      final bc = _binCount();
      if (bc == 0) return null;
      final fi = idx ~/ bc;
      final bi = idx % bc;
      if (fi >= widget.frames.length) return null;
      final frame = widget.frames[fi];
      if (bi >= frame.binCount) return null;
      return _makeRow(frame, bi);
    }

    // Slow path: scan visible rows until idx
    int seen = 0;
    final bc = _binCount();
    final q = _searchFilter.toLowerCase();
    for (final frame in widget.frames) {
      final t = frame.time.toStringAsFixed(3);
      for (int bi = 0; bi < bc; bi++) {
        if (_showOnlyNonZero && frame.magnitudes[bi] == 0) continue;
        if (q.isNotEmpty) {
          final freq = frame.frequencies[bi].toStringAsFixed(1);
          final amp = frame.magnitudes[bi].toStringAsFixed(6);
          final phase = frame.phases[bi].toStringAsFixed(6);
          if (!t.contains(q) &&
              !freq.contains(q) &&
              !amp.contains(q) &&
              !phase.contains(q)) continue;
        }
        if (seen == idx) return _makeRow(frame, bi, time: t);
        seen++;
      }
    }
    return null;
  }

  Map<String, String> _makeRow(AudioFrame frame, int bi, {String? time}) {
    return {
      'key': '${frame.time}_$bi',
      'time': time ?? frame.time.toStringAsFixed(3),
      'frequency': frame.frequencies[bi].toStringAsFixed(1),
      'amplitude': frame.magnitudes[bi].toStringAsFixed(6),
      'phase': frame.phases[bi].toStringAsFixed(6),
    };
  }

  void _exportToClipboard() {
    if (widget.frames.isEmpty) return;
    final sb = StringBuffer('time_s\tfrequency_hz\tamplitude\tphase_radians\n');
    int lines = 0;
    const maxLines = 10000;
    final bc = _binCount();
    for (final frame in widget.frames) {
      final t = frame.time.toStringAsFixed(3);
      for (int bi = 0; bi < bc; bi++) {
        if (_showOnlyNonZero && frame.magnitudes[bi] == 0) continue;
        if (lines >= maxLines) break;
        sb.writeln(
          '$t\t${frame.frequencies[bi].toStringAsFixed(1)}\t'
          '${frame.magnitudes[bi].toStringAsFixed(6)}\t'
          '${frame.phases[bi].toStringAsFixed(6)}',
        );
        lines++;
      }
      if (lines >= maxLines) break;
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lines >= maxLines
                ? 'Copied first $maxLines rows (TSV)'
                : 'Copied $lines rows (TSV)',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.frames.isEmpty) {
      return const Center(
        child: Text('No data', style: TextStyle(color: Colors.white54)),
      );
    }

    final totalFrames = widget.frames.length;
    final binCount = _binCount();
    final totalRows = _totalRows();

    return Column(
      children: [
        // ── Top filter bar ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: TextField(
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search freq or amp...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: InputBorder.none,
                      suffixIcon: Icon(
                        Icons.search,
                        size: 16,
                        color: Colors.white54,
                      ),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      _searchFilter = v;
                      _autoScroll = false;
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.filter_alt_outlined,
                color: Colors.white54,
                size: 20,
              ),
            ],
          ),
        ),

        // ── Stats bar ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
          child: Row(
            children: [
              Text(
                '$totalFrames frames · $binCount bins · '
                '${totalRows >= 10000 ? '${(totalRows / 1000).toStringAsFixed(0)}K' : totalRows} rows',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
              const Spacer(),
              Switch(
                value: _showOnlyNonZero,
                onChanged: (v) => setState(() {
                  _showOnlyNonZero = v;
                  _autoScroll = false;
                }),
                activeTrackColor: const Color(0xFF1E88E5),
                activeThumbColor: const Color(0xFF1E88E5),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const Text(
                'Non-zero only',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),

        // ── Export / scroll-toggle bar ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _exportToClipboard,
                icon: const Icon(Icons.copy, size: 14, color: Colors.white70),
                label: const Text(
                  'Copy TSV (first 10K)',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  minimumSize: const Size(0, 28),
                  side: const BorderSide(color: Color(0xFF30363D)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const Spacer(),
              // Live/Paused toggle
              GestureDetector(
                onTap: () {
                  setState(() => _autoScroll = true);
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _scrollToBottom(),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _autoScroll
                        ? const Color(0xFF1E88E5)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _autoScroll
                          ? const Color(0xFF1E88E5)
                          : const Color(0xFF30363D),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_downward,
                        size: 12,
                        color: _autoScroll ? Colors.white : Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _autoScroll ? 'Live' : 'Paused',
                        style: TextStyle(
                          fontSize: 10,
                          color: _autoScroll ? Colors.white : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Table Header ──
        Container(
          color: const Color(0xFF161B22),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Row(
            children: [
              Expanded(
                flex: 2,
                child: Text('Time (s)',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
              Expanded(
                flex: 2,
                child: Text('Freq (Hz)',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
              Expanded(
                flex: 3,
                child: Text('Amplitude',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
              Expanded(
                flex: 3,
                child: Text('Phase (rad)',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
              SizedBox(width: 24),
            ],
          ),
        ),

        // ── Scrollable Table Body ──
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: totalRows,
            itemExtent: 34,
            itemBuilder: (context, index) {
              final row = _rowAt(index);
              if (row == null) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                height: 34,
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF30363D)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(row['time']!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(row['frequency']!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        row['amplitude']!,
                        style: TextStyle(
                          fontSize: 11,
                          color: double.parse(row['amplitude']!) > 0.5
                              ? const Color(0xFF4FC3F7)
                              : Colors.white,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(row['phase']!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white54)),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.more_vert, size: 14, color: Colors.white30),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
