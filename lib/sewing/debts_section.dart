import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DebtsSection extends StatefulWidget {
  const DebtsSection({super.key});

  @override
  State<DebtsSection> createState() => _DebtsSectionState();
}

class _DebtsSectionState extends State<DebtsSection> {
  int selectedTab = 0;

  // Scroll controllers
  final ScrollController supplierTableController = ScrollController();
  final ScrollController clientTableController = ScrollController();

  // Raw data
  List<Map<String, dynamic>> supplierDebts = [];
  List<Map<String, dynamic>> clientDebts = [];

  // Filtered views
  List<Map<String, dynamic>> filteredSupplierDebts = [];
  List<Map<String, dynamic>> filteredClientDebts = [];

  // Loading flags
  bool loadingSuppliers = false;
  bool loadingClients = false;

  // Search controllers
  final TextEditingController supplierSearchController = TextEditingController();
  final TextEditingController clientSearchController = TextEditingController();

  // Date filters (year/month)
  late List<int> supplierYears;
  late List<String> supplierMonths;
  int selectedSupplierYear = DateTime.now().year;
  String selectedSupplierMonth = DateTime.now().month.toString().padLeft(2, '0');

  late List<int> clientYears;
  late List<String> clientMonths;
  int selectedClientYear = DateTime.now().year;
  String selectedClientMonth = DateTime.now().month.toString().padLeft(2, '0');

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

  final String baseUrl = 'http://localhost:8888';

  @override
  void initState() {
    super.initState();
    supplierYears = [];
    supplierMonths = [];
    clientYears = [];
    clientMonths = [];
    _fetchSupplierDebts();
    _fetchClientDebts();

    supplierSearchController.addListener(() {
      final q = supplierSearchController.text.toLowerCase();
      setState(() {
        filteredSupplierDebts = supplierDebts.where((s) {
          final name = (s['full_name'] ?? '').toString().toLowerCase();
          final company = (s['company_name'] ?? '').toString().toLowerCase();
          return name.contains(q) || company.contains(q);
        }).toList();
      });
    });

    clientSearchController.addListener(() {
      final q = clientSearchController.text.toLowerCase();
      setState(() {
        filteredClientDebts = clientDebts.where((c) {
          final name = (c['full_name'] ?? '').toString().toLowerCase();
          return name.contains(q);
        }).toList();
      });
    });
  }

