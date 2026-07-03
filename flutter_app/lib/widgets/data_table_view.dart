import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/audio_frame.dart';
import '../services/stft_data_query.dart';

class StftDataTableView extends StatefulWidget {
  final List<AudioFrame> frames;

  const StftDataTableView({super.key, required this.frames});

  @override
  State<StftDataTableView> createState() => _StftDataTableViewState();
}

class _StftDataTableViewState extends State<StftDataTableView> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  String _searchFilter = '';
  bool _showOnlyNonZero = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(StftDataTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.frames.length > oldWidget.frames.length && _autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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
    _autoScroll =
        (_scrollController.position.maxScrollExtent - _scrollController.offset) <= 60;
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

  StftDataQuery get _activeQuery => StftDataQuery(
        searchFilter: _searchFilter,
        showOnlyNonZero: _showOnlyNonZero,
      );

  int get _binCount => _activeQuery.binCount(widget.frames);

  void _exportToClipboard() {
    final tsv = _activeQuery.exportTsv(widget.frames);
    if (tsv.isEmpty) return;
    Clipboard.setData(ClipboardData(text: tsv));

    final lineCount = '\n'.allMatches(tsv).length;
    final truncated = tsv.length > 0 && !tsv.endsWith('phases') && lineCount >= 10000;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            truncated
                ? 'Copied first 10K rows (TSV)'
                : 'Copied ${lineCount - 1} rows (TSV)',
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

    final query = _activeQuery;
    final totalFrames = widget.frames.length;
    final binCount = _binCount;
    final totalRows = query.totalRows(widget.frames);

    return Column(
      children: [
        // ── Search bar ──
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
              const Icon(Icons.filter_alt_outlined, color: Colors.white54, size: 20),
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
              GestureDetector(
                onTap: () {
                  setState(() => _autoScroll = true);
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _scrollToBottom());
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
              Expanded(flex: 2, child: Text('Time (s)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
              Expanded(flex: 2, child: Text('Freq (Hz)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
              Expanded(flex: 3, child: Text('Amplitude',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
              Expanded(flex: 3, child: Text('Phase (rad)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 24),
            ],
          ),
        ),

        // ── Scrollable table body ──
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: totalRows,
            itemExtent: 34,
            itemBuilder: (context, index) {
              final row = query.rowAt(widget.frames, index);
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
                      child: Text(row.time,
                          style: const TextStyle(fontSize: 11, color: Colors.white)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(row.frequency,
                          style: const TextStyle(fontSize: 11, color: Colors.white)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        row.amplitude,
                        style: TextStyle(
                          fontSize: 11,
                          color: (double.tryParse(row.amplitude) ?? 0) > 0.5
                              ? const Color(0xFF4FC3F7)
                              : Colors.white,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(row.phase,
                          style: const TextStyle(fontSize: 11, color: Colors.white54)),
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
