import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../main.dart';

class EmbroideryReturnsSection extends StatefulWidget {
  const EmbroideryReturnsSection({super.key});

  @override
  State<EmbroideryReturnsSection> createState() => _EmbroideryReturnsSectionState();
}

class _EmbroideryReturnsSectionState extends State<EmbroideryReturnsSection> {
  // Data
  List<dynamic> allReturns = [];
  List<dynamic> allFactures = [];
  List<dynamic> allMaterials = [];

  // Loading state
  bool isLoading = false;

  // Filters
  List<int> _yearOptions = [];
  List<String> _monthOptions = [];
  int selectedYear = DateTime.now().year;
  String? selectedMonth;

  // API base URL
String get baseUrl => '${globalServerUri.toString()}';

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  Future<void> _fetchAllData() async {
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _fetchReturns(),
        _fetchFactures(),
        _fetchMaterials(),
      ]);
    } catch (e) {
      _showSnackBar('خطأ في تحميل البيانات: $e', color: Colors.red);
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchReturns() async {
    final response = await http.get(Uri.parse('${baseUrl}/embrodry/returns/'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      setState(() {
        allReturns = data;
        _buildYearMonthFilters();
      });
    } else {
      throw Exception('Failed to load returns');
    }
  }

  Future<void> _fetchFactures() async {
    final response = await http.get(Uri.parse('http://localhost:8888/embrodry/sales/factures'));
    if (response.statusCode == 200) {
      setState(() {
        allFactures = jsonDecode(response.body) as List;
      });
    } else {
      throw Exception('Failed to load factures');
    }
  }

  Future<void> _fetchMaterials() async {
    List<dynamic> materials = [];
    final typesRes = await http.get(Uri.parse('${baseUrl}/embrodry/warehouse/material-types'));
    if (typesRes.statusCode == 200) {
      final types = jsonDecode(typesRes.body) as List;
      for (final type in types) {
        final typeId = type['id'];
        final matsRes = await http.get(
          Uri.parse('${baseUrl}/embrodry/warehouse/materials?type_id=$typeId'),
        );
        if (matsRes.statusCode == 200) {
          final matsJson = jsonDecode(matsRes.body);
          for (final mat in matsJson['materials']) {
            mat['type_name'] = type['name'];
          }
          materials.addAll(matsJson['materials'] as List);
        }
      }
      setState(() {
        allMaterials = materials;
      });
    } else {
      throw Exception('Failed to load material types');
    }
  }

  void _showSnackBar(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _buildYearMonthFilters() {
    final years = allReturns
        .map((r) {
          final d = (r['return_date'] ?? '').toString();
          return d.length >= 4
              ? int.tryParse(d.substring(0, 4)) ?? DateTime.now().year
              : DateTime.now().year;
        })
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    _yearOptions = years.isEmpty ? [DateTime.now().year] : years;
    if (!_yearOptions.contains(selectedYear)) {
      selectedYear = _yearOptions.first;
    }
    _monthOptions = allReturns
        .where((r) => (r['return_date'] ?? '').toString().startsWith('$selectedYear-'))
        .map((r) => r['return_date'].toString().substring(5, 7))
        .toSet()
        .toList()
      ..sort();
    final nowMon = DateTime.now().month.toString().padLeft(2, '0');
    selectedMonth = (selectedYear == DateTime.now().year && _monthOptions.contains(nowMon))
        ? nowMon
        : null;
  }

  List<dynamic> get filteredReturns {
    return allReturns.where((r) {
      final d = (r['return_date'] ?? '').toString();
      if (!d.startsWith('$selectedYear-')) return false;
      if (selectedMonth == null) return true;
      return d.substring(5, 7) == selectedMonth;
    }).toList();
  }

  Future<void> _showAddReturnDialog() async {
    int? selectedFactureId;
    int? selectedModelId;
    int quantity = 1;
    bool allLoss = false;
    String notes = '';
    List<Map<String, dynamic>> repairMaterials = [];

    final quantityController = TextEditingController(text: '1');
    final notesController = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final perPieceCost = repairMaterials.fold<double>(0.0, (s, m) => s + _toDouble(m['cost']));
          final totalRepairCost = perPieceCost * quantity;

          return AlertDialog(
            title: const Text('إضافة مرتجع تطريز'),
            content: SizedBox(
              width: 500,
              height: 600,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Return info
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('معلومات المرتجع',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              decoration: const InputDecoration(labelText: 'اختر الفاتورة'),
                              value: selectedFactureId,
                              items: allFactures.map((facture) {
                                return DropdownMenuItem<int>(
                                  value: facture['id'] as int,
                                  child: Text('فاتورة رقم ${facture['id']} - ${facture['client_name']}'),
                                );
                              }).toList(),
                              onChanged: (v) => setDialogState(() {
                                selectedFactureId = v;
                                selectedModelId = null;
                              }),
                            ),
                            if (selectedFactureId != null) ...[
                              const SizedBox(height: 12),
                              FutureBuilder<List<dynamic>>(
                                future: _getFactureModels(selectedFactureId!),
                                builder: (context, snap) {
                                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                                  if (snap.data!.isEmpty) {
                                    return const Text('لا توجد موديلات متاحة');
                                  }
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      DropdownButtonFormField<int>(
                                        decoration: const InputDecoration(labelText: 'اختر الموديل'),
                                        value: selectedModelId,
                                        items: snap.data!
                                            .where((model) => model['available_quantity'] > 0)
                                            .map((model) {
                                          return DropdownMenuItem<int>(
                                            value: model['model_id'] as int,
                                            child: Text('${model['model_name']} - الكمية المتاحة: ${model['available_quantity']}'),
                                          );
                                        }).toList(),
                                        onChanged: (v) => setDialogState(() {
                                          selectedModelId = v;
                                          quantity = 1;
                                          quantityController.text = '1';
                                        }),
                                      ),
                                      if (selectedModelId != null) ...[
                                        const SizedBox(height: 12),
                                        DropdownButtonFormField<int>(
                                          decoration: const InputDecoration(labelText: 'الكمية المرتجعة'),
                                          value: quantity,
                                          items: List.generate(
                                            snap.data!
                                                .firstWhere((m) => m['model_id'] == selectedModelId)['available_quantity'] as int,
                                            (index) => DropdownMenuItem(
                                              value: index + 1,
                                              child: Text('${index + 1}'),
                                            ),
                                          ),
                                          onChanged: (value) {
                                            setDialogState(() {
                                              quantity = value!;
                                            });
                                          },
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextField(
                              controller: notesController,
                              decoration: const InputDecoration(labelText: 'ملاحظات'),
                              maxLines: 2,
                              onChanged: (v) => notes = v,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Loss vs Repair
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('حالة القطعة المرتجعة',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 12),
                            RadioListTile<bool>(
                              title: const Text('كلها خسارة'),
                              subtitle: const Text('ستسجل كخسارة كاملة ولن تضاف للمخزون'),
                              value: true,
                              groupValue: allLoss,
                              onChanged: (v) => setDialogState(() {
                                allLoss = v!;
                                repairMaterials.clear();
                              }),
                            ),
                            RadioListTile<bool>(
                              title: const Text('تحتاج إصلاح'),
                              subtitle: const Text('سيتم خصم مواد الإصلاح ويمكن إضافتها للمخزون بعد الإصلاح'),
                              value: false,
                              groupValue: allLoss,
                              onChanged: (v) => setDialogState(() => allLoss = v!),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (!allLoss) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('مواد الإصلاح المطلوبة',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('إضافة مادة'),
                                    onPressed: () => _showAddRepairMaterialDialog(repairMaterials, setDialogState),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (repairMaterials.isEmpty)
                                const Text('لم يتم إضافة مواد إصلاح بعد', style: TextStyle(color: Colors.grey))
                              else
                                ...repairMaterials.asMap().entries.map((entry) {
                                  int idx = entry.key;
                                  final mat = entry.value;
                                  final info = allMaterials.firstWhere(
                                    (m) => m['id'] == mat['material_id'],
                                    orElse: () => {'code': 'غير معروف', 'name': 'غير معروف'},
                                  );
                                  return ListTile(
                                    title: Text('${info['code']} - ${info['name']}'),
                                    subtitle: Text('الكمية: ${mat['quantity']} - التكلفة: ${_toDouble(mat['cost']).toStringAsFixed(2)} دج'),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => setDialogState(() => repairMaterials.removeAt(idx)),
                                    ),
                                  );
                                }).toList(),
                              if (repairMaterials.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'إجمالي تكلفة الإصلاح: ${totalRepairCost.toStringAsFixed(2)} دج',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: (selectedFactureId != null && selectedModelId != null && quantity > 0)
                    ? () async {
                        final payload = {
                          'facture_id': selectedFactureId,
                          'model_id': selectedModelId,
                          'quantity': quantity,
                          'repair_materials': allLoss ? [] : repairMaterials,
                          'repair_cost': allLoss ? 0.0 : (repairMaterials.isEmpty ? 0.0 : totalRepairCost),
                          'notes': notes,
                          'all_loss':         allLoss,    // ← NEW

                        };

                        try {
                          final resp = await http.post(
                            Uri.parse('${baseUrl}/embrodry/returns/'),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode(payload),
                          );
                          if (resp.statusCode == 201) {
                            Navigator.pop(context);
                            _showSnackBar('تم إضافة المرتجع بنجاح!', color: Colors.green);
                            await _fetchReturns();
                          } else {
                            final err = jsonDecode(resp.body);
                            _showSnackBar('فشل إضافة المرتجع: ${err['error'] ?? 'خطأ غير معروف'}');
                          }
                        } catch (e) {
                          _showSnackBar('خطأ في الاتصال: $e');
                        }
                      }
                    : null,
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<List<dynamic>> _getFactureModels(int factureId) async {
    final response = await http.get(
      Uri.parse('${baseUrl}/embrodry/returns/${factureId}'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['items'] as List;
    }
    return [];
  }

  void _showAddRepairMaterialDialog(
    List<Map<String, dynamic>> repairMaterials,
    void Function(void Function()) setDialogState,
  ) {
    int? selectedMaterialId;
    double quantity = 1.0;
    double unitPrice = 0.0;
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('إضافة مادة إصلاح'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'اختر المادة'),
                value: selectedMaterialId,
                items: allMaterials
                    .where((m) => !repairMaterials.any((rm) => rm['material_id'] == m['id']))
                    .map((m) {
                  return DropdownMenuItem<int>(
                    value: m['id'] as int,
                    child: Text('${m['code']} - ${m['type_name']}'),
                  );
                }).toList(),
                onChanged: (v) => setState(() {
                  selectedMaterialId = v;
                  if (v != null) {
                    final mat = allMaterials.firstWhere((m) => m['id'] == v);
                    unitPrice = _toDouble(mat['last_unit_price'] ?? mat['unit_price'] ?? mat['price'] ?? 0);
                    priceCtrl.text = unitPrice.toStringAsFixed(2);
                  }
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(labelText: 'الكمية'),
                keyboardType: TextInputType.number,
                onChanged: (v) => quantity = double.tryParse(v) ?? 1.0,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'التكلفة للقطعة (تلقائي)'),
                readOnly: true,
                enabled: false,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: (selectedMaterialId != null && quantity > 0)
                  ? () {
                      final cost = unitPrice * quantity;
                      setDialogState(() {
                        repairMaterials.add({
                          'material_id': selectedMaterialId,
                          'quantity': quantity,
                          'cost': cost,
                        });
                      });
                      Navigator.pop(context);
                    }
                  : null,
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteReturn(int returnId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا المرتجع؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final resp = await http.delete(Uri.parse('${baseUrl}/embrodry/returns/${returnId}'));
        if (resp.statusCode == 200) {
          _showSnackBar('تم حذف المرتجع بنجاح', color: Colors.green);
          await _fetchReturns();
        } else {
          final err = jsonDecode(resp.body);
          _showSnackBar('فشل حذف المرتجع: ${err['error'] ?? 'خطأ غير معروف'}');
        }
      } catch (e) {
        _showSnackBar('خطأ في الاتصال: $e');
      }
    }
  }

  Future<void> _validateReturn(int returnId) async {
    try {
      final resp = await http.patch(Uri.parse('${baseUrl}/embrodry/returns/${returnId}/validate'));
      if (resp.statusCode == 200) {
        _showSnackBar('تم تأكيد الجاهزية بنجاح!', color: Colors.green);
        await _fetchReturns();
      } else {
        final err = jsonDecode(resp.body);
        _showSnackBar('فشل تأكيد الجاهزية: ${err['error'] ?? 'خطأ غير معروف'}');
      }
    } catch (e) {
      _showSnackBar('خطأ في الاتصال: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const monthNames = [
      'جانفي','فيفري','مارس','أفريل','ماي','جوان','جويلية','أوت',
      'سبتمبر','أكتوبر','نوفمبر','ديسمبر'
    ];

    final totalQty = filteredReturns.fold<int>(0, (s, r) => s + _toInt(r['quantity']));
    final lossQty = filteredReturns.fold<int>(
      0,
      (s, r) => s + (_toDouble(r['repair_cost'] ?? 0) == 0.0 ? _toInt(r['quantity']) : 0),
    );
    final repairQty = filteredReturns.fold<int>(
      0,
      (s, r) => s + (_toDouble(r['repair_cost'] ?? 0) > 0.0 ? _toInt(r['quantity']) : 0),
    );
    final totalRepairCost = filteredReturns.fold<double>(
      0.0,
      (s, r) => s + _toDouble(r['repair_cost'] ?? 0.0),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Top controls
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _showAddReturnDialog,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('+ إضافة مرتجع جديد'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  DropdownButton<int>(
                    value: selectedYear,
                    items: _yearOptions
                        .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                        .toList(),
                    onChanged: (y) {
                      if (y != null) setState(() {
                        selectedYear = y;
                        _buildYearMonthFilters();
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String?>(
                    value: selectedMonth,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('الكل')),
                      ..._monthOptions.map((m) {
                        final idx = int.parse(m);
                        return DropdownMenuItem(value: m, child: Text(monthNames[idx - 1]));
                      }),
                    ],
                    onChanged: (m) => setState(() => selectedMonth = m),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Summary cards with updated colors
              Row(
                children: [
                  Expanded(
                    child: Card(
                      color: Colors.blue[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'إجمالي القطع المرتجعة',
                              style: TextStyle(
                                  color: Colors.blue[800],
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$totalQty',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Card(
                      color: Colors.red[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'إجمالي الخسارة',
                              style: TextStyle(
                                  color: Colors.red[800],
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$lossQty',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Card(
                      color: Colors.orange[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'تحتاج إصلاح',
                              style: TextStyle(
                                  color: Colors.orange[800],
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$repairQty',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Card(
                      color: Colors.green[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'إجمالي تكلفة الإصلاح',
                              style: TextStyle(
                                  color: Colors.green[800],
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${totalRepairCost.toStringAsFixed(2)} دج',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Data table
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredReturns.isEmpty
                        ? const Center(child: Text('لا توجد مرتجعات'))
                        : Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Scrollbar(
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  child: DataTable(
                                    headingRowColor: MaterialStateProperty.all(
                                        Theme.of(context).colorScheme.primary),
                                    headingTextStyle: const TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.bold),
                                    columns: const [
                                      DataColumn(label: Text('رقم المرتجع')),
                                      DataColumn(label: Text('رقم الفاتورة')),
                                      DataColumn(label: Text('العميل')),
                                      DataColumn(label: Text('الموديل')),
                                      DataColumn(label: Text('الكمية')),
                                      DataColumn(label: Text('الحالة')),
                                      DataColumn(label: Text('تكلفة الإصلاح')),
                                      DataColumn(label: Text('تاريخ المرتجع')),
                                      DataColumn(label: Text('ملاحظات')),
                                      // DataColumn(label: Text('الخسارة')),
                                      DataColumn(label: Text('إجراءات')),
                                    ],
                                    rows: filteredReturns.map<DataRow>((r) {
  // parse fields
  final date = (r['return_date'] ?? '').toString().split(RegExp(r'[T ]')).first;
  final isReady   = r['is_ready_to_sell'] == true;
  final isAllLoss = r['all_loss'] == true;
  // server-provided cost
  final serverCost = _toDouble(r['repair_cost'] ?? 0);
  // material list & cost sum
  final mats       = (r['repair_materials'] as List<dynamic>).cast<Map<String, dynamic>>();
  final matCostSum = mats.fold<double>(0.0, (sum, m) => sum + _toDouble(m['cost']));
  // final repairCost: use server cost if >0, else sum of material costs
  final repairCost = serverCost > 0 ? serverCost : matCostSum;
  // loss amount if total loss
  final lossAmount = isAllLoss
      ? _toDouble(r['total_price'] ?? 0) * _toInt(r['quantity'])
      : 0.0;

  return DataRow(cells: [
    DataCell(Text('${r['id']}')),
    DataCell(Text('${r['facture_id']}')),
    DataCell(Text(r['client_name'] ?? 'غير محدد')),
    DataCell(Text(r['model_name'] ?? 'غير محدد')),
    DataCell(Text('${_toInt(r['quantity'])}')),

    // Status badge
    DataCell(Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAllLoss
            ? Colors.red[100]
            : isReady
                ? Colors.green[100]
                : Colors.orange[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isAllLoss
            ? 'خسارة كاملة'
            : isReady
                ? 'جاهز للبيع'
                : 'تحتاج إصلاح',
        style: TextStyle(
          color: isAllLoss
              ? Colors.red[800]
              : isReady
                  ? Colors.green[800]
                  : Colors.orange[800],
          fontWeight: FontWeight.bold,
        ),
      ),
    )),

    // Cost or loss amount
    DataCell(Text(
      isAllLoss
          ? '${lossAmount.toStringAsFixed(2)} دج'
          : '${repairCost.toStringAsFixed(2)} دج',
    )),

    DataCell(Text(date)),

    DataCell(SizedBox(
      width: 100,
      child: Text(
        r['notes'] ?? '',
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    )),

    // Actions
    DataCell(Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.visibility, color: Colors.blue),
          tooltip: 'عرض التفاصيل',
          onPressed: () => _showReturnDetails(r),
        ),
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          tooltip: 'حذف المرتجع',
          onPressed: () => _deleteReturn(r['id']),
        ),
        if (!isAllLoss && !isReady)
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green),
            tooltip: 'تأكيد الجاهزية',
            onPressed: () => _validateReturn(r['id']),
          ),
      ],
    )),
  ]);
}).toList(),

                                  ),
                                ),
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReturnDetails(Map<String, dynamic> r) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تفاصيل المرتجع رقم ${r['id']}'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildDetailRow('رقم الفاتورة:', '${r['facture_id']}'),
              _buildDetailRow('العميل:', r['client_name'] ?? 'غير محدد'),
              _buildDetailRow('الموديل:', r['model_name'] ?? 'غير محدد'),
              _buildDetailRow('الكمية:', '${_toInt(r['quantity'])}'),
              _buildDetailRow('تاريخ المرتجع:', (r['return_date'] ?? '').toString().split(RegExp(r'[T ]')).first),
              _buildDetailRow('الحالة:', _toDouble(r['repair_cost'] ?? 0) == 0.0 ? 'خسارة كاملة' : 'تحتاج إصلاح'),
              if (_toDouble(r['repair_cost'] ?? 0) > 0.0) ...[
                const Divider(),
                const Text('مواد الإصلاح:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...(r['repair_materials'] as List).map((m) {
                  final info = allMaterials.firstWhere((mat) => mat['id'] == m['material_id'], orElse: () => {'code':'غير معروف','name':'غير معروف'});
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• ${info['code']} - كمية: ${m['quantity']} - تكلفة: ${_toDouble(m['cost']).toStringAsFixed(2)} دج'),
                  );
                }).toList(),
                _buildDetailRow('إجمالي تكلفة الإصلاح:', '${_toDouble(r['repair_cost'] ?? 0).toStringAsFixed(2)} دج'),
              ],
              if (r['notes'] != null && r['notes'].toString().isNotEmpty) ...[
                const Divider(),
                const Text('ملاحظات:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(r['notes']),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
        Expanded(child: Text(value)),
      ]),
    );
  }
}