  @override
  void dispose() {
    supplierTableController.dispose();
    clientTableController.dispose();
    supplierSearchController.dispose();
    clientSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSupplierDebts() async {
    setState(() => loadingSuppliers = true);
    try {
      final allResp = await http.get(Uri.parse('$baseUrl/debts/suppliers'));
      if (allResp.statusCode == 200) {
        supplierDebts = (jsonDecode(allResp.body) as List).cast<Map<String, dynamic>>();
      } else {
        supplierDebts = [];
      }
      final years = <int>{};
      final months = <String>{};
      for (var s in supplierDebts) {
        final d = s['date'] as String?;
        if (d != null && d.contains('-')) {
          final parts = d.split('-');
          years.add(int.parse(parts[0]));
          months.add(parts[1]);
        }
      }
      if (years.isEmpty) years.add(DateTime.now().year);
      supplierYears = years.toList()..sort((a, b) => b.compareTo(a));
      supplierMonths = months.toList()..sort();

      if (!supplierYears.contains(selectedSupplierYear)) {
        selectedSupplierYear = supplierYears.first;
      }
      if (!supplierMonths.contains(selectedSupplierMonth)) {
        selectedSupplierMonth = supplierMonths.first;
      }

      final uri = Uri.parse(
        '$baseUrl/debts/suppliers?year=$selectedSupplierYear&month=$selectedSupplierMonth',
      );
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        filteredSupplierDebts = (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
      } else {
        filteredSupplierDebts = [];
        _showSnackBar('فشل تحميل ديون الموردين: ${response.reasonPhrase}', color: Colors.red);
      }
    } catch (e) {
      supplierDebts = [];
      filteredSupplierDebts = [];
      _showSnackBar('خطأ في الاتصال: $e', color: Colors.red);
    }
    setState(() => loadingSuppliers = false);
  }

  Future<void> _fetchClientDebts() async {
    setState(() => loadingClients = true);
    try {
      final allResp = await http.get(Uri.parse('$baseUrl/debts/clients'));
      if (allResp.statusCode == 200) {
        clientDebts = (jsonDecode(allResp.body) as List).cast<Map<String, dynamic>>();
      } else {
        clientDebts = [];
      }
      final years = <int>{};
      final months = <String>{};
      for (var c in clientDebts) {
        final d = c['date'] as String?;
        if (d != null && d.contains('-')) {
          final parts = d.split('-');
          years.add(int.parse(parts[0]));
          months.add(parts[1]);
        }
      }
      if (years.isEmpty) years.add(DateTime.now().year);
      clientYears = years.toList()..sort((a, b) => b.compareTo(a));
      clientMonths = months.toList()..sort();

      final uri = Uri.parse(
        '$baseUrl/debts/clients?year=$selectedClientYear&month=$selectedClientMonth',
      );
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        filteredClientDebts = (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
      } else {
        filteredClientDebts = [];
        _showSnackBar('فشل تحميل ديون العملاء: ${response.reasonPhrase}', color: Colors.red);
      }
    } catch (e) {
      clientDebts = [];
      filteredClientDebts = [];
      _showSnackBar('خطأ في الاتصال: $e', color: Colors.red);
    }
    setState(() => loadingClients = false);
  }

  void _showSnackBar(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  // Supplier summaries
  double get _suppliersTotalPurchases =>
      supplierDebts.fold(0.0, (sum, e) => sum + (e['total_purchases'] as num? ?? 0).toDouble());
  double get _suppliersTotalPaid =>
      supplierDebts.fold(0.0, (sum, e) => sum + (e['total_paid'] as num? ?? 0).toDouble());
  double get _suppliersTotalDebt =>
      supplierDebts.fold(0.0, (sum, e) => sum + (e['debt'] as num? ?? 0).toDouble());

  // Client summaries
  double get _clientsTotalInvoiced =>
      clientDebts.fold(0.0, (sum, e) => sum + (e['total_invoiced'] as num? ?? 0).toDouble());
  double get _clientsTotalPaid =>
      clientDebts.fold(0.0, (sum, e) => sum + (e['total_paid'] as num? ?? 0).toDouble());
  double get _clientsTotalDebt =>
      clientDebts.fold(0.0, (sum, e) => sum + (e['debt'] as num? ?? 0).toDouble());

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // Tabs
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              2,
              (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ChoiceChip(
                  label: Text(i == 0 ? 'ديون الموردين' : 'ديون العملاء'),
                  selected: selectedTab == i,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  labelStyle: TextStyle(
                    color: selectedTab == i ? Colors.white : null,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (_) => setState(() => selectedTab = i),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Content
          Expanded(
            child: selectedTab == 0 ? _buildSuppliersTab() : _buildClientsTab(),
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
          // Filters + Search
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
                  controller: supplierSearchController,
                  decoration: const InputDecoration(
                    labelText: 'بحث بالمورد/الشركة',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _fetchSupplierDebts,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Summary Cards
          Row(
            children: [
              _buildStatCard('totalPurchases', _suppliersTotalPurchases),
              const SizedBox(width: 8),
              _buildStatCard('totalPaid', _suppliersTotalPaid),
              const SizedBox(width: 8),
              _buildStatCard('currentDebt', _suppliersTotalDebt),
            ],
          ),
          const SizedBox(height: 16),
          // Table
          Expanded(
            child: loadingSuppliers
                ? const Center(child: CircularProgressIndicator())
                : filteredSupplierDebts.isEmpty
                    ? const Center(child: Text('لا توجد بيانات'))
                    : Scrollbar(
                        controller: supplierTableController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: supplierTableController,
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(
                                Theme.of(context).colorScheme.primary,
                              ),
                              headingTextStyle:
                                  const TextStyle(color: Colors.white),
                              columns: const [
                                DataColumn(label: Text('المورد')),
                                DataColumn(label: Text('إجمالي المشتريات')),
                                DataColumn(label: Text('إجمالي المدفوع')),
                                DataColumn(label: Text('الدين الحالي')),
                                DataColumn(label: Text('خيارات')),
                              ],
                              rows: filteredSupplierDebts.map((s) {
                                final debt =
                                    (s['debt'] as num? ?? 0).toDouble();
                                final totPur = (s['total_purchases']
                                        as num? ??
                                    0)
                                    .toDouble();
                                final totPaid =
                                    (s['total_paid'] as
                                            num? ??
                                        0)
                                        .toDouble();
                                final name = s['full_name'] ?? '';
                                final company = s['company_name'] ?? '';
                                return DataRow(cells: [
                                  DataCell(Text(name +
                                      (company.isNotEmpty
                                          ? ' ($company)'
                                          : ''))),
                                  DataCell(
                                      Text(totPur.toStringAsFixed(2))),
                                  DataCell(
                                      Text(totPaid.toStringAsFixed(2))),
                                  DataCell(Text(
                                    debt.toStringAsFixed(2),
                                    style: TextStyle(
                                      color: debt > 0
                                          ? Colors.red
                                          : Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )),
                                  DataCell(ElevatedButton.icon(
                                    icon: const Icon(Icons.payments),
                                    label: const Text('سداد'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(80, 36),
                                    ),
                                    onPressed: debt > 0
                                        ? () =>
                                            _showSupplierPaymentDialog(
                                                s)
                                        : null,
                                  )),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
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
          // Filters + Search
         
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
                  controller: clientSearchController,
                  decoration: const InputDecoration(
                    labelText: 'بحث بالمورد/الشركة',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _fetchClientDebts,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Summary Cards
          Row(
            children: [
              _buildStatCard('totalPurchases', _clientsTotalInvoiced),
              const SizedBox(width: 8),
              _buildStatCard('totalPaid', _clientsTotalPaid),
              const SizedBox(width: 8),
              _buildStatCard('currentDebt', _clientsTotalDebt),
            ],
          ),
          const SizedBox(height: 16),
          // Table
          Expanded(
            child: loadingClients
                ? const Center(child: CircularProgressIndicator())
                : filteredClientDebts.isEmpty
                    ? const Center(child: Text('لا توجد بيانات'))
                    : Scrollbar(
                        controller: clientTableController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: clientTableController,
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(
                                Theme.of(context).colorScheme.primary,
                              ),
                              headingTextStyle:
                                  const TextStyle(color: Colors.white),
                              columns: const [
                                DataColumn(label: Text('العميل')),
                                DataColumn(label: Text('الهاتف')),
                                DataColumn(label: Text('إجمالي الفواتير')),
                                DataColumn(label: Text('إجمالي المدفوع')),
                                DataColumn(label: Text('الدين الحالي')),
                                DataColumn(label: Text('خيارات')),
                              ],
                              rows: filteredClientDebts.map((c) {
                                final debt =
                                    (c['debt'] as num? ?? 0).toDouble();
                                final totInv = (c['total_invoiced']
                                        as num? ??
                                    0)
                                    .toDouble();
                                final totPaid =
                                    (c['total_paid'] as
                                            num? ??
                                        0)
                                        .toDouble();
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
                                      color: debt > 0
                                          ? Colors.red
                                          : Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )),
                                  DataCell(ElevatedButton.icon(
                                    icon: const Icon(Icons.payments),
                                    label: const Text('تسجيل'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(80, 36),
                                    ),
                                    onPressed: debt > 0
                                        ? () => _showClientPaymentDialog(c)
                                        : null,
                                  )),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
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
                  fontWeight: FontWeight.bold,
                ),
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

  Future<void> _showSupplierPaymentDialog(Map<String, dynamic> supplier) async {
    final amountController = TextEditingController();
    bool submitting = false;
    final currentDebt = (supplier['debt'] as num?)?.toDouble() ?? 0.0;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('سداد دفعة إلى المورد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${supplier['full_name']}${supplier['company_name'] != null && supplier['company_name'] != '' ? " (${supplier['company_name']})" : ""}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text('الدين الحالي: ${currentDebt.toStringAsFixed(2)} ج.م'),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.attach_money),
                  label: const Text('تسديد الكل'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: currentDebt > 0
                      ? () => setDialog(() {
                            amountController.text =
                                currentDebt.toStringAsFixed(2);
                          })
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText:
                      'المبلغ الذي تم دفعه (الحد الأقصى: ${currentDebt.toStringAsFixed(2)})',
                  prefixIcon: const Icon(Icons.payments),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final amount = double.tryParse(value) ?? 0.0;
                  if (amount > currentDebt) {
                    setDialog(() {
                      amountController.text =
                          currentDebt.toStringAsFixed(2);
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text('سداد'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      final amount =
                          double.tryParse(amountController.text) ?? 0;
                      if (amount <= 0) {
                        _showSnackBar('يجب إدخال مبلغ صحيح',
                            color: Colors.red);
                        return;
                      }
                      if (amount > currentDebt) {
                        _showSnackBar('لا يمكن دفع أكثر من قيمة الدين',
                            color: Colors.red);
                        return;
                      }

                      setDialog(() => submitting = true);
                      try {
                        final res = await http.post(
                          Uri.parse(
                              '$baseUrl/debts/suppliers/${supplier['id']}/pay'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'amount': amount}),
                        );

                        if (res.statusCode == 200) {
                          _showSnackBar(
                            'تم تسجيل دفع بقيمة ${amount.toStringAsFixed(2)} ج.م بنجاح!',
                            color: Colors.green,
                          );
                          Navigator.pop(context);
                          await _fetchSupplierDebts();
                        } else {
                          final error = jsonDecode(res.body);
                          _showSnackBar(
                            'فشل في تسجيل الدفع: ${error['error'] ?? 'خطأ غير معروف'}',
                            color: Colors.red,
                          );
                        }
                      } catch (e) {
                        _showSnackBar('خطأ في الاتصال: $e',
                            color: Colors.red);
                      }
                      setDialog(() => submitting = false);
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClientPaymentDialog(Map<String, dynamic> client) async {
    final amountController = TextEditingController();
    bool submitting = false;
    final currentDebt = (client['debt'] as num?)?.toDouble() ?? 0.0;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('تسجيل دفعة من العميل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${client['full_name']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text('الدين الحالي: ${currentDebt.toStringAsFixed(2)} ج.م'),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.attach_money),
                  label: const Text('تسديد الكل'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: currentDebt > 0
                      ? () => setDialog(() {
                            amountController.text =
                                currentDebt.toStringAsFixed(2);
                          })
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText:
                      'المبلغ الذي تم دفعه (الحد الأقصى: ${currentDebt.toStringAsFixed(2)})',
                  prefixIcon: const Icon(Icons.payments),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final amount = double.tryParse(value) ?? 0.0;
                  if (amount > currentDebt) {
                    setDialog(() {
                      amountController.text =
                          currentDebt.toStringAsFixed(2);
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text('تسجيل'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      final amount =
                          double.tryParse(amountController.text) ?? 0;
                      if (amount <= 0) {
                        _showSnackBar('يجب إدخال مبلغ صحيح',
                            color: Colors.red);
                        return;
                      }
                      if (amount > currentDebt) {
                        _showSnackBar('لا يمكن دفع أكثر من قيمة الدين',
                            color: Colors.red);
                        return;
                      }

                      setDialog(() => submitting = true);
                      try {
                        final res = await http.post(
                          Uri.parse(
                              '$baseUrl/debts/clients/${client['id']}/pay'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'amount': amount}),
                        );

                        if (res.statusCode == 200) {
                          _showSnackBar(
                            'تم تسجيل دفع بقيمة ${amount.toStringAsFixed(2)} ج.م بنجاح!',
                            color: Colors.green,
                          );
                          Navigator.pop(context);
                          await _fetchClientDebts();
                        } else {
                          final error = jsonDecode(res.body);
                          _showSnackBar(
                            'فشل في تسجيل الدفع: ${error['error'] ?? 'خطأ غير معروف'}',
                            color: Colors.red,
                          );
                        }
                      } catch (e) {
                        _showSnackBar('خطأ في الاتصال: $e',
                            color: Colors.red);
                      }
                      setDialog(() => submitting = false);
                    },
            ),
          ],
        ),
      ),
    );
  }
}
