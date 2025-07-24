// lib/sewing/season_report_section.dart
// UPDATED: default season = the one containing today, added other_expenses & net_profit,
// sidebar redesigned to match SewingPurchasesSection style, plus misc UI tweaks.

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SeasonReportSection extends StatefulWidget {
  const SeasonReportSection({Key? key}) : super(key: key);
  @override
  State<SeasonReportSection> createState() => _SeasonReportSectionState();
}

class _SeasonReportSectionState extends State<SeasonReportSection> {
  // ================== CONFIG ==================
  final String baseUrl = 'http://localhost:8888';
  static const double kDonutHeight = 300; // ارتفاع الرسم
  static const double _sidebarWidth = 400; // like purchases sidebar

  // ================== STATE ===================
  List<dynamic> _allSeasons = [];
  List<dynamic> _filteredSeasons = [];
  Map<int, Map<String, dynamic>> _seasonProfits = {};
  dynamic _selectedSeason;

  bool _loadingSeasons = true;
  bool _loadingProfit = false;

  String? _errorSeasons;
  String? _errorProfit;

  final TextEditingController _searchCtl = TextEditingController();

  // ================== INIT ====================
  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(_applyFilter);
    _fetchAllSeasons();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  // ================== HELPERS =================
  void _applyFilter() {
    final q = _searchCtl.text.trim().toLowerCase();
    setState(() {
      _filteredSeasons = _allSeasons.where((s) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        return name.contains(q);
      }).toList();
    });
  }

  void _snack(String msg, {Color? c}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: c),
    );
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso);
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      if (iso.contains('T')) return iso.split('T').first;
      if (iso.contains(' ')) return iso.split(' ').first;
      return iso;
    }
  }

  // ================== NETWORK =================
  Future<void> _fetchAllSeasons() async {
    setState(() {
      _loadingSeasons = true;
      _errorSeasons = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/seasons'));
      if (res.statusCode == 200) {
        _allSeasons = jsonDecode(res.body) as List<dynamic>;
        _filteredSeasons = List.from(_allSeasons);

        // pick default season: today inside [start_date, end_date]
        if (_allSeasons.isNotEmpty) {
          final now = DateTime.now();
          dynamic found = _allSeasons.firstWhere(
            (s) {
              final sd = DateTime.tryParse(s['start_date'] ?? '');
              final ed = DateTime.tryParse(s['end_date'] ?? '');
              if (sd == null || ed == null) return false;
              return (now.isAfter(sd) || _sameDay(now, sd)) && (now.isBefore(ed) || _sameDay(now, ed));
            },
            orElse: () => _allSeasons.first,
          );
          await _selectSeason(found);
        }
      } else {
        throw Exception(res.reasonPhrase);
      }
    } catch (e) {
      _errorSeasons = 'خطأ في تحميل المواسم: $e';
    } finally {
      if (mounted) setState(() => _loadingSeasons = false);
    }
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _selectSeason(dynamic season) async {
    setState(() {
      _selectedSeason = season;
      _errorProfit = null;
    });
    await _fetchSeasonProfit(season['id'] as int);
  }

  Future<void> _fetchSeasonProfit(int id) async {
    setState(() => _loadingProfit = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/seasons/$id/profit'));
      if (res.statusCode == 200) {
        _seasonProfits[id] = jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception(res.reasonPhrase);
      }
    } catch (e) {
      _errorProfit = 'خطأ في تحميل تقرير الموسم: $e';
    } finally {
      if (mounted) setState(() => _loadingProfit = false);
    }
  }

  Future<void> _addSeason() async {
    final nameCtl = TextEditingController();
    DateTime? startDate, endDate;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> pick(bool start) async {
          final p = await showDatePicker(
            context: ctx,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (p != null) setD(() => start ? startDate = p : endDate = p);
        }

        return AlertDialog(
          title: const Text('إضافة موسم جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'اسم الموسم',
                  ),
                ),
                const SizedBox(height: 12),
                _DatePickTile(label: 'تاريخ البدء', date: startDate, onTap: () => pick(true)),
                const SizedBox(height: 8),
                _DatePickTile(label: 'تاريخ الانتهاء', date: endDate, onTap: () => pick(false)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtl.text.isEmpty || startDate == null || endDate == null) {
                        _snack('الرجاء ملء جميع الحقول.', c: Colors.red);
                        return;
                      }
                      if (startDate!.isAfter(endDate!)) {
                        _snack('تاريخ البدء يجب أن يكون قبل تاريخ الانتهاء.', c: Colors.red);
                        return;
                      }
                      setD(() => saving = true);
                      try {
                        final res = await http.post(
                          Uri.parse('$baseUrl/seasons'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'name': nameCtl.text.trim(),
                            'start_date': startDate!.toIso8601String(),
                            'end_date': endDate!.toIso8601String(),
                          }),
                        );
                        if (res.statusCode == 201) {
                          _snack('تمت إضافة الموسم بنجاح!', c: Colors.green);
                          Navigator.pop(ctx);
                          await _fetchAllSeasons();
                        } else {
                          _snack('فشل إضافة الموسم: ${res.reasonPhrase}', c: Colors.red);
                        }
                      } catch (e) {
                        _snack('خطأ في الاتصال: $e', c: Colors.red);
                      }
                      setD(() => saving = false);
                    },
            ),
          ],
        );
      }),
    );
  }

  Future<void> _editSeason(dynamic season) async {
    final nameCtl = TextEditingController(text: season['name'] ?? '');
    DateTime? startDate = DateTime.tryParse(season['start_date'] ?? '');
    DateTime? endDate = DateTime.tryParse(season['end_date'] ?? '');
    bool saving = false;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> pick(bool start) async {
          final p = await showDatePicker(
            context: ctx,
            initialDate: (start ? startDate : endDate) ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (p != null) setD(() => start ? startDate = p : endDate = p);
        }

        return AlertDialog(
          title: const Text('تعديل الموسم'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'اسم الموسم',
                  ),
                ),
                const SizedBox(height: 12),
                _DatePickTile(label: 'تاريخ البدء', date: startDate, onTap: () => pick(true)),
                const SizedBox(height: 8),
                _DatePickTile(label: 'تاريخ الانتهاء', date: endDate, onTap: () => pick(false)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtl.text.isEmpty || startDate == null || endDate == null) {
                        _snack('الرجاء ملء جميع الحقول.', c: Colors.red);
                        return;
                      }
                      if (startDate!.isAfter(endDate!)) {
                        _snack('تاريخ البدء يجب أن يكون قبل تاريخ الانتهاء.', c: Colors.red);
                        return;
                      }
                      setD(() => saving = true);
                      try {
                        final res = await http.put(
                          Uri.parse('$baseUrl/seasons/${season['id']}'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'name': nameCtl.text.trim(),
                            'start_date': startDate!.toIso8601String(),
                            'end_date': endDate!.toIso8601String(),
                          }),
                        );
                        if (res.statusCode == 200) {
                          _snack('تم تحديث الموسم بنجاح!', c: Colors.green);
                          Navigator.pop(ctx);
                          await _fetchAllSeasons();
                        } else {
                          _snack('فشل تحديث الموسم: ${res.reasonPhrase}', c: Colors.red);
                        }
                      } catch (e) {
                        _snack('خطأ في الاتصال: $e', c: Colors.red);
                      }
                      setD(() => saving = false);
                    },
            ),
          ],
        );
      }),
    );
  }

  Future<void> _deleteSeason(int id) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد أنك تريد حذف هذا الموسم؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (yes == true) {
      try {
        final res = await http.delete(Uri.parse('$baseUrl/seasons/$id'));
        if (res.statusCode == 200) {
          _snack('تم حذف الموسم بنجاح!', c: Colors.green);
          await _fetchAllSeasons();
          if (_selectedSeason != null && _selectedSeason['id'] == id) {
            setState(() => _selectedSeason = null);
          }
        } else {
          _snack('فشل حذف الموسم: ${res.reasonPhrase}', c: Colors.red);
        }
      } catch (e) {
        _snack('خطأ في الاتصال: $e', c: Colors.red);
      }
    }
  }

  // ================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _fetchAllSeasons,
        child: Row(
          children: [
            _buildSidebar(),
            const VerticalDivider(width: 1),
            // Main content
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _selectedSeason == null ? _placeholder() : _report(_selectedSeason),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Sidebar like SewingPurchasesSection =====
  Widget _buildSidebar() {
    return Container(
      width: _sidebarWidth,
      color: Colors.grey[100],
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'تقارير المواسم',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchCtl,
                  decoration: InputDecoration(
                    hintText: 'بحث باسم الموسم',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('إضافة موسم', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[600],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _addSeason,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loadingSeasons
                ? const Center(child: CircularProgressIndicator())
                : _errorSeasons != null
                    ? Center(child: Text(_errorSeasons!))
                    : _filteredSeasons.isEmpty
                        ? const Center(child: Text('لا توجد مواسم'))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: _filteredSeasons.length,
                            itemBuilder: (ctx, i) {
                              final s = _filteredSeasons[i];
                              final bool sel = _selectedSeason != null && s['id'] == _selectedSeason['id'];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                elevation: sel ? 4 : 1,
                                color: sel ? Colors.grey[100] : Colors.white,
                                child: ListTile(
                                  selected: sel,
                                  title: Text(
                                    s['name'] ?? '',
                                    style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal),
                                  ),
                                  subtitle: Text('${_fmtDate(s['start_date'])} → ${_fmtDate(s['end_date'])}'),
                                  onTap: () => _selectSeason(s),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 20, color: Colors.teal),
                                        onPressed: () => _editSeason(s),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                        onPressed: () => _deleteSeason(s['id'] as int),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Center(
      key: const ValueKey('ph'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_month, size: 90, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('اختر موسمًا من الشريط الجانبي لعرض التقرير', style: TextStyle(fontSize: 18)),
        ],
      ),
    );
  }

  Widget _report(dynamic season) {
    final id = season['id'] as int;
    if (_loadingProfit) {
      return const Center(key: ValueKey('lp'), child: CircularProgressIndicator());
    }
    if (_errorProfit != null) {
      return Center(key: const ValueKey('ep'), child: Text(_errorProfit!));
    }

    final data = _seasonProfits[id] ?? {};
    final rev = (data['total_revenue'] ?? 0).toDouble();
    final cogs = (data['total_cost_of_goods_sold'] ?? 0).toDouble();
    final preProfit = (data['total_profit'] ?? 0).toDouble(); // قبل المصاريف الأخرى
    final other = (data['other_expenses'] ?? 0).toDouble();
    final net = (data['net_profit'] ?? (preProfit - other)).toDouble();

    final List<dynamic> byModel = (data['profit_by_model'] ?? []) as List<dynamic>;
    final List<dynamic> byClient = (data['profit_by_client'] ?? []) as List<dynamic>;

    return SingleChildScrollView(
      key: const ValueKey('rp'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تقرير الموسم: ${season['name']}', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('${_fmtDate(season['start_date'])} → ${_fmtDate(season['end_date'])}',
              style: Theme.of(context).textTheme.titleMedium),
          const Divider(height: 32),

          // الإحصائيات الرئيسية
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statCard('الإيرادات', rev, Icons.attach_money, Colors.blue),
              _statCard('تكلفة البضاعة', cogs, Icons.inventory_2, Colors.orange),
              _statCard('الربح قبل المصاريف', preProfit, Icons.trending_up, preProfit >= 0 ? Colors.green : Colors.red),
              _statCard('مصاريف أخرى', other, Icons.money_off, Colors.redAccent),
              _statCard('الربح الصافي', net, Icons.balance, net >= 0 ? Colors.green : Colors.red),
            ].map((w) => SizedBox(width: 220, child: w)).toList(),
          ),

          // const SizedBox(height: 24),
          // if (rev != 0 || cogs != 0 || preProfit != 0 || other != 0 || net != 0)
          //   _donutSection(revenue: rev, cogs: cogs, other: other, net: net),

          const SizedBox(height: 32),
          Text('تفاصيل الأداء', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          _metricsTable(rev: rev, cogs: cogs, pre: preProfit, other: other, net: net),

          if (byModel.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text('الربح حسب الموديل', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            _breakdownTable(
              headers: const ['الموديل', 'الإيرادات', 'التكلفة', 'الربح'],
              rows: byModel.map<List<String>>((m) {
                final r = (m['revenue'] ?? 0).toDouble();
                final cg = (m['cogs'] ?? 0).toDouble();
                final pf = (m['profit'] ?? 0).toDouble();
                return [
                  (m['model_name'] ?? '').toString(),
                  r.toStringAsFixed(2),
                  cg.toStringAsFixed(2),
                  pf.toStringAsFixed(2),
                ];
              }).toList(),
            ),
          ],
          if (byClient.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text('الربح حسب العميل', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            _breakdownTable(
              headers: const ['العميل', 'الإيرادات', 'التكلفة', 'الربح'],
              rows: byClient.map<List<String>>((c) {
                final r = (c['revenue'] ?? 0).toDouble();
                final cg = (c['cogs'] ?? 0).toDouble();
                final pf = (c['profit'] ?? 0).toDouble();
                return [
                  (c['client_name'] ?? '').toString(),
                  r.toStringAsFixed(2),
                  cg.toStringAsFixed(2),
                  pf.toStringAsFixed(2),
                ];
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statCard(String label, double value, IconData icon, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Icon(icon, color: color)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                Text('${value.toStringAsFixed(2)} دج',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Widget _donutSection({
  //   required double revenue,
  //   required double cogs,
  //   required double other,
  //   required double net,
  // }) {
  //   final totalAbs = cogs.abs() + other.abs() + net.abs();
  //   final hasData = totalAbs > 0;
  //   return Card(
  //     elevation: 1,
  //     child: Padding(
  //       padding: const EdgeInsets.all(16),
  //       child: Column(
  //         children: [
  //           Text('نسبة التكلفة / المصاريف / الربح', style: Theme.of(context).textTheme.titleMedium),
  //           const SizedBox(height: 12),
  //           SizedBox(
  //             height: kDonutHeight,
  //             child: hasData
  //                 ? _DonutChart(
  //                     slices: [
  //                       DonutSlice(value: cogs.abs(), color: Colors.orange.shade300, label: 'تكلفة البضاعة'),
  //                       DonutSlice(value: other.abs(), color: Colors.red.shade300, label: 'مصاريف أخرى'),
  //                       DonutSlice(value: net.abs(), color: Colors.green.shade300, label: 'ربح صافي'),
  //                     ],
  //                   )
  //                 : const Center(child: Text('لا توجد بيانات لعرض الرسم')),
  //           ),
  //           if (revenue != 0) ...[
  //             const SizedBox(height: 8),
  //             Text('إجمالي الإيرادات: ${revenue.toStringAsFixed(2)} دج',
  //                 style: const TextStyle(fontWeight: FontWeight.bold)),
  //           ]
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Widget _metricsTable({
  required double rev,
  required double cogs,
  required double pre,
  required double other,
  required double net,
}) {
  final table = DataTable(
    headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
    headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    columns: const [
      DataColumn(label: Text('المقياس')),
      DataColumn(label: Text('القيمة')),
    ],
    rows: [
      DataRow(cells: [const DataCell(Text('إجمالي الإيرادات')), DataCell(Text('${rev.toStringAsFixed(2)} دج'))]),
      DataRow(cells: [const DataCell(Text('تكلفة البضاعة المباعة')), DataCell(Text('${cogs.toStringAsFixed(2)} دج'))]),
      DataRow(cells: [const DataCell(Text('الربح قبل المصاريف الأخرى')), DataCell(Text('${pre.toStringAsFixed(2)} دج'))]),
      DataRow(cells: [const DataCell(Text('مصاريف أخرى')), DataCell(Text('${other.toStringAsFixed(2)} دج'))]),
      DataRow(cells: [const DataCell(Text('الربح الصافي')), DataCell(Text('${net.toStringAsFixed(2)} دج',
        style: TextStyle(color: net >= 0 ? Colors.green : Colors.red),
      ))]),
    ],
  );

  return LayoutBuilder(
    builder: (ctx, cons) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: cons.maxWidth),
        child: Center(child: table),
      ),
    ),
  );
}

  Widget _breakdownTable({
  required List<String> headers,
  required List<List<String>> rows,
}) {
  final table = DataTable(
    headingRowColor: MaterialStateProperty.all(Theme.of(context).primaryColor),
    headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
    rows: rows.map((r) => DataRow(cells: r.map((c) => DataCell(Text(c))).toList())).toList(),
  );

  return LayoutBuilder(
    builder: (ctx, cons) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: cons.maxWidth),
        child: Center(child: table),
      ),
    ),
  );
}

}

// ===================== Helper Widgets =====================

class _DatePickTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const _DatePickTile({Key? key, required this.label, required this.date, required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final txt = date == null ? label : '$label: ${date!.toLocal().toString().split(' ')[0]}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(txt),
      trailing: const Icon(Icons.calendar_today),
      onTap: onTap,
    );
  }
}

// ===================== Donut Chart (No external deps) =====================

class DonutSlice {
  final double value;
  final Color color;
  final String label;
  DonutSlice({required this.value, required this.color, required this.label});
}

class _DonutChart extends StatelessWidget {
  final List<DonutSlice> slices;
  final double strokeWidth;
  const _DonutChart({Key? key, required this.slices, this.strokeWidth = 28}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (s, e) => s + e.value);
    return LayoutBuilder(
      builder: (ctx, cons) => Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(cons.biggest.shortestSide),
            painter: _DonutPainter(slices: slices, total: total, strokeWidth: strokeWidth),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: slices.map((s) {
                final pct = total == 0 ? 0 : (s.value / total * 100);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 12, color: s.color),
                    const SizedBox(width: 4),
                    Text('${s.label} (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 12)),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSlice> slices;
  final double total;
  final double strokeWidth;
  _DonutPainter({required this.slices, required this.total, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    if (total == 0) return;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 4;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    double start = -math.pi / 2;
    for (final s in slices) {
      final sweep = (s.value / total) * 2 * math.pi;
      paint.color = s.color;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.total != total || old.strokeWidth != strokeWidth;
}
