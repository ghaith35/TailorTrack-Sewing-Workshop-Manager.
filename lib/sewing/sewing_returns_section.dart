import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../main.dart';

class SewingReturnsSection extends StatefulWidget {
  const SewingReturnsSection({super.key});

  @override
  State<SewingReturnsSection> createState() => _SewingReturnsSectionState();
}

class _SewingReturnsSectionState extends State<SewingReturnsSection> {
  // ---------------- Data ----------------
  List<dynamic> allReturns = [];
  List<dynamic> allFactures = [];
  List<dynamic> allMaterials = [];

  // ---------------- Loading ----------------
  bool isLoading = false;

  // ---------------- Filters (Year / Month) ----------------
  List<int> _yearOptions = [];
  List<String> _monthOptions = []; // '01'...'12'
  int selectedYear = DateTime.now().year;
  String? selectedMonth; // null => ALL

  // ---------------- Scroll controllers ----------------
  final ScrollController _vCtrl = ScrollController();
  final ScrollController _hCtrl = ScrollController();

  // ---------------- API ----------------
String get baseUrl => '${globalServerUri.toString()}/returns/';

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  // ---------------- Helper converters ----------------
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

  // ---------------- Fetching ----------------
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
    final response = await http.get(Uri.parse(baseUrl));
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
    final response =
        await http.get(Uri.parse('http://localhost:8888/sales/factures'));
    if (response.statusCode == 200) {
      setState(() {
        allFactures = jsonDecode(response.body) as List;
      });
    } else {
      throw Exception('Failed to load factures');
    }
  }

  Future<void> _fetchMaterials() async {
    final response =
        await http.get(Uri.parse('http://localhost:8888/models/materials/'));
    if (response.statusCode == 200) {
      setState(() {
        allMaterials = jsonDecode(response.body) as List;
      });
    } else {
      throw Exception('Failed to load materials');
    }
  }

  // ---------------- UI Helpers ----------------
  void _showSnackBar(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _buildYearMonthFilters() {
    // Years
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

    // Months for selected year
    _monthOptions = allReturns
        .where((r) {
          final d = (r['return_date'] ?? '').toString();
          return d.startsWith('$selectedYear-');
        })
        .map((r) => r['return_date'].toString().substring(5, 7))
        .toSet()
        .toList()
      ..sort();

    final nowMon = DateTime.now().month.toString().padLeft(2, '0');
    if (selectedYear == DateTime.now().year && _monthOptions.contains(nowMon)) {
      selectedMonth = nowMon;
    } else {
      selectedMonth = null; // "ALL"
    }
  }

  List<dynamic> get filteredReturns {
    return allReturns.where((r) {
      final d = (r['return_date'] ?? '').toString();
      if (!d.startsWith('$selectedYear-')) return false;
      if (selectedMonth == null) return true;
      return d.substring(5, 7) == selectedMonth;
    }).toList();
  }

  // ---------------- Add / Delete ----------------
  Future<void> _showAddReturnDialog() async {
  int? selectedFactureId;
  int? selectedModelId;
  int quantity = 1;
  bool isReadyToSell = false;
  String notes = '';
  List<Map<String, dynamic>> repairMaterials = [];

  final notesController = TextEditingController();

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setDialogState) {
        final perPieceCost = repairMaterials.fold<double>(
            0.0, (s, m) => s + _toDouble(m['cost']));
        final totalRepairCost = perPieceCost * quantity;

        return AlertDialog(
          title: const Text('إضافة مرتجع بضاعة'),
          content: SizedBox(
            width: 500,
            height: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // معلومات المرتجع
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('معلومات المرتجع',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            decoration:
                                const InputDecoration(labelText: 'اختر الفاتورة'),
                            value: selectedFactureId,
                            items: allFactures.map((facture) {
                              return DropdownMenuItem<int>(
                                value: facture['id'] as int,
                                child: Text(
                                    'فاتورة رقم ${facture['id']} - ${facture['client_name']}'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedFactureId = value;
                                selectedModelId = null;
                                quantity = 1;
                              });
                            },
                          ),
                          if (selectedFactureId != null) ...[
                            const SizedBox(height: 12),
                            FutureBuilder<List<dynamic>>(
                              future: _getFactureModels(selectedFactureId!),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const CircularProgressIndicator();
                                }
                                if (snapshot.hasError) {
                                  return const Text('خطأ في تحميل الموديلات');
                                }
                                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                  return const Text('لا توجد موديلات متاحة');
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    DropdownButtonFormField<int>(
                                      decoration: const InputDecoration(
                                          labelText: 'اختر الموديل'),
                                      value: selectedModelId,
                                      items: snapshot.data!
                                          .where((model) =>
                                              model['available_quantity'] > 0)
                                          .map((model) {
                                        return DropdownMenuItem<int>(
                                          value: model['model_id'] as int,
                                          child: Text(
                                              '${model['model_name']} - الكمية المتاحة: ${model['available_quantity']}'),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        setDialogState(() {
                                          selectedModelId = value;
                                          quantity = 1;
                                        });
                                      },
                                    ),
                                    if (selectedModelId != null) ...[
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<int>(
                                        decoration: const InputDecoration(
                                            labelText: 'الكمية المرتجعة'),
                                        value: quantity,
                                        items: List.generate(
                                          snapshot.data!
                                              .firstWhere((m) =>
                                                  m['model_id'] ==
                                                  selectedModelId)[
                                                  'available_quantity'] as int,
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
                            decoration:
                                const InputDecoration(labelText: 'ملاحظات'),
                            maxLines: 2,
                            onChanged: (value) => notes = value,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // حالة البضاعة
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('حالة البضاعة المرتجعة',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          RadioListTile<bool>(
                            title: const Text('جاهزة للبيع مرة أخرى'),
                            subtitle: const Text('سيتم إضافتها مباشرة للمخزون'),
                            value: true,
                            groupValue: isReadyToSell,
                            onChanged: (value) {
                              setDialogState(() {
                                isReadyToSell = value!;
                                if (isReadyToSell) {
                                  repairMaterials.clear();
                                }
                              });
                            },
                          ),
                          RadioListTile<bool>(
                            title: const Text('تحتاج إصلاح'),
                            subtitle: const Text(
                                'سيتم خصم مواد الإصلاح من المخزون'),
                            value: false,
                            groupValue: isReadyToSell,
                            onChanged: (value) {
                              setDialogState(() {
                                isReadyToSell = value!;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (!isReadyToSell) ...[
                    const SizedBox(height: 16),
                    // مواد الإصلاح
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
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('إضافة مادة'),
                                  onPressed: () {
                                    _showAddRepairMaterialDialog(
                                        repairMaterials, setDialogState);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (repairMaterials.isEmpty)
                              const Text('لم يتم إضافة مواد إصلاح بعد',
                                  style: TextStyle(color: Colors.grey))
                            else
                              ...repairMaterials.asMap().entries.map((entry) {
                                int index = entry.key;
                                Map<String, dynamic> material = entry.value;
                                final materialInfo = allMaterials.firstWhere(
                                  (m) => m['id'] == material['material_id'],
                                  orElse: () =>
                                      {'code': 'غير معروف', 'name': 'غير معروف'},
                                );
                                return ListTile(
                                  title: Text(
                                      '${materialInfo['code']} - ${materialInfo['name']}'),
                                  subtitle: Text(
                                      'الكمية: ${material['quantity']} - التكلفة: ${_toDouble(material['cost']).toStringAsFixed(2)} دج'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () {
                                      setDialogState(() {
                                        repairMaterials.removeAt(index);
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                            if (repairMaterials.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  'إجمالي تكلفة الإصلاح (لكل القطع): ${totalRepairCost.toStringAsFixed(2)} دج',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green),
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
              onPressed: (selectedFactureId != null &&
                      selectedModelId != null &&
                      quantity > 0)
                  ? () async {
                      print('Selected Facture ID: $selectedFactureId');
                      print('Selected Model ID: $selectedModelId');
                      print('Return Quantity: $quantity');
                      print('Is Ready to Sell: $isReadyToSell');
                      print('Repair Materials: $repairMaterials');

                      final payload = {
                        'facture_id': selectedFactureId,
                        'model_id': selectedModelId,
                        'quantity': quantity,
                        'is_ready_to_sell': isReadyToSell,
                        'repair_materials': repairMaterials,
                        'repair_cost': totalRepairCost,
                        'notes': notes,
                      };

                      print('Payload for Return Creation: $payload');

                      try {
                        final response = await http.post(
                          Uri.parse(baseUrl),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(payload),
                        );

                        print('Response Status: ${response.statusCode}');
                        print('Response Body: ${response.body}');

                        if (response.statusCode == 201) {
                          Navigator.pop(context);
                          _showSnackBar('تم إضافة المرتجع بنجاح!',
                              color: Colors.green);
                          await _fetchReturns();
                        } else {
                          final error = jsonDecode(response.body);
                          _showSnackBar(
                              'فشل إضافة المرتجع: ${error['error'] ?? 'خطأ غير معروف'}');
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
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$factureId'), // Changed to new route
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['items'] as List;
      } else {
        _showSnackBar('فشل تحميل موديلات الفاتورة');
        return [];
      }
    } catch (e) {
      _showSnackBar('خطأ في الاتصال: $e');
      return [];
    }
  }

  void _showAddRepairMaterialDialog(
    List<Map<String, dynamic>> repairMaterials,
    void Function(void Function()) setDialogState,
  ) {
    int? selectedMaterialId;
    double quantity = 1.0;
    double unitPrice = 0.0;
    final quantityController = TextEditingController(text: '1');
    final unitPriceController = TextEditingController(text: '0');

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
                    .where((m) =>
                        !repairMaterials.any((rm) => rm['material_id'] == m['id']))
                    .map((material) {
                  return DropdownMenuItem<int>(
                    value: material['id'] as int,
                    child: Text('${material['code']} - ${material['name']}'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedMaterialId = value;
                    if (value != null) {
                      final mat = allMaterials.firstWhere((m) => m['id'] == value);
                      unitPrice = _toDouble(
                        mat['price'] ?? mat['unit_price'] ?? mat['cost'] ?? 0,
                      );
                      unitPriceController.text = unitPrice.toStringAsFixed(2);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'الكمية'),
                keyboardType: TextInputType.number,
                onChanged: (v) => quantity = double.tryParse(v) ?? 1.0,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unitPriceController,
                decoration: const InputDecoration(
                  labelText: 'التكلفة للقطعة (تلقائي)',
                ),
                readOnly: true,
                enabled: false,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: (selectedMaterialId != null && quantity > 0)
                  ? () {
                      final totalLineCost = unitPrice * quantity;
                      setDialogState(() {
                        repairMaterials.add({
                          'material_id': selectedMaterialId,
                          'quantity': quantity,
                          'cost': totalLineCost,
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
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
        final response = await http.delete(Uri.parse('$baseUrl$returnId'));
        if (response.statusCode == 200) {
          _showSnackBar('تم حذف المرتجع بنجاح', color: Colors.green);
          await _fetchReturns();
        } else {
          final error = jsonDecode(response.body);
          _showSnackBar(
              'فشل حذف المرتجع: ${error['error'] ?? 'خطأ غير معروف'}');
        }
      } catch (e) {
        _showSnackBar('خطأ في الاتصال: $e');
      }
    }
  }

  // 1) Change your method signature:
Future<void> _validateReturn(Map<String, dynamic> returnItem) async {
  try {
    final payload = {
      'is_ready_to_sell': true,
      'repair_cost': _toDouble(returnItem['repair_cost'] ?? 0.0),
      'repair_materials': returnItem['repair_materials'] ?? [],
    };

    final response = await http.patch(
      Uri.parse('$baseUrl${returnItem['id']}/validate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    print('Validate Request Payload: $payload');
    print('Validate Response Status: ${response.statusCode}');
    print('Validate Response Body: ${response.body}');

    if (response.statusCode == 200) {
      _showSnackBar('تم تأكيد الجاهزية بنجاح!', color: Colors.green);
      await _fetchReturns();
    } else {
      final error = jsonDecode(response.body);
      _showSnackBar(
        'فشل تأكيد الجاهزية: ${error['error'] ?? 'خطأ غير معروف'}',
      );
    }
  } catch (e) {
    _showSnackBar('خطأ في الاتصال: $e');
  }
}


  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    const monthNames = [
      'جانفي',
      'فيفري',
      'مارس',
      'أفريل',
      'ماي',
      'جوان',
      'جويلية',
      'أوت',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];

    final totalQty = filteredReturns.fold<int>(
        0, (s, r) => s + _toInt(r['quantity']));
    final readyQty = filteredReturns
        .where((r) => r['is_ready_to_sell'] == true)
        .fold<int>(0, (s, r) => s + _toInt(r['quantity']));
    final repairQty = filteredReturns
        .where((r) => r['is_ready_to_sell'] == false)
        .fold<int>(0, (s, r) => s + _toInt(r['quantity']));
    final totalRepairCost = filteredReturns.fold<double>(
        0.0, (s, r) => s + _toDouble(r['repair_cost'] ?? 0.0));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
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
                        .map((y) =>
                            DropdownMenuItem(value: y, child: Text('$y')))
                        .toList(),
                    onChanged: (y) {
                      if (y == null) return;
                      setState(() {
                        selectedYear = y;
                        _buildYearMonthFilters();
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String?>(
                    value: selectedMonth,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('الكل'),
                      ),
                      ..._monthOptions.map((m) {
                        final idx = int.parse(m);
                        return DropdownMenuItem<String?>(
                          value: m,
                          child: Text(monthNames[idx - 1]),
                        );
                      }),
                    ],
                    onChanged: (mon) {
                      setState(() => selectedMonth = mon);
                    },
                  ),
                ],
              ),

              const SizedBox(height: 24),

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
                      color: Colors.green[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'قطع جاهزة للبيع',
                              style: TextStyle(
                                  color: Colors.green[800],
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$readyQty',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[900],
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
                              'قطع تحتاج إصلاح',
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
                      color: Colors.red[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'إجمالي تكلفة الإصلاح',
                              style: TextStyle(
                                  color: Colors.red[800],
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${totalRepairCost.toStringAsFixed(2)} دج',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[900],
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

              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredReturns.isEmpty
                        ? const Center(child: Text('لا توجد مرتجعات'))
                        : Scrollbar(
                            controller: _vCtrl,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _vCtrl,
                              scrollDirection: Axis.vertical,
                              child: Center(
                                child: SingleChildScrollView(
                                  controller: _hCtrl,
                                  scrollDirection: Axis.horizontal,
                                  child: Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: DataTable(
                                        headingRowColor:
                                            MaterialStateProperty.all(
                                          Theme.of(context).colorScheme.primary,
                                        ),
                                        headingTextStyle: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        columns: const [
                                          DataColumn(label: Text('رقم المرتجع')),
                                          DataColumn(label: Text('رقم الفاتورة')),
                                          DataColumn(label: Text('العميل')),
                                          DataColumn(label: Text('الموديل')),
                                          DataColumn(label: Text('الكمية')),
                                          DataColumn(label: Text('الحالة')),
                                          DataColumn(
                                              label: Text('تكلفة الإصلاح')),
                                          DataColumn(
                                              label: Text('تاريخ المرتجع')),
                                          DataColumn(label: Text('ملاحظات')),
                                          DataColumn(label: Text('إجراءات')),
                                        ],
                                        rows: filteredReturns
                                            .map<DataRow>((returnItem) {
                                          final dateOnly = (returnItem[
                                                          'return_date'] ??
                                                      '')
                                                  .toString()
                                                  .split(RegExp(r'[T ]'))
                                                  .first;
                                          return DataRow(
                                            cells: [
                                              DataCell(
                                                  Text('${returnItem['id']}')),
                                              DataCell(Text(
                                                  '${returnItem['facture_id']}')),
                                              DataCell(Text(returnItem[
                                                      'client_name'] ??
                                                  'غير محدد')),
                                              DataCell(Text(returnItem[
                                                      'model_name'] ??
                                                  'غير محدد')),
                                              DataCell(Text(
                                                  '${_toInt(returnItem['quantity'])}')),
                                              DataCell(Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: returnItem[
                                                              'is_ready_to_sell']
                                                          ? Colors.green[100]
                                                          : Colors.orange[100],
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  returnItem[
                                                              'is_ready_to_sell']
                                                      ? 'جاهز للبيع'
                                                      : 'يحتاج إصلاح',
                                                  style: TextStyle(
                                                    color: returnItem[
                                                            'is_ready_to_sell']
                                                        ? Colors.green[800]
                                                        : Colors.orange[800],
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              )),
                                              DataCell(Text(
                                                  '${_toDouble(returnItem['repair_cost'] ?? 0.0).toStringAsFixed(2)} دج')),
                                              DataCell(Text(dateOnly)),
                                              DataCell(SizedBox(
                                                width: 100,
                                                child: Text(
                                                  returnItem['notes'] ?? '',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 2,
                                                ),
                                              )),
                                              DataCell(Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.visibility,
                                                        color: Colors.blue),
                                                    tooltip: 'عرض التفاصيل',
                                                    onPressed: () =>
                                                        _showReturnDetails(
                                                            returnItem),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete,
                                                        color: Colors.red),
                                                    tooltip: 'حذف المرتجع',
                                                    onPressed: () =>
                                                        _deleteReturn(
                                                            returnItem['id']),
                                                  ),
                                                  if (!returnItem[
                                                      'is_ready_to_sell'])
                                                    IconButton(
  icon: const Icon(Icons.check, color: Colors.blue),
  tooltip: 'تأكيد الجاهزية',
  onPressed: () async {
    await _validateReturn(returnItem);
    await _fetchReturns();
  },
),
                                                ],
                                              )),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
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

  void _showReturnDetails(Map<String, dynamic> returnItem) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تفاصيل المرتجع رقم ${returnItem['id']}'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('رقم الفاتورة:', '${returnItem['facture_id']}'),
                _buildDetailRow('العميل:', returnItem['client_name'] ?? 'غير محدد'),
                _buildDetailRow('الموديل:', returnItem['model_name'] ?? 'غير محدد'),
                _buildDetailRow('الكمية:', '${_toInt(returnItem['quantity'])}'),
                _buildDetailRow(
                    'تاريخ المرتجع:',
                    (returnItem['return_date'] ?? '')
                        .toString()
                        .split(RegExp(r'[T ]'))
                        .first),
                _buildDetailRow(
                    'الحالة:',
                    returnItem['is_ready_to_sell'] ? 'جاهز للبيع' : 'يحتاج إصلاح'),
                if (!(returnItem['is_ready_to_sell'] ?? true)) ...[
                  const Divider(),
                  const Text('مواد الإصلاح:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (returnItem['repair_materials'] != null)
                    ...((returnItem['repair_materials'] as List).map((material) {
                      final materialInfo = allMaterials.firstWhere(
                        (m) => m['id'] == material['material_id'],
                        orElse: () =>
                            {'code': 'غير معروف', 'name': 'غير معروف'},
                      );
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                            '• ${materialInfo['code']} - كمية: ${material['quantity']} - تكلفة: ${_toDouble(material['cost']).toStringAsFixed(2)} دج'),
                      );
                    }).toList()),
                  _buildDetailRow(
                      'إجمالي تكلفة الإصلاح:',
                      '${_toDouble(returnItem['repair_cost'] ?? 0.0).toStringAsFixed(2)} دج'),
                ],
                if (returnItem['notes'] != null &&
                    returnItem['notes'].toString().isNotEmpty) ...[
                  const Divider(),
                  const Text('ملاحظات:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(returnItem['notes']),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}