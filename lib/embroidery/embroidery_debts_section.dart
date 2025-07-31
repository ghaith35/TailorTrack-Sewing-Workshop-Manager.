import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class EmbroideryDebtsSection extends StatefulWidget {
  const EmbroideryDebtsSection({Key? key}) : super(key: key);

  @override
  State<EmbroideryDebtsSection> createState() => _EmbroideryDebtsSectionState();
}

class _EmbroideryDebtsSectionState extends State<EmbroideryDebtsSection> {
  int selectedTab = 0;

  // Scroll controllers
  final ScrollController supplierTableController = ScrollController();
  final ScrollController clientTableController   = ScrollController();

  // Search controllers
  final TextEditingController supplierSearchController = TextEditingController();
  final TextEditingController clientSearchController   = TextEditingController();

  // Raw data
  List<Map<String, dynamic>> supplierDebts         = [];
  List<Map<String, dynamic>> filteredSupplierDebts = [];
  List<Map<String, dynamic>> clientDebts           = [];
  List<Map<String, dynamic>> filteredClientDebts   = [];

  // Loading flags
  bool loadingSuppliers = false;
  bool loadingClients   = false;

  // Date filters for suppliers
  late List<int> supplierYears;
  late List<String> supplierMonths;
  int selectedSupplierYear  = DateTime.now().year;
  String selectedSupplierMonth =
      DateTime.now().month.toString().padLeft(2, '0');

  // Date filters for clients
  late List<int> clientYears;
  late List<String> clientMonths;
  int selectedClientYear  = DateTime.now().year;
  String selectedClientMonth =
      DateTime.now().month.toString().padLeft(2, '0');

