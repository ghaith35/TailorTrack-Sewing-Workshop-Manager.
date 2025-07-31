// lib/embroidery/embroidery_season_report_section.dart
//
// Season report for EMBROIDERY module:
// profit = revenue - returns_value - raw_materials_usage - other_expenses
//
// - Uses same sidebar style as sewing
// - Shows breakdown by model / client
// - No donut by default (left commented like sewing)
// - Handles Arabic RTL and formatting

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart';

class EmbroiderySeasonReportSection extends StatefulWidget {
  const EmbroiderySeasonReportSection({Key? key}) : super(key: key);
  @override
  State<EmbroiderySeasonReportSection> createState() =>
      _EmbroiderySeasonReportSectionState();
}

class _EmbroiderySeasonReportSectionState extends State<EmbroiderySeasonReportSection> {
  // ================== CONFIG ==================
String get baseUrl => '${globalServerUri.toString()}/embrodry';
  static const double kDonutHeight = 300;
  static const double _sidebarWidth = 400;

  // ================== STATE ===================
  List<dynamic> _allSeasons = [];
  List<dynamic> _filteredSeasons = [];
  Map<int, Map<String, dynamic>> _seasonReports = {};
  dynamic _selectedSeason;

  bool _loadingSeasons = true;
  bool _loadingReport = false;

  String? _errorSeasons;
  String? _errorReport;

