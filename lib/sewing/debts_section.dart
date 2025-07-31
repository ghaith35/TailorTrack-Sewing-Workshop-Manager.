import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DebtsSection extends StatefulWidget {
  final String role;

  const DebtsSection({Key? key, required this.role}) : super(key: key);

  @override
  State<DebtsSection> createState() => _DebtsSectionState();
}

class _DebtsSectionState extends State<DebtsSection> {
  int selectedTab = 0;

  final ScrollController supplierTableController = ScrollController();
  final ScrollController clientTableController    = ScrollController();
  final ScrollController depositTableController   = ScrollController();

  final TextEditingController supplierSearchController = TextEditingController();
  final TextEditingController clientSearchController   = TextEditingController();
  final TextEditingController depositSearchController  = TextEditingController();

  List<Map<String, dynamic>> supplierDebts         = [];
  List<Map<String, dynamic>> filteredSupplierDebts = [];
  List<Map<String, dynamic>> clientDebts           = [];
  List<Map<String, dynamic>> filteredClientDebts   = [];
  List<Map<String, dynamic>> deposits              = [];
  List<Map<String, dynamic>> filteredDeposits      = [];

  Map<int, double> clientDepositTotals = {};

  bool loadingSuppliers = false;
  bool loadingClients   = false;
  bool loadingDeposits  = false;

  late List<int>    supplierYears;
  late List<String> supplierMonths;
  int selectedSupplierYear  = DateTime.now().year;
  String selectedSupplierMonth = DateTime.now().month.toString().padLeft(2, '0');

  late List<int>    clientYears;
  late List<String> clientMonths;
  int selectedClientYear  = DateTime.now().year;
  String selectedClientMonth = DateTime.now().month.toString().padLeft(2, '0');

