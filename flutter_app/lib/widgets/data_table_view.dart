import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/audio_frame.dart';

/// Displays STFT numerical data in a scrollable, editable table.
///
/// Shows time, frequency, amplitude, and phase angle for each bin per frame.
/// Users can edit cells inline and export the modified data.
class StftDataTableView extends StatefulWidget {
  final List<AudioFrame> frames;

  const StftDataTableView({super.key, required this.frames});

  @override
  State<StftDataTableView> createState() => _StftDataTableViewState();
}

class _StftDataTableViewState extends State<StftDataTableView> {
  // Editable data grid: key = "time_freqIdx", value = editable string
  final Map<String, TextEditingController> _controllers = {};
  final ScrollController _scrollController = ScrollController();

  // Filtering
  String _searchFilter = '';
  bool _showOnlyNonZero = false;

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

  /// Estimated total row count (for performance decisions).
  int get _totalRowEstimate =>
      widget.frames.fold(0, (sum, f) => sum + f.binCount);

  /// Generate rows lazily — returns an iterable, not a list.
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

  /// Build filtered row list (only materializes when needed).
  List<Map<String, String>> _buildFilteredRows() {
    final total = _totalRowEstimate;
    // For very large datasets, apply filtering during iteration
    // to avoid materializing everything.
    if (total > 20000) {
      final result = <Map<String, String>>[];
      for (final row in _generateRows()) {
        if (_showOnlyNonZero &&
            double.tryParse(row['amplitude']!) == 0.0) {
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
      }
      return result;
    }

    // Small dataset: filter after full materialization (simpler).
    final all = _generateRows().toList();
    if (!_showOnlyNonZero && _searchFilter.isEmpty) {
      return all;
    }
    return all.where((r) {
      if (_showOnlyNonZero &&
          double.tryParse(r['amplitude']!) == 0.0) {
        return false;
      }
      if (_searchFilter.isNotEmpty) {
        final q = _searchFilter.toLowerCase();
        if (!r['time']!.contains(q) &&
            !r['frequency']!.contains(q) &&
            !r['amplitude']!.contains(q) &&
            !r['phase']!.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void _exportToClipboard() {
    final rows = _buildFilteredRows();
    if (rows.isEmpty) return;
    final sb = StringBuffer('time_s\tfrequency_hz\tamplitude\tphase_radians\n');
    for (final r in rows) {
      sb.writeln('${r['time']}\t${r['frequency']}\t${r['amplitude']}\t${r['phase']}');
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data copied to clipboard (TSV format)'),
            duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.frames.isEmpty) {
      return const Center(
        child: Text('No data. Start recording to see numerical values.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    final rows = _buildFilteredRows();
    final isDense = rows.length > 5000;

    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // Search filter
              SizedBox(
                width: 160,
                height: 32,
                child: TextField(
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Filter...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _searchFilter = v),
                ),
              ),
              const SizedBox(width: 8),
              // Non-zero toggle
              FilterChip(
                label: const Text('Non-zero only', style: TextStyle(fontSize: 11)),
                selected: _showOnlyNonZero,
                onSelected: (v) => setState(() => _showOnlyNonZero = v),
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              Text('${rows.length} rows', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy filtered data as TSV',
                onPressed: _exportToClipboard,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Editable data table
        Expanded(
          child: isDense ? _buildDenseView(rows) : _buildEditableTable(rows),
        ),
      ],
    );
  }

  Widget _buildEditableTable(List<Map<String, String>> rows) {
    if (rows.isEmpty) {
      return const Center(child: Text('No matching rows', style: TextStyle(color: Colors.white38)));
    }

    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.vertical,
      child: DataTable(
        columnSpacing: 12,
        dataRowMinHeight: 24,
        dataRowMaxHeight: 32,
        headingRowHeight: 32,
        columns: const [
          DataColumn(label: Text('Time (s)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Freq (Hz)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Amplitude', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Phase (rad)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        ],
        rows: rows.map((row) {
          final ampCtrl = _getController('amp_${row['key']}', row['amplitude']!);
          final phaseCtrl = _getController('phase_${row['key']}', row['phase']!);
          return DataRow(
            cells: [
              DataCell(Text(row['time']!, style: const TextStyle(fontSize: 11))),
              DataCell(Text(row['frequency']!, style: const TextStyle(fontSize: 11))),
              DataCell(SizedBox(width: 100, child: TextField(
                controller: ampCtrl,
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ))),
              DataCell(SizedBox(width: 100, child: TextField(
                controller: phaseCtrl,
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ))),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// For very large datasets, show a simplified non-editable view.
  Widget _buildDenseView(List<Map<String, String>> rows) {
    // Show only a sample — every Nth row
    final step = (rows.length / 2000).ceil().clamp(1, rows.length);
    final sampled = <Map<String, String>>[];
    for (int i = 0; i < rows.length; i += step) {
      sampled.add(rows[i]);
    }

    return ListView.builder(
      itemCount: sampled.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Showing ${sampled.length} of ${rows.length} rows (sampled)',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          );
        }
        final row = sampled[index - 1];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Text(
            't=${row['time']}s  f=${row['frequency']}Hz  A=${row['amplitude']}  φ=${row['phase']}rad',
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
          ),
        );
      },
    );
  }
}
