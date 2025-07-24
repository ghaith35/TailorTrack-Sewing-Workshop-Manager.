import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DesignDebtsSection extends StatefulWidget {
  const DesignDebtsSection({super.key});

  @override
  State<DesignDebtsSection> createState() => _DesignDebtsSectionState();
}

class _DesignDebtsSectionState extends State<DesignDebtsSection> {
  int _tab = 0; // 0 => suppliers, 1 => clients

  // Scroll controllers (both axes)
  final _supH = ScrollController();
  final _supV = ScrollController();
  final _cliH = ScrollController();
  final _cliV = ScrollController();

  // Raw data
  List<Map<String, dynamic>> _supplierDebts = [];
  List<Map<String, dynamic>> _clientDebts = [];

  // Filtered
  List<Map<String, dynamic>> _fSup = [];
  List<Map<String, dynamic>> _fCli = [];

  // Loading
  bool _loadingSup = false;
  bool _loadingCli = false;

  // Search
  final _supSearch = TextEditingController();
  final _cliSearch = TextEditingController();

  // Date filters
  late List<int> _supYears;
  late List<String> _supMonths;
  int _selSupYear = DateTime.now().year;
  String _selSupMonth = DateTime.now().month.toString().padLeft(2, '0');

  late List<int> _cliYears;
  late List<String> _cliMonths;
  int _selCliYear = DateTime.now().year;
  String _selCliMonth = DateTime.now().month.toString().padLeft(2, '0');