  // Month names in Arabic
  static const List<String> monthNames = [
    'جانفي', 'فيفري', 'مارس', 'أفريل',
    'ماي', 'جوان', 'جويلية', 'أوت',
    'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

  // Summary labels/colors
  final Map<String, Map<String, dynamic>> summaryLabels = {
    'totalPurchases': {
      'label': 'إجمالي المشتريات',
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

  final String baseUrl = 'http://127.0.0.1:8888/embrodry';

  @override
  void initState() {
    super.initState();
    supplierYears   = [];
    supplierMonths  = [];
    clientYears     = [];
    clientMonths    = [];

    _fetchSupplierDebts();
    _fetchClientDebts();

    supplierSearchController.addListener(_onSupplierSearch);
    clientSearchController.addListener(_onClientSearch);
  }

  @override
  void dispose() {
    supplierTableController.dispose();
    clientTableController.dispose();
    supplierSearchController.dispose();
    clientSearchController.dispose();
    super.dispose();
  }

  void _onSupplierSearch() {
    final q = supplierSearchController.text.toLowerCase();
    setState(() {
      filteredSupplierDebts = supplierDebts.where((s) {
        final name    = (s['full_name'] ?? '').toString().toLowerCase();
        final company = (s['company_name'] ?? '').toString().toLowerCase();
        return name.contains(q) || company.contains(q);
      }).toList();
    });
  }

  void _onClientSearch() {
    final q = clientSearchController.text.toLowerCase();
    setState(() {
      filteredClientDebts = clientDebts.where((c) {
        final name = (c['full_name'] ?? '').toString().toLowerCase();
        return name.contains(q);
      }).toList();
    });
  }

  Future<void> _fetchSupplierDebts() async {
    setState(() => loadingSuppliers = true);
    try {
      final resp = await http.get(Uri.parse('$baseUrl/debts/suppliers'));
      if (resp.statusCode == 200) {
        supplierDebts = (jsonDecode(resp.body) as List)
            .cast<Map<String, dynamic>>();
      } else {
        supplierDebts = [];
      }

      // build year/month filters...
      final years  = <int>{};
      final months = <String>{};
      for (var s in supplierDebts) {
        final d = s['date'] as String? ?? '';
        if (d.contains('-')) {
          final parts = d.split('-');
          years.add(int.parse(parts[0]));
          months.add(parts[1]);
        }
      }
      if (years.isEmpty) years.add(DateTime.now().year);
      supplierYears  = years.toList()..sort((a, b) => b.compareTo(a));
      supplierMonths = months.toList()..sort();
      if (!supplierYears.contains(selectedSupplierYear))
        selectedSupplierYear = supplierYears.first;
      if (!supplierMonths.contains(selectedSupplierMonth))
        selectedSupplierMonth = supplierMonths.first;

      // fetch filtered
      final uri = Uri.parse(
        '$baseUrl/debts/suppliers?year=$selectedSupplierYear&month=$selectedSupplierMonth',
      );
      final fresp = await http.get(uri);
      if (fresp.statusCode == 200) {
        filteredSupplierDebts = (jsonDecode(fresp.body) as List)
            .cast<Map<String, dynamic>>();
      } else {
        filteredSupplierDebts = [];
        _showSnackBar('فشل تحميل ديون الموردين', color: Colors.red);
      }
    } catch (e) {
   
    }
    setState(() => loadingSuppliers = false);
  }

  Future<void> _fetchClientDebts() async {
    setState(() => loadingClients = true);
    try {
      final resp = await http.get(Uri.parse('$baseUrl/debts/clients'));
      if (resp.statusCode == 200) {
        clientDebts = (jsonDecode(resp.body) as List)
            .cast<Map<String, dynamic>>();
      } else {
        clientDebts = [];
      }
      // build year/month...
      final years  = <int>{};
      final months = <String>{};
      for (var c in clientDebts) {
        final d = c['date'] as String? ?? '';
        if (d.contains('-')) {
          final parts = d.split('-');
          years.add(int.parse(parts[0]));
          months.add(parts[1]);
        }
      }
      if (years.isEmpty) years.add(DateTime.now().year);
      clientYears  = years.toList()..sort((a, b) => b.compareTo(a));
      clientMonths = months.toList()..sort();
      if (!clientYears.contains(selectedClientYear))
        selectedClientYear = clientYears.first;
      if (!clientMonths.contains(selectedClientMonth))
        selectedClientMonth = clientMonths.first;

      final uri = Uri.parse(
        '$baseUrl/debts/clients?year=$selectedClientYear&month=$selectedClientMonth',
      );
      final fresp = await http.get(uri);
      if (fresp.statusCode == 200) {
        filteredClientDebts = (jsonDecode(fresp.body) as List)
            .cast<Map<String, dynamic>>();
      } else {
        filteredClientDebts = [];
        _showSnackBar('فشل تحميل ديون العملاء', color: Colors.red);
      }
    } catch (e) {
     
    }
    setState(() => loadingClients = false);
  }

  void _showSnackBar(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  double get _suppliersTotalPurchases =>
      supplierDebts.fold(0.0, (s, e) => s + _toDouble(e['total_purchases']));
  double get _suppliersTotalPaid =>
      supplierDebts.fold(0.0, (s, e) => s + _toDouble(e['total_paid']));
  double get _suppliersTotalDebt =>
      supplierDebts.fold(0.0, (s, e) => s + _toDouble(e['debt']));

  double get _clientsTotalInvoiced =>
      clientDebts.fold(0.0, (s, e) => s + _toDouble(e['total_invoiced']));
  double get _clientsTotalPaid =>
      clientDebts.fold(0.0, (s, e) => s + _toDouble(e['total_paid']));
  double get _clientsTotalDebt =>
      clientDebts.fold(0.0, (s, e) => s + _toDouble(e['debt']));

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ['ديون الموردين', 'ديون العملاء']
                .asMap()
                .entries
                .map((e) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: selectedTab == e.key,
                        selectedColor:
                            Theme.of(context).colorScheme.primary,
                        labelStyle: TextStyle(
                          color: selectedTab == e.key
                              ? Colors.white
                              : null,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) =>
                            setState(() => selectedTab = e.key),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: selectedTab == 0
                ? _buildSuppliersTab()
                : _buildClientsTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuppliersTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSearchRefreshRow(
            controller: supplierSearchController,
            hint: 'بحث بالمورد/الشركة',
            onRefresh: _fetchSupplierDebts,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatCard(
                  'totalPurchases', _suppliersTotalPurchases),
              const SizedBox(width: 8),
              _buildStatCard(
                  'totalPaid', _suppliersTotalPaid),
              const SizedBox(width: 8),
              _buildStatCard(
                  'currentDebt', _suppliersTotalDebt),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: loadingSuppliers
                ? const Center(child: CircularProgressIndicator())
                : _buildDataTable(
                    controller: supplierTableController,
                    columns: const [
                      'المورد',
                      'إجمالي المشتريات',
                      'إجمالي المدفوع',
                      'الدين الحالي',
                      'خيارات',
                    ],
                    rows: filteredSupplierDebts.map((s) {
                      final debt    = _toDouble(s['debt']);
                      final totPur  = _toDouble(s['total_purchases']);
                      final totPaid = _toDouble(s['total_paid']);
                      return DataRow(cells: [
                        DataCell(Text(
                          '${s['full_name'] ?? ''}'
                          '${(s['company_name'] ?? '').isNotEmpty
                              ? ' (${s['company_name']})'
                              : ''}',
                        )),
                        DataCell(
                            Text(totPur.toStringAsFixed(2))),
                        DataCell(
                            Text(totPaid.toStringAsFixed(2))),
                        DataCell(Text(
                          debt.toStringAsFixed(2),
                          style: TextStyle(
                            color:
                                debt > 0 ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        )),
                        DataCell(ElevatedButton.icon(
                          icon: const Icon(Icons.payments),
                          label: const Text('سداد'),
                          onPressed: debt > 0
                              ? () => _showSupplierPaymentDialog(s)
                              : null,
                        )),
                      ]);
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSearchRefreshRow(
            controller: clientSearchController,
            hint: 'بحث بالعميل',
            onRefresh: _fetchClientDebts,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatCard(
                  'totalPurchases', _clientsTotalInvoiced),
              const SizedBox(width: 8),
              _buildStatCard(
                  'totalPaid', _clientsTotalPaid),
              const SizedBox(width: 8),
              _buildStatCard(
                  'currentDebt', _clientsTotalDebt),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: loadingClients
                ? const Center(child: CircularProgressIndicator())
                : _buildDataTable(
                    controller: clientTableController,
                    columns: const [
                      'العميل',
                      'الهاتف',
                      'إجمالي الفواتير',
                      'إجمالي المدفوع',
                      'الدين الحالي',
                      'خيارات',
                    ],
                    rows: filteredClientDebts.map((c) {
                      final debt = _toDouble(c['debt']);
                      final inv  = _toDouble(c['total_invoiced']);
                      final paid = _toDouble(c['total_paid']);
                      return DataRow(cells: [
                        DataCell(Text(c['full_name'] ?? '')),
                        DataCell(Text(c['phone'] ?? '')),
                        DataCell(Text(inv.toStringAsFixed(2))),
                        DataCell(Text(paid.toStringAsFixed(2))),
                        DataCell(Text(
                          debt.toStringAsFixed(2),
                          style: TextStyle(
                            color:
                                debt > 0 ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        )),
                        DataCell(ElevatedButton.icon(
                          icon: const Icon(Icons.payments),
                          label: const Text('سداد'),
                          onPressed: debt > 0
                              ? () => _showClientPaymentDialog(c)
                              : null,
                        )),
                      ]);
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRefreshRow({
    required TextEditingController controller,
    required String hint,
    required Future<void> Function() onRefresh,
  }) {
    return Wrap(
      spacing: 8,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: controller,
            decoration:
                InputDecoration(labelText: hint, prefixIcon: const Icon(Icons.search)),
          ),
        ),
        IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh),
      ],
    );
  }

  Widget _buildDataTable({
    required ScrollController controller,
    required List<String> columns,
    required List<DataRow> rows,
  }) {
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(
              Theme.of(context).colorScheme.primary,
            ),
            headingTextStyle: const TextStyle(color: Colors.white),
            columns:
                columns.map((c) => DataColumn(label: Text(c))).toList(),
            rows: rows,
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String key, double value) {
    final cfg = summaryLabels[key]!;
    return Expanded(
      child: Card(
        color: cfg['lightColor'] as Color,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                cfg['label'] as String,
                style: TextStyle(
                    color: cfg['darkColor'] as Color,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 20,
                  color: cfg['darkerColor'] as Color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Payment dialogs (unchanged)...
  // Future<void> _showSupplierPaymentDialog(Map<String, dynamic> supplier) async {
  //   // ...same as before...
  // }

  // Future<void> _showClientPaymentDialog(Map<String, dynamic> client) async {
  //   // ...same as before...
  // }
 Future<void> _showSupplierPaymentDialog(Map<String, dynamic> sup) async {
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
  Uri.parse('$baseUrl/debts/suppliers/${sup['id']}/pay'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'amount': amount}),
                        );
                        if (res.statusCode == 200) {
                          _snack('تم تسجيل الدفع بنجاح');
                          Navigator.pop(ctx);
                          await _fetchSupplierDebts();
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
 void _snack(String msg, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: err ? Colors.red : Colors.green),
    );
  }
  Future<void> _showClientPaymentDialog(Map<String, dynamic> cli) async {
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
      Uri.parse('$baseUrl/debts/clients/${cli['id']}/pay'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'amount': amount}),
                        );
                        if (res.statusCode == 200) {
                          _snack('تم تسجيل الدفع بنجاح');
                          Navigator.pop(ctx);
                          await _fetchClientDebts();
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
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    throw FormatException('Cannot convert ${v.runtimeType} to double');
  }
}