  static const List<String> monthNames = [
    'جانفي', 'فيفري', 'مارس', 'أفريل',
    'ماي', 'جوان', 'جويلية', 'أوت',
    'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

  final Map<String, Map<String, dynamic>> summaryLabels = {
    'totalPurchases': {
      'label': 'إجمالي المشتريات',
      'lightColor': Colors.blue[50],
      'darkColor':  Colors.blue[800],
      'darkerColor':Colors.blue[900],
    },
    'totalPaid': {
      'label': 'إجمالي المدفوع',
      'lightColor': Colors.green[50],
      'darkColor':  Colors.green[800],
      'darkerColor':Colors.green[900],
    },
    'currentDebt': {
      'label': 'الدين الحالي',
      'lightColor': Colors.red[50],
      'darkColor':  Colors.red[800],
      'darkerColor':Colors.red[900],
    },
    'totalDeposit': {
      'label': 'إجمالي الإيداعات المتبقية',
      'lightColor': Colors.purple[50],
      'darkColor':  Colors.purple[800],
      'darkerColor':Colors.purple[900],
    },
    'totalOriginalDeposit': {
      'label': 'إجمالي الإيداعات الأصلية',
      'lightColor': Colors.purple[50],
      'darkColor':  Colors.purple[800],
      'darkerColor':Colors.purple[900],
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
    _fetchDeposits();

    supplierSearchController.addListener(_onSupplierSearch);
    clientSearchController.addListener(_onClientSearch);
    depositSearchController.addListener(_onDepositSearch);
  }

  @override
  void dispose() {
    supplierTableController.dispose();
    clientTableController.dispose();
    depositTableController.dispose();
    supplierSearchController.dispose();
    clientSearchController.dispose();
    depositSearchController.dispose();
    super.dispose();
  }

  void _onSupplierSearch() {
    final q = supplierSearchController.text.toLowerCase();
    setState(() {
      filteredSupplierDebts = supplierDebts.where((s) {
        final name    = (s['full_name']    ?? '').toString().toLowerCase();
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

  void _onDepositSearch() {
    final q = depositSearchController.text.toLowerCase();
    setState(() {
      filteredDeposits = deposits.where((d) {
        final client = (d['client_name'] ?? '').toString().toLowerCase();
        final notes  = (d['notes']       ?? '').toString().toLowerCase();
        return client.contains(q) || notes.contains(q);
      }).toList();
    });
  }

  Future<void> _fetchSupplierDebts() async {
    setState(() => loadingSuppliers = true);
    try {
      final resp = await http.get(Uri.parse('$baseUrl/debts/suppliers'));
      if (resp.statusCode == 200) {
        supplierDebts = (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
      } else {
        supplierDebts = [];
      }
      final years = <int>{};
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
      supplierYears = years.toList()..sort((a, b) => b.compareTo(a));
      supplierMonths = months.toList()..sort();
      if (!supplierYears.contains(selectedSupplierYear)) selectedSupplierYear = supplierYears.first;
      if (!supplierMonths.contains(selectedSupplierMonth)) selectedSupplierMonth = supplierMonths.first;

      final uri = Uri.parse(
        '$baseUrl/debts/suppliers?year=$selectedSupplierYear&month=$selectedSupplierMonth',
      );
      final fresp = await http.get(uri);
      if (fresp.statusCode == 200) {
        filteredSupplierDebts = (jsonDecode(fresp.body) as List).cast<Map<String, dynamic>>();
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
        clientDebts = (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
      } else {
        clientDebts = [];
      }
      final years = <int>{}, months = <String>{};
      for (var c in clientDebts) {
        final d = c['date'] as String? ?? '';
        if (d.contains('-')) {
          final parts = d.split('-');
          years.add(int.parse(parts[0]));
          months.add(parts[1]);
        }
      }
      if (years.isEmpty) years.add(DateTime.now().year);
      clientYears = years.toList()..sort((a, b) => b.compareTo(a));
      clientMonths = months.toList()..sort();
      if (!clientYears.contains(selectedClientYear)) selectedClientYear = clientYears.first;
      if (!clientMonths.contains(selectedClientMonth)) selectedClientMonth = clientMonths.first;

      final uri = Uri.parse(
        '$baseUrl/debts/clients?year=$selectedClientYear&month=$selectedClientMonth',
      );
      final fresp = await http.get(uri);
      if (fresp.statusCode == 200) {
        filteredClientDebts = (jsonDecode(fresp.body) as List).cast<Map<String, dynamic>>();
      } else {
        filteredClientDebts = [];
        _showSnackBar('فشل تحميل ديون العملاء', color: Colors.red);
      }
    } catch (e) {
    }
    setState(() => loadingClients = false);
  }

  Future<void> _fetchDeposits() async {
    setState(() => loadingDeposits = true);
    try {
      final resp = await http.get(Uri.parse('$baseUrl/debts/clients/deposits'));
      if (resp.statusCode == 200) {
        deposits = (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
      } else {
        deposits = [];
      }

      clientDepositTotals.clear();
      for (var d in deposits) {
        final cid = d['client_id'] as int;
        final amt = (d['amount'] as num).toDouble();
        clientDepositTotals[cid] = (clientDepositTotals[cid] ?? 0) + amt;
      }

      filteredDeposits = List.from(deposits);
    } catch (e) {
      deposits = [];
      filteredDeposits = [];
      clientDepositTotals.clear();
      _showSnackBar('خطأ في تحميل الإيداعات', color: Colors.red);
    }
    setState(() => loadingDeposits = false);
  }

  void _showSnackBar(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  double get _suppliersTotalPurchases =>
      supplierDebts.fold(0.0, (s, e) => s + (e['total_purchases'] as num? ?? 0).toDouble());
  double get _suppliersTotalPaid =>
      supplierDebts.fold(0.0, (s, e) => s + (e['total_paid'] as num? ?? 0).toDouble());
  double get _suppliersTotalDebt =>
      supplierDebts.fold(0.0, (s, e) => s + (e['debt'] as num? ?? 0).toDouble());

  double get _clientsTotalInvoiced =>
      clientDebts.fold(0.0, (s, e) => s + (e['total_invoiced'] as num? ?? 0).toDouble());
  double get _clientsTotalPaid =>
      clientDebts.fold(0.0, (s, e) => s + (e['total_paid'] as num? ?? 0).toDouble());
  double get _clientsTotalDebt =>
      clientDebts.fold(0.0, (s, e) => s + (e['debt'] as num? ?? 0).toDouble());

  double get _depositsTotal =>
      deposits.fold(0.0, (s, e) => s + (_toDouble(e['amount']) as double));
  double get _depositsOriginalTotal =>
      deposits.fold(0.0, (s, e) => s + (_toDouble(e['value']) as double));
@override
  Widget build(BuildContext context) {
    // determine which tabs to show
    final allLabels = ['ديون الموردين', 'ديون العملاء', 'ايداعات'];
    late final List<String> tabs;
    if (widget.role == 'Accountant') {
      tabs = ['ديون الموردين'];
    } else if (widget.role == 'Admin' || widget.role == 'SuperAdmin') {
      tabs = allLabels;
    } else {
      // for any other role, show only suppliers as a safe default
      tabs = ['ديون الموردين'];
    }

    // clamp selectedTab
    if (selectedTab >= tabs.length) selectedTab = 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // ─── Choice Chips ───────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: tabs.asMap().entries.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: selectedTab == e.key,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  labelStyle: TextStyle(
                    color: selectedTab == e.key ? Colors.white : null,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (_) => setState(() => selectedTab = e.key),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ─── Tab Content ─────────────────────────────────────────────
          Expanded(
            child: tabs[selectedTab] == 'ديون الموردين'
                ? _buildSuppliersTab()
                : tabs[selectedTab] == 'ديون العملاء'
                    ? _buildClientsTab()
                    : _buildDepositsTab(),
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
          if (widget.role == 'Admin' || widget.role == 'SuperAdmin') ...[
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
          ],
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
                      final debt = (s['debt'] as num? ?? 0).toDouble();
                      final totPur = (s['total_purchases'] as num? ?? 0).toDouble();
                      final totPaid = (s['total_paid'] as num? ?? 0).toDouble();
                      return DataRow(cells: [
                        DataCell(Text(
                          '${s['full_name'] ?? ''}${(s['company_name'] ?? '').isNotEmpty ? ' (${s['company_name']})' : ''}',
                        )),
                        DataCell(Text(totPur.toStringAsFixed(2))),
                        DataCell(Text(totPaid.toStringAsFixed(2))),
                        DataCell(Text(
                          debt.toStringAsFixed(2),
                          style: TextStyle(
                            color: debt > 0 ? Colors.red : Colors.green,
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
          if (widget.role == 'Admin' || widget.role == 'SuperAdmin') ...[
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
          ],
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
                      'الإيداع',
                      'الدين الحالي',
                      'خيارات',
                    ],
                    rows: filteredClientDebts.map((c) {
                      final debt = (c['debt'] as num? ?? 0).toDouble();
                      final inv = (c['total_invoiced'] as num? ?? 0).toDouble();
                      final paid = (c['total_paid'] as num? ?? 0).toDouble();
                      final dep = clientDepositTotals[c['id']] ?? 0.0;
                      return DataRow(cells: [
                        DataCell(Text(c['full_name'] ?? '')),
                        DataCell(Text(c['phone'] ?? '')),
                        DataCell(Text(inv.toStringAsFixed(2))),
                        DataCell(Text(paid.toStringAsFixed(2))),
                        DataCell(Text(dep.toStringAsFixed(2))),
                        DataCell(Text(
                          debt.toStringAsFixed(2),
                          style: TextStyle(
                            color: debt > 0 ? Colors.red : Colors.green,
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

  Widget _buildDepositsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: depositSearchController,
                  decoration: const InputDecoration(
                    labelText: 'بحث بالإيداع',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchDeposits),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('إضافة إيداع'),
                onPressed: () => _showDepositDialog(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.role == 'Admin' || widget.role == 'SuperAdmin') ...[
            Row(
              children: [
                _buildStatCard('totalOriginalDeposit', _depositsOriginalTotal),
                const SizedBox(width: 8),
                _buildStatCard('totalDeposit', _depositsTotal),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: loadingDeposits
                ? const Center(child: CircularProgressIndicator())
                : _buildDataTable(
                    controller: depositTableController,
                    columns: const [
                      'العميل',
                      'القيمة الأصلية',
                      'المبلغ المتبقي',
                      'تاريخ الدفع',
                      'ملاحظات',
                      'خيارات',
                    ],
                    rows: filteredDeposits.map((d) {
                      final val = (d['value'] as num? ?? 0).toDouble();
                      final amt = (d['amount'] as num? ?? 0).toDouble();
                      return DataRow(cells: [
                        DataCell(Text(d['client_name'] ?? '')),
                        DataCell(Text(val.toStringAsFixed(2))),
                        DataCell(Text(amt.toStringAsFixed(2))),
                        DataCell(Text(d['payment_date'] ?? '')),
                        DataCell(Text(d['notes'] ?? '')),
                        DataCell(Row(children: [
                          IconButton(
                            icon: Icon(
                              Icons.edit,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            onPressed: () => _showDepositDialog(editing: d),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteDeposit(d),
                          ),
                        ])),
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
            decoration: InputDecoration(labelText: hint, prefixIcon: const Icon(Icons.search)),
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
            columns: columns.map((c) => DataColumn(label: Text(c))).toList(),
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
                style: TextStyle(color: cfg['darkColor'] as Color, fontWeight: FontWeight.bold),
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
    final currentDebt = (supplier['debt'] as num? ?? 0).toDouble();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('سداد دفعة إلى المورد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${supplier['full_name']}${(supplier['company_name'] ?? '').isNotEmpty ? ' (${supplier['company_name']})' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text('الدين الحالي: ${currentDebt.toStringAsFixed(2)} دج'),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.attach_money),
                  label: const Text('تسديد الكل'),
                  onPressed: currentDebt > 0
                      ? () => setDialog(() => amountController.text = currentDebt.toStringAsFixed(2))
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'المبلغ (الحد الأقصى: ${currentDebt.toStringAsFixed(2)})',
                  prefixIcon: const Icon(Icons.payments),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final amt = double.tryParse(value) ?? 0;
                  if (amt >= currentDebt) {
                    setDialog(() => amountController.text = currentDebt.toStringAsFixed(2));
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: submitting ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text('سداد'),
              onPressed: submitting
                  ? null
                  : () async {
                      final amt = double.tryParse(amountController.text) ?? 0;
                      if (amt <= 0) {
                        _showSnackBar('يجب إدخال مبلغ صحيح', color: Colors.red);
                        return;
                      }
                      setDialog(() => submitting = true);
                      try {
                        final resp = await http.post(
                          Uri.parse('$baseUrl/debts/suppliers/${supplier['id']}/pay'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'amount': amt}),
                        );
                        if (resp.statusCode == 200) {
                          _showSnackBar('تم تسجيل دفعة بنجاح', color: Colors.green);
                          Navigator.pop(context);
                          await _fetchSupplierDebts();
                        } else {
                          final err = jsonDecode(resp.body);
                          throw err['error'] ?? 'خطأ غير معروف';
                        }
                      } catch (e) {
                        _showSnackBar(e.toString(), color: Colors.red);
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
    bool useDeposit = false;
    bool submitting = false;
    final currentDebt = (client['debt'] as num? ?? 0).toDouble();
    final currentDeposit = clientDepositTotals[client['id']] ?? 0.0;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('سداد دفعة من العميل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(client['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text('الدين الحالي: ${currentDebt.toStringAsFixed(2)} دج'),
              const SizedBox(height: 8),
              Text('الإيداع المتوفر: ${currentDeposit.toStringAsFixed(2)} دج'),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('استخدام الإيداع'),
                value: useDeposit,
                onChanged: (v) => setDialog(() => useDeposit = v),
              ),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'المبلغ (الحد الأقصى: ${useDeposit ? min(currentDeposit, currentDebt).toStringAsFixed(2) : currentDebt.toStringAsFixed(2)})',
                  prefixIcon: const Icon(Icons.payments),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final amt = double.tryParse(value) ?? 0;
                  final maxAmt = useDeposit ? min(currentDeposit, currentDebt) : currentDebt;
                  if (amt >= maxAmt) {
                    setDialog(() => amountController.text = maxAmt.toStringAsFixed(2));
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: submitting ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text('سداد'),
              onPressed: submitting
                  ? null
                  : () async {
                      final amt = double.tryParse(amountController.text) ?? 0;
                      if (amt <= 0) {
                        _showSnackBar('يجب إدخال مبلغ صحيح', color: Colors.red);
                        return;
                      }
                      setDialog(() => submitting = true);
                      try {
                        if (useDeposit) {
                          final resp2 = await http.post(
                            Uri.parse('$baseUrl/debts/clients/${client['id']}/deposit/use'),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode({'amount': amt}),
                          );
                          if (resp2.statusCode != 200) {
                            final err = jsonDecode(resp2.body);
                            throw err['error'] ?? 'فشل استخدام الإيداع';
                          }
                          await _fetchDeposits();
                        }
                        final resp = await http.post(
                          Uri.parse('$baseUrl/debts/clients/${client['id']}/pay'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'amount': amt}),
                        );
                        if (resp.statusCode == 200) {
                          _showSnackBar('تم تسجيل دفعة بنجاح', color: Colors.green);
                          Navigator.pop(context);
                          await _fetchClientDebts();
                        } else {
                          final err = jsonDecode(resp.body);
                          throw err['error'] ?? 'خطأ غير معروف';
                        }
                      } catch (e) {
                        _showSnackBar(e.toString(), color: Colors.red);
                      }
                      setDialog(() => submitting = false);
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDepositDialog({Map<String, dynamic>? editing}) async {
    final isEdit = editing != null;
    int? selectedClientId = editing?['client_id'] as int?;
    final amountController = TextEditingController(
        text: editing != null ? (editing['amount'] as num).toString() : '');
    final notesController = TextEditingController(text: editing?['notes'] ?? '');
    final _formKey = GlobalKey<FormState>();
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(isEdit ? 'تعديل الإيداع' : 'إضافة إيداع جديد'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: selectedClientId,
                  decoration: const InputDecoration(labelText: 'العميل'),
                  items: clientDebts.map((c) {
                    return DropdownMenuItem<int>(
                      value: c['id'] as int,
                      child: Text(c['full_name'] as String),
                    );
                  }).toList(),
                  onChanged: (v) => setDialog(() => selectedClientId = v),
                  validator: (v) =>
                      v == null ? 'الرجاء اختيار العميل' : null,
                ),
                if (isEdit) ...[
                  const SizedBox(height: 8),
                  Text(
                    'القيمة الأصلية: ${(editing!['value'] as num? ?? 0).toDouble().toStringAsFixed(2)} دج',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'المبلغ المتبقي'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'الرجاء إدخال المبلغ';
                    }
                    final parsed = double.tryParse(v);
                    if (parsed == null || parsed <= 0) {
                      return 'المبلغ غير صالح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: submitting ? null : () => Navigator.pop(context),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;

                      final amt = double.parse(amountController.text);
                      setDialog(() => submitting = true);
                      try {
                        final url = isEdit
                            ? Uri.parse('$baseUrl/debts/clients/deposits/${editing!['id']}')
                            : Uri.parse('$baseUrl/debts/clients/deposits');

                        final resp = await (isEdit
                            ? http.put(url,
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'client_id': selectedClientId,
                                  'amount': amt,
                                  'notes': notesController.text,
                                }))
                            : http.post(url,
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'client_id': selectedClientId,
                                  'amount': amt,
                                  'notes': notesController.text,
                                })));

                        if (resp.statusCode == 200) {
                          _showSnackBar(isEdit ? 'تم التحديث بنجاح' : 'تمت الإضافة بنجاح',
                              color: Colors.green);
                          Navigator.pop(context);
                          await _fetchDeposits();
                        } else {
                          final err = jsonDecode(resp.body);
                          throw err['error'] ?? 'فشل العملية';
                        }
                      } catch (e) {
                        _showSnackBar(e.toString(), color: Colors.red);
                      }
                      setDialog(() => submitting = false);
                    },
              child: Text(isEdit ? 'حفظ' : 'إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDeposit(Map<String, dynamic> d) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('تأكيد الحذف'),
            content: const Text('هل تريد حذف هذا الإيداع؟'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    try {
      final resp = await http.delete(Uri.parse('$baseUrl/debts/clients/deposits/${d['id']}'));
      if (resp.statusCode == 200) {
        _showSnackBar('تم الحذف', color: Colors.green);
        await _fetchDeposits();
      } else {
        throw 'فشل الحذف';
      }
    } catch (e) {
      _showSnackBar(e.toString(), color: Colors.red);
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    throw FormatException('Cannot convert ${v.runtimeType} to double');
  }
}