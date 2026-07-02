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
  final Map<String, TextEditingController> _controllers = {};
  final ScrollController _scrollController = ScrollController();

  String _searchFilter = '';
  bool _showOnlyNonZero = true;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  TextEditingController _getController(String key, String initialValue) {
    if (!_controllers.containsKey(key)) {
      _controllers[key] = TextEditingController(text: initialValue);
    }
    return _controllers[key]!;
  }

  Iterable<Map<String, String>> _generateRows() sync* {
    for (final frame in widget.frames) {
      final t = frame.time.toStringAsFixed(3);
      for (int i = 0; i < frame.binCount; i++) {
        yield {
          'key': '${t}_$i',
          'time': t,
          'frequency': frame.frequencies[i].toStringAsFixed(1),
          'amplitude': frame.magnitudes[i].toStringAsFixed(6),
          'phase': frame.phases[i].toStringAsFixed(6),
        };
      }
    }
  }

  List<Map<String, String>> _buildFilteredRows() {
    final result = <Map<String, String>>[];
    for (final row in _generateRows()) {
      if (_showOnlyNonZero && double.tryParse(row['amplitude']!) == 0.0) {
        continue;
      }
      if (_searchFilter.isNotEmpty) {
        final q = _searchFilter.toLowerCase();
        if (!row['time']!.contains(q) &&
            !row['frequency']!.contains(q) &&
            !row['amplitude']!.contains(q) &&
            !row['phase']!.contains(q)) {
          continue;
        }
      }
      result.add(row);
      if (result.length > 500) break; // Limit for UI performance
    }
    return result;
  }

  void _exportToClipboard() {
    final rows = _buildFilteredRows();
    if (rows.isEmpty) return;
    final sb = StringBuffer('time_s\tfrequency_hz\tamplitude\tphase_radians\n');
    for (final r in rows) {
      sb.writeln(
        '${r['time']}\t${r['frequency']}\t${r['amplitude']}\t${r['phase']}',
      );
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data copied to clipboard (TSV format)'),
          duration: Duration(seconds: 2),
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

    final rows = _buildFilteredRows();

    return Column(
      children: [
        // Top filter bar
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
                    onChanged: (v) => setState(() => _searchFilter = v),
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

        // Second filter bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              _buildDropdown('All Frequencies'),
              const SizedBox(width: 8),
              _buildDropdown('All Amplitudes'),
              const Spacer(),
              Switch(
                value: _showOnlyNonZero,
                onChanged: (v) => setState(() => _showOnlyNonZero = v),
                activeColor: const Color(0xFF1E88E5),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const Text(
                'Non-zero only',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),

        // Copy TSV
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _exportToClipboard,
              icon: const Icon(Icons.copy, size: 14, color: Colors.white70),
              label: const Text(
                'Copy TSV',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                minimumSize: const Size(0, 32),
                side: const BorderSide(color: Color(0xFF30363D)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),

        // Table Header
        Container(
          color: const Color(0xFF161B22),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: const Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  'Time (s)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Freq (Hz)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Amplitude',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Phase (rad)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 24), // For 3-dots
            ],
          ),
        ),

        // Table Body
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF30363D))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        row['time']!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        row['frequency']!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        row['amplitude']!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        row['phase']!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.more_vert,
                      size: 16,
                      color: Colors.white54,
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Pagination
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF0D1117),
            border: Border(top: BorderSide(color: Color(0xFF30363D))),
          ),
          child: Row(
            children: [
              const Text(
                'Rows per page:',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              const SizedBox(width: 8),
              _buildDropdown('100', width: 60),
              const Spacer(),
              const Text(
                '1–100 of 52,665',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.first_page, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_left, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF42A5F5)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '1',
                  style: TextStyle(fontSize: 11, color: Color(0xFF42A5F5)),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '2',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              const SizedBox(width: 8),
              const Text(
                '3',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              const SizedBox(width: 8),
              const Text(
                '...',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              const SizedBox(width: 8),
              const Text(
                '527',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              const Icon(Icons.last_page, size: 16, color: Colors.white54),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String text, {double? width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white54),
        ],
      ),
    );
  }
}