  static const List<String> _arMonths = [
    'جانفي', 'فيفري', 'مارس', 'أفريل',
    'ماي', 'جوان', 'جويلية', 'أوت',
    'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

  // Summary labels/colors
  final Map<String, Map<String, dynamic>> _sumCfg = {
  'totalPurchases': {
    'label': 'إجمالي المشتريات/الفواتير',
    'lightColor': Colors.blue[50],
    'darkColor': Colors.blue[800],
    'darkerColor': Colors.blue[900],
  },
  'totalPaid': {
    'label': 'إجمالي المدفوع',
    'lightColor': Colors.green[50],
    'darkColor': Colors.green[800],
    'darkerColor': Colors.green[900],
  },
  'currentDebt': {
    'label': 'الدين الحالي',
    'lightColor': Colors.red[50],
    'darkColor': Colors.red[800],
    'darkerColor': Colors.red[900],
  },
};


  // BASE URL
  final String baseUrl = 'http://localhost:8888/design/debts';

  @override
  void initState() {
    super.initState();
    _supYears = [];
    _supMonths = [];
    _cliYears = [];
    _cliMonths = [];
    _fetchSuppliers();
    _fetchClients();

    _supSearch.addListener(() {
      final q = _supSearch.text.toLowerCase();
      setState(() {
        _fSup = _supplierDebts.where((s) {
          final name = (s['full_name'] ?? '').toString().toLowerCase();
          final company = (s['company_name'] ?? '').toString().toLowerCase();
          return name.contains(q) || company.contains(q);
        }).toList();
      });
    });

    _cliSearch.addListener(() {
      final q = _cliSearch.text.toLowerCase();
      setState(() {
        _fCli = _clientDebts.where((c) {
          final name = (c['full_name'] ?? '').toString().toLowerCase();
          return name.contains(q);
        }).toList();
      });
    });
  }

  @override
  void dispose() {
    _supH.dispose();
    _supV.dispose();
    _cliH.dispose();
    _cliV.dispose();
    _supSearch.dispose();
    _cliSearch.dispose();
    super.dispose();
  }

  // ================== NETWORK ==================
  Future<void> _fetchSuppliers() async {
  setState(() => _loadingSup = true);
  try {
    // جلب كل الموردين
    final all = await http.get(Uri.parse('$baseUrl/suppliers'));
    if (all.statusCode == 200) {
      _supplierDebts = (jsonDecode(all.body) as List).cast<Map<String, dynamic>>();
    } else {
      _supplierDebts = [];
    }

    // بناء سنوات/أشهر فقط للإحصاء/الفلترة (اختياري)
    final years = <int>{};
    final months = <String>{};
    for (final s in _supplierDebts) {
      final d = s['date'] as String?;
      if (d != null && d.contains('-')) {
        final p = d.split('-');
        years.add(int.parse(p[0]));
        months.add(p[1]);
      }
    }
    if (years.isEmpty) years.add(DateTime.now().year);
    _supYears = years.toList()..sort((a, b) => b.compareTo(a));
    _supMonths = months.toList()..sort();

    // فلترة محلية (إن أردت سنة/شهر)
    _fSup = _supplierDebts.where((e) {
      final d = e['date'] as String?;
      if (d == null || !d.contains('-')) return true;
      final parts = d.split('-');
      final yrOk = parts[0] == _selSupYear.toString();
      final moOk = parts[1] == _selSupMonth;
      // إذا كنت لا تريد فلترة بالشهر/السنة، فقط أرجع true
      return yrOk && moOk; // أو بدلها بـ true لعرض الكل دومًا
    }).toList();

    // ترتيب: الذين عليهم دين أولاً
    _fSup.sort((a, b) {
      final da = ((b['debt'] ?? 0) as num).toDouble();
      final db = ((a['debt'] ?? 0) as num).toDouble();
      final hasB = da > 0 ? 1 : 0;
      final hasA = db > 0 ? 1 : 0;
      if (hasB != hasA) return hasB - hasA; // debt>0 قبل
      // بعدها رتب مثلاً حسب قيمة الدين تنازلياً
      return da.compareTo(db) * -1;
    });

  } catch (e) {
    _supplierDebts = [];
    _fSup = [];
    _snack('خطأ في الاتصال: $e', err: true);
  }
  setState(() => _loadingSup = false);
}


  Future<void> _fetchClients() async {
  setState(() => _loadingCli = true);
  try {
    final all = await http.get(Uri.parse('$baseUrl/clients'));
    if (all.statusCode == 200) {
      _clientDebts = (jsonDecode(all.body) as List).cast<Map<String, dynamic>>();
    } else {
      _clientDebts = [];
    }

    final years = <int>{};
    final months = <String>{};
    for (final c in _clientDebts) {
      final d = c['date'] as String?;
      if (d != null && d.contains('-')) {
        final p = d.split('-');
        years.add(int.parse(p[0]));
        months.add(p[1]);
      }
    }
    if (years.isEmpty) years.add(DateTime.now().year);
    _cliYears = years.toList()..sort((a, b) => b.compareTo(a));
    _cliMonths = months.toList()..sort();

    _fCli = _clientDebts.where((e) {
      final d = e['date'] as String?;
      if (d == null || !d.contains('-')) return true;
      final parts = d.split('-');
      final yrOk = parts[0] == _selCliYear.toString();
      final moOk = parts[1] == _selCliMonth;
      return yrOk && moOk; // أو true لعدم الفلترة
    }).toList();

    _fCli.sort((a, b) {
      final da = ((b['debt'] ?? 0) as num).toDouble();
      final db = ((a['debt'] ?? 0) as num).toDouble();
      final hasB = da > 0 ? 1 : 0;
      final hasA = db > 0 ? 1 : 0;
      if (hasB != hasA) return hasB - hasA;
      return da.compareTo(db) * -1;
    });

  } catch (e) {
    _clientDebts = [];
    _fCli = [];
    _snack('خطأ في الاتصال: $e', err: true);
  }
  setState(() => _loadingCli = false);
}


  // ================== HELPERS ==================
  void _snack(String msg, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: err ? Colors.red : Colors.green),
    );
  }

  double _sum(List<Map<String, dynamic>> list, String key) =>
      list.fold(0.0, (s, e) => s + ((e[key] as num?)?.toDouble() ?? 0));

  double get _supTotalPurchases => _sum(_supplierDebts, 'total_purchases');
  double get _supTotalPaid => _sum(_supplierDebts, 'total_paid');
  double get _supTotalDebt => _sum(_supplierDebts, 'debt');

  double get _cliTotalInvoiced => _sum(_clientDebts, 'total_invoiced');
  double get _cliTotalPaid => _sum(_clientDebts, 'total_paid');
  double get _cliTotalDebt => _sum(_clientDebts, 'debt');

  // ================== UI ==================
  @override
  Widget build(BuildContext context) {
    final tabs = ['ديون الموردين', 'ديون العملاء'];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(tabs.length, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ChoiceChip(
                  label: Text(tabs[i]),
                  selected: _tab == i,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  labelStyle: TextStyle(
                    color: _tab == i ? Colors.white : null,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (_) => setState(() => _tab = i),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Expanded(child: _tab == 0 ? _suppliersTab() : _clientsTab()),
        ],
      ),
    );
  }

  // ---------- Supplier tab ----------
  Widget _suppliersTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // (Uncomment if you want year/month filters in UI)
              // SizedBox(
              //   width: 120,
              //   child: DropdownButtonFormField<int>(
              //     value: _selSupYear,
              //     decoration: const InputDecoration(labelText: 'السنة'),
              //     items: _supYears
              //         .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
              //         .toList(),
              //     onChanged: (y) {
              //       if (y == null) return;
              //       setState(() => _selSupYear = y);
              //       _fetchSuppliers();
              //     },
              //   ),
              // ),
              // SizedBox(
              //   width: 140,
              //   child: DropdownButtonFormField<String>(
              //     value: _selSupMonth,
              //     decoration: const InputDecoration(labelText: 'الشهر'),
              //     items: _supMonths
              //         .map((m) => DropdownMenuItem(
              //               value: m,
              //               child: Text(_arMonths[int.parse(m) - 1]),
              //             ))
              //         .toList(),
              //     onChanged: (m) {
              //       if (m == null) return;
              //       setState(() => _selSupMonth = m);
              //       _fetchSuppliers();
              //     },
              //   ),
              // ),
              const SizedBox(width: 8),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _supSearch,
                  decoration: const InputDecoration(
                    labelText: 'بحث بالمورد/الشركة',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _fetchSuppliers,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statCard('totalPurchases', _supTotalPurchases),
              const SizedBox(width: 8),
              _statCard('totalPaid', _supTotalPaid),
              const SizedBox(width: 8),
              _statCard('currentDebt', _supTotalDebt),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loadingSup
                ? const Center(child: CircularProgressIndicator())
                : _fSup.isEmpty
                    ? const Center(child: Text('لا توجد بيانات'))
                    : _scrollableTable(
                        hCtrl: _supH,
                        vCtrl: _supV,
                        columns: const [
                          DataColumn(label: Text('المورد')),
                          DataColumn(label: Text('إجمالي المشتريات')),
                          DataColumn(label: Text('إجمالي المدفوع')),
                          DataColumn(label: Text('الدين الحالي')),
                          DataColumn(label: Text('خيارات')),
                        ],
                        rows: _fSup.map((s) {
                          final debt = (s['debt'] as num? ?? 0).toDouble();
                          final totPur =
                              (s['total_purchases'] as num? ?? 0).toDouble();
                          final totPaid =
                              (s['total_paid'] as num? ?? 0).toDouble();
                          final name = s['full_name'] ?? '';
                          final company = s['company_name'] ?? '';
                          return DataRow(cells: [
                            DataCell(Text(
                                '$name${company != null && company.isNotEmpty ? ' ($company)' : ''}')),
                            DataCell(Text(totPur.toStringAsFixed(2))),
                            DataCell(Text(totPaid.toStringAsFixed(2))),
                            DataCell(Text(
                              debt.toStringAsFixed(2),
                              style: TextStyle(
                                color: debt > 0 ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            )),
                            DataCell(
                              ElevatedButton.icon(
                                icon: const Icon(Icons.payments),
                                label: const Text('سداد'),
                                onPressed: debt > 0
                                    ? () => _supplierPayDialog(s)
                                    : null,
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
          ),
        ],
      ),
    );
  }

  // ---------- Client tab ----------
  Widget _clientsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Same as suppliers, keep commented unless needed
              // SizedBox(
              //   width: 120,
              //   child: DropdownButtonFormField<int>(
              //     value: _selCliYear,
              //     decoration: const InputDecoration(labelText: 'السنة'),
              //     items: _cliYears
              //         .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
              //         .toList(),
              //     onChanged: (y) {
              //       if (y == null) return;
              //       setState(() => _selCliYear = y);
              //       _fetchClients();
              //     },
              //   ),
              // ),
              // SizedBox(
              //   width: 140,
              //   child: DropdownButtonFormField<String>(
              //     value: _selCliMonth,
              //     decoration: const InputDecoration(labelText: 'الشهر'),
              //     items: _cliMonths
              //         .map((m) => DropdownMenuItem(
              //               value: m,
              //               child: Text(_arMonths[int.parse(m) - 1]),
              //             ))
              //         .toList(),
              //     onChanged: (m) {
              //       if (m == null) return;
              //       setState(() => _selCliMonth = m);
              //       _fetchClients();
              //     },
              //   ),
              // ),
              const SizedBox(width: 8),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _cliSearch,
                  decoration: const InputDecoration(
                    labelText: 'بحث بالعميل',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _fetchClients,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statCard('totalPurchases', _cliTotalInvoiced),
              const SizedBox(width: 8),
              _statCard('totalPaid', _cliTotalPaid),
              const SizedBox(width: 8),
              _statCard('currentDebt', _cliTotalDebt),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loadingCli
                ? const Center(child: CircularProgressIndicator())
                : _fCli.isEmpty
                    ? const Center(child: Text('لا توجد بيانات'))
                    : _scrollableTable(
                        hCtrl: _cliH,
                        vCtrl: _cliV,
                        columns: const [
                          DataColumn(label: Text('العميل')),
                          DataColumn(label: Text('الهاتف')),
                          DataColumn(label: Text('إجمالي الفواتير')),
                          DataColumn(label: Text('إجمالي المدفوع')),
                          DataColumn(label: Text('الدين الحالي')),
                          DataColumn(label: Text('خيارات')),
                        ],
                        rows: _fCli.map((c) {
                          final debt = (c['debt'] as num? ?? 0).toDouble();
                          final totInv =
                              (c['total_invoiced'] as num? ?? 0).toDouble();
                          final totPaid =
                              (c['total_paid'] as num? ?? 0).toDouble();
                          final name = c['full_name'] ?? '';
                          final phone = c['phone'] ?? '';
                          return DataRow(cells: [
                            DataCell(Text(name)),
                            DataCell(Text(phone)),
                            DataCell(Text(totInv.toStringAsFixed(2))),
                            DataCell(Text(totPaid.toStringAsFixed(2))),
                            DataCell(Text(
                              debt.toStringAsFixed(2),
                              style: TextStyle(
                                color: debt > 0 ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            )),
                            DataCell(
                              ElevatedButton.icon(
                                icon: const Icon(Icons.payments),
                                label: const Text('تسجيل'),
                                onPressed:
                                    debt > 0 ? () => _clientPayDialog(c) : null,
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _scrollableTable({
    required ScrollController hCtrl,
    required ScrollController vCtrl,
    required List<DataColumn> columns,
    required List<DataRow> rows,
  }) {
    return Scrollbar(
      controller: hCtrl,
      thumbVisibility: true,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: hCtrl,
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 900),
          child: Scrollbar(
            controller: vCtrl,
            thumbVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
            child: SingleChildScrollView(
              controller: vCtrl,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(
                    Theme.of(context).colorScheme.primary),
                headingTextStyle:
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                columns: columns,
                rows: rows,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard(String key, double val) {
  final cfg = _sumCfg[key]!;
  final Color light   = cfg['lightColor'] as Color;
  final Color dark    = cfg['darkColor']  as Color;
  final Color darker  = cfg['darkerColor'] as Color;

  return Expanded(
    child: Card(
      color: light,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              cfg['label'] as String,
              style: TextStyle(color: dark, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              val.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 20,
                color: darker,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Future<void> _supplierPayDialog(Map<String, dynamic> sup) async {
    final ctl = TextEditingController();
    bool submitting = false;
    final currentDebt = (sup['debt'] as num?)?.toDouble() ?? 0.0;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('سداد دفعة إلى المورد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${sup['full_name']}${(sup['company_name'] ?? '').toString().isNotEmpty ? ' (${sup['company_name']})' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('الدين الحالي: ${currentDebt.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.attach_money),
                  label: const Text('تسديد الكل'),
                  onPressed: currentDebt > 0
                      ? () => setD(() => ctl.text = currentDebt.toStringAsFixed(2))
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'المبلغ (الحد الأقصى: ${currentDebt.toStringAsFixed(2)})',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final a = double.tryParse(v) ?? 0;
                  if (a > currentDebt) {
                    setD(() => ctl.text = currentDebt.toStringAsFixed(2));
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text('سداد'),
              onPressed: submitting
                  ? null
                  : () async {
                      final amount = double.tryParse(ctl.text) ?? 0;
                      if (amount <= 0) {
                        _snack('أدخل مبلغًا صحيحًا', err: true);
                        return;
                      }
                      if (amount > currentDebt) {
                        _snack('المبلغ أكبر من الدين', err: true);
                        return;
                      }
                      setD(() => submitting = true);
                      try {
                        final res = await http.post(
                          Uri.parse('$baseUrl/suppliers/${sup['id']}/pay'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'amount': amount}),
                        );
                        if (res.statusCode == 200) {
                          _snack('تم تسجيل الدفع بنجاح');
                          Navigator.pop(ctx);
                          await _fetchSuppliers();
                        } else {
                          final err = jsonDecode(res.body);
                          _snack('فشل التسجيل: ${err['error']}', err: true);
                        }
                      } catch (e) {
                        _snack('خطأ اتصال: $e', err: true);
                      }
                      setD(() => submitting = false);
                    },
            ),
          ],
        );
      }),
    );
  }

  Future<void> _clientPayDialog(Map<String, dynamic> cli) async {
    final ctl = TextEditingController();
    bool submitting = false;
    final currentDebt = (cli['debt'] as num?)?.toDouble() ?? 0.0;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('تسجيل دفعة من العميل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(cli['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('الدين الحالي: ${currentDebt.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.attach_money),
                  label: const Text('تسديد الكل'),
                  onPressed: currentDebt > 0
                      ? () => setD(() => ctl.text = currentDebt.toStringAsFixed(2))
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'المبلغ (الحد الأقصى: ${currentDebt.toStringAsFixed(2)})',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final a = double.tryParse(v) ?? 0;
                  if (a > currentDebt) {
                    setD(() => ctl.text = currentDebt.toStringAsFixed(2));
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text('تسجيل'),
              onPressed: submitting
                  ? null
                  : () async {
                      final amount = double.tryParse(ctl.text) ?? 0;
                      if (amount <= 0) {
                        _snack('أدخل مبلغًا صحيحًا', err: true);
                        return;
                      }
                      if (amount > currentDebt) {
                        _snack('المبلغ أكبر من الدين', err: true);
                        return;
                      }
                      setD(() => submitting = true);
                      try {
                        final res = await http.post(
                          Uri.parse('$baseUrl/clients/${cli['id']}/pay'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'amount': amount}),
                        );
                        if (res.statusCode == 200) {
                          _snack('تم تسجيل الدفع بنجاح');
                          Navigator.pop(ctx);
                          await _fetchClients();
                        } else {
                          final err = jsonDecode(res.body);
                          _snack('فشل التسجيل: ${err['error']}', err: true);
                        }
                      } catch (e) {
                        _snack('خطأ اتصال: $e', err: true);
                      }
                      setD(() => submitting = false);
                    },
            ),
          ],
        );
      }),
    );
  }
}