  final TextEditingController _searchCtl = TextEditingController();

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
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      if (iso.contains('T')) return iso.split('T').first;
      if (iso.contains(' ')) return iso.split(' ').first;
      return iso;
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ================== NETWORK =================
  Future<void> _fetchAllSeasons() async {
    setState(() {
      _loadingSeasons = true;
      _errorSeasons = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/seasons'));
      if (res.statusCode == 200) {
        _allSeasons = jsonDecode(res.body) as List;
        _filteredSeasons = List.from(_allSeasons);

        if (_allSeasons.isNotEmpty) {
          final now = DateTime.now();
          dynamic def = _allSeasons.firstWhere(
            (s) {
              final sd = DateTime.tryParse(s['start_date'] ?? '');
              final ed = DateTime.tryParse(s['end_date'] ?? '');
              if (sd == null || ed == null) return false;
              return (now.isAfter(sd) || _sameDay(now, sd)) &&
                  (now.isBefore(ed) || _sameDay(now, ed));
            },
            orElse: () => _allSeasons.first,
          );
          await _selectSeason(def);
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

  Future<void> _selectSeason(dynamic season) async {
    setState(() {
      _selectedSeason = season;
      _errorReport = null;
    });
    await _fetchSeasonReport(season['id'] as int);
  }

  Future<void> _fetchSeasonReport(int id) async {
    setState(() => _loadingReport = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/seasons/$id/report'));
      if (res.statusCode == 200) {
        _seasonReports[id] = jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception(res.reasonPhrase);
      }
    } catch (e) {
      _errorReport = 'خطأ في تحميل تقرير الموسم: $e';
    } finally {
      if (mounted) setState(() => _loadingReport = false);
    }
  }

  final _seasonFormKey = GlobalKey<FormState>();

  Future<void> _addSeason() async {
    final nameCtl = TextEditingController();
    DateTime? startDate, endDate;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> pick(bool isStart) async {
          final picked = await showDatePicker(
            context: ctx,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            locale: const Locale('ar'),
            cancelText: 'إلغاء',
            confirmText: 'موافق',
            helpText: 'اختر التاريخ',
          );
          if (picked != null) {
            setD(() => isStart ? startDate = picked : endDate = picked);
          }
        }

        return AlertDialog(
          title: const Text('إضافة موسم جديد'),
          content: Form(
            key: _seasonFormKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'اسم الموسم',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'الرجاء إدخال اسم الموسم'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(startDate == null
                        ? 'تاريخ البدء'
                        : 'تاريخ البدء: ${startDate!.toLocal().toString().split(' ')[0]}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => pick(true),
                  ),
                  if (startDate == null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          'الرجاء اختيار تاريخ البدء',
                          style: TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(endDate == null
                        ? 'تاريخ الانتهاء'
                        : 'تاريخ الانتهاء: ${endDate!.toLocal().toString().split(' ')[0]}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => pick(false),
                  ),
                  if (endDate == null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          'الرجاء اختيار تاريخ الانتهاء',
                          style: TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
              onPressed: saving
                  ? null
                  : () async {
                      if (!_seasonFormKey.currentState!.validate() ||
                          startDate == null ||
                          endDate == null) {
                        return;
                      }
                      if (startDate!.isAfter(endDate!)) {
                        _snack(
                          'تاريخ البدء يجب أن يكون قبل الانتهاء.',
                          c: Colors.red,
                        );
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
                          _snack('تمت الإضافة', c: Colors.green);
                          Navigator.pop(ctx);
                          await _fetchAllSeasons();
                        } else {
                          _snack('فشل الإضافة: ${res.reasonPhrase}', c: Colors.red);
                        }
                      } catch (e) {
                        _snack('خطأ اتصال: $e', c: Colors.red);
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
        Future<void> pick(bool isStart) async {
          final picked = await showDatePicker(
            context: ctx,
            initialDate: (isStart ? startDate : endDate) ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            locale: const Locale('ar'),
            cancelText: 'إلغاء',
            confirmText: 'موافق',
            helpText: 'اختر التاريخ',
          );
          if (picked != null) {
            setD(() => isStart ? startDate = picked : endDate = picked);
          }
        }

        return AlertDialog(
          title: const Text('تعديل الموسم'),
          content: Form(
            key: _seasonFormKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'اسم الموسم',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'الرجاء إدخال اسم الموسم'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(startDate == null
                        ? 'تاريخ البدء'
                        : 'تاريخ البدء: ${startDate!.toLocal().toString().split(' ')[0]}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => pick(true),
                  ),
                  if (startDate == null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          'الرجاء اختيار تاريخ البدء',
                          style: TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(endDate == null
                        ? 'تاريخ الانتهاء'
                        : 'تاريخ الانتهاء: ${endDate!.toLocal().toString().split(' ')[0]}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => pick(false),
                  ),
                  if (endDate == null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          'الرجاء اختيار تاريخ الانتهاء',
                          style: TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
              onPressed: saving
                  ? null
                  : () async {
                      if (!_seasonFormKey.currentState!.validate() ||
                          startDate == null ||
                          endDate == null) {
                        return;
                      }
                      if (startDate!.isAfter(endDate!)) {
                        _snack(
                          'تاريخ البدء يجب أن يكون قبل الانتهاء.',
                          c: Colors.red,
                        );
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
                          _snack('تم التحديث', c: Colors.green);
                          Navigator.pop(ctx);
                          await _fetchAllSeasons();
                        } else {
                          _snack('فشل التحديث: ${res.reasonPhrase}',
                              c: Colors.red);
                        }
                      } catch (e) {
                        _snack('خطأ اتصال: $e', c: Colors.red);
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا الموسم؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final res = await http.delete(Uri.parse('$baseUrl/seasons/$id'));
      if (res.statusCode == 200) {
        _snack('تم الحذف', c: Colors.green);
        await _fetchAllSeasons();
        if (_selectedSeason != null && _selectedSeason['id'] == id) {
          setState(() => _selectedSeason = null);
        }
      } else {
        _snack('فشل الحذف: ${res.reasonPhrase}', c: Colors.red);
      }
    } catch (e) {
      _snack('خطأ اتصال: $e', c: Colors.red);
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
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _selectedSeason == null
                    ? _placeholder()
                    : _report(_selectedSeason),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                  'تقارير المواسم (تطريز)',
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
                            itemBuilder: (_, i) {
                              final s = _filteredSeasons[i];
                              final sel = _selectedSeason != null && s['id'] == _selectedSeason['id'];
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
    if (_loadingReport) {
      return const Center(key: ValueKey('lp'), child: CircularProgressIndicator());
    }
    if (_errorReport != null) {
      return Center(key: const ValueKey('er'), child: Text(_errorReport!));
    }

    final data = _seasonReports[id] ?? {};
    final revenue   = (data['total_revenue'] ?? 0).toDouble();
    final returnsV  = (data['total_returns_value'] ?? 0).toDouble();
    final rawUsage  = (data['raw_materials_usage'] ?? 0).toDouble();
    final expenses  = (data['other_expenses'] ?? 0).toDouble();
    final totalSalaries = (data['total_salaries'] ?? 0).toDouble();
    final totalPiecesValue = (data['total_pieces_value'] ?? 0).toDouble();
    final profit    = (data['net_profit'] ?? (revenue - returnsV - rawUsage - expenses)).toDouble();

    final byModel  = (data['profit_by_model'] ?? []) as List;
    final byClient = (data['profit_by_client'] ?? []) as List;

    return SingleChildScrollView(
      key: const ValueKey('rep'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تقرير الموسم: ${season['name']}', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('${_fmtDate(season['start_date'])} → ${_fmtDate(season['end_date'])}', style: Theme.of(context).textTheme.titleMedium),
          const Divider(height: 32),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statCard('الإيرادات', revenue, Icons.attach_money, Colors.blue),
              _statCard('إجمالي الرواتب', totalSalaries, Icons.monetization_on, Colors.green),
              _statCard('إجمالي قيمة القطع', totalPiecesValue, Icons.layers, Colors.orange),
              _statCard('استهلاك المواد الخام', rawUsage, Icons.layers, Colors.purple),
              _statCard('المصاريف الأخرى', expenses, Icons.money_off, Colors.redAccent),
              _statCard('الربح الصافي', profit, Icons.balance, profit >= 0 ? Colors.green : Colors.red),
            ].map((w) => SizedBox(width: 220, child: w)).toList(),
          ),

          const SizedBox(height: 32),
          Text('تفاصيل الأداء', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          _metricsTable(
            rev: revenue,
            ret: returnsV,
            raw: rawUsage,
            other: expenses,
            totalSalaries: totalSalaries,
            totalPiecesValue: totalPiecesValue,
            net: profit,
          ),

          if (byModel.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text('حسب الموديل', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            _breakdownTable(
              headers: const ['الموديل', 'الإيرادات'],
              rows: byModel.map<List<String>>((m) {
                final r  = (m['revenue'] ?? 0).toDouble();
                return [
                  (m['model_name'] ?? '').toString(),
                  r.toStringAsFixed(2),
                ];
              }).toList(),
            ),
          ],

          if (byClient.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text('حسب العميل', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            _breakdownTable(
              headers: const ['العميل', 'الإيرادات'],
              rows: byClient.map<List<String>>((c) {
                final r  = (c['revenue'] ?? 0).toDouble();
                return [
                  (c['client_name'] ?? '').toString(),
                  r.toStringAsFixed(2),
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
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                Text('${value.toStringAsFixed(2)} دج', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricsTable({
    required double rev,
    required double ret,
    required double raw,
    required double other,
    required double totalSalaries,
    required double totalPiecesValue,
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
        DataRow(cells: [const DataCell(Text('إجمالي الرواتب')), DataCell(Text('${totalSalaries.toStringAsFixed(2)} دج'))]),
        DataRow(cells: [const DataCell(Text('إجمالي قيمة القطع')), DataCell(Text('${totalPiecesValue.toStringAsFixed(2)} دج'))]),
        DataRow(cells: [const DataCell(Text('استهلاك المواد الخام')), DataCell(Text('${raw.toStringAsFixed(2)} دج'))]),
        DataRow(cells: [const DataCell(Text('المصاريف الأخرى')), DataCell(Text('${other.toStringAsFixed(2)} دج'))]),
        DataRow(cells: [
          const DataCell(Text('الربح الصافي')),
          DataCell(Text('${net.toStringAsFixed(2)} دج', style: TextStyle(color: net >= 0 ? Colors.green : Colors.red))),
        ]),
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
