import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// =============================================================
/// Shared / Common Widgets & Helpers
/// =============================================================
class TabHeader extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;
  const TabHeader({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.grey[100], // Same background as main area
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(tabs.length, (i) {
          final sel = selected == i;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ChoiceChip(
              label: Text(tabs[i]),
              selected: sel,
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                color: sel ? Colors.white : null,
                fontWeight: FontWeight.bold,
              ),
              onSelected: (_) => onChanged(i),
            ),
          );
        }),
      ),
    );
  }
}

class SidePanel extends StatelessWidget {
  final String title;
  final Widget? topFilters;
  final Widget list;
  const SidePanel({
    super.key,
    required this.title,
    this.topFilters,
    required this.list,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      color: Colors.grey[100],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 16),
                if (topFilters != null) topFilters!,
              ],
            ),
          ),
          Expanded(child: list),
        ],
      ),
    );
  }
}

Widget summaryCard(Map<String, Map<String, dynamic>> labels, String key, String value) {
  final cfg = labels[key]!;
  return Expanded(
    child: Card(
      color: cfg['lightColor'] as Color,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: cfg['darkerColor'] as Color,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget costItem(String label, dynamic value, Color color, {bool isTotal = false}) {
  final numVal = (value ?? 0.0) is num ? (value ?? 0.0) as num : 0.0;
  return Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 14 : 12,
            color: color,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          '${numVal.toStringAsFixed(2)} دج',
          style: TextStyle(
            fontSize: isTotal ? 18 : 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    ),
  );
}

String fmtDate(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '';
  try {
    final date = DateTime.parse(dateStr);
    return "${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}";
  } catch (e) {
    return dateStr.split('T').first;
  }
}

/// =============================================================
/// Main Section
/// =============================================================
class SewingSalesSection extends StatefulWidget {
  const SewingSalesSection({super.key});

  @override
  State<SewingSalesSection> createState() => _SewingSalesSectionState();
}

class _SewingSalesSectionState extends State<SewingSalesSection> {
  int selectedTab = 2; // 0: Models, 1: Clients, 2: Factures

  final String baseUrl = 'http://localhost:8888/sales';

  List<dynamic> allModels = [];
  List<dynamic> allClients = [];
  List<dynamic> allFactures = [];
  List<dynamic> allSeasons = [];
  Map<String, dynamic>? facturesSummary;

  int? selectedFactureId;
  int? selectedClientId;
  int? selectedModelId;
  int? selectedSeasonId; // null = ALL
  bool isLoading = false;

  // Type labels
  final Map<String, Map<String, dynamic>> typeLabels = {
    'factures': {
      'label': 'اجمالي عدد الفواتير',
      'lightColor': Colors.blue[50],
      'darkColor': Colors.blue[800],
      'darkerColor': Colors.blue[900],
    },
    'income': {
      'label': 'اجمالي المدخول',
      'lightColor': Colors.green[50],
      'darkColor': Colors.green[800],
      'darkerColor': Colors.green[900],
    },
    'remaining': {
      'label': 'اجمالي المتبقي',
      'lightColor': Colors.orange[50],
      'darkColor': Colors.orange[800],
      'darkerColor': Colors.orange[900],
    },
    'profit': {
      'label': 'اجمالي الربح',
      'lightColor': Colors.purple[50],
      'darkColor': Colors.purple[800],
      'darkerColor': Colors.purple[900],
    },
  };

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  void _showSnackBar(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _fetchAllData() async {
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _fetchSeasons(),
        _fetchClients(),
        _fetchModels(),
        _fetchFactures(),
        _fetchFacturesSummary(),
      ]);
    } catch (e) {
      _showSnackBar('خطأ في تحميل البيانات: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchSeasons() async {
    try {
      final resp = await http.get(Uri.parse('$baseUrl/seasons'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => allSeasons = data is List ? data : []);
      }
    } catch (_) {
      allSeasons = [];
    }
  }

  Future<void> _fetchFacturesSummary() async {
    try {
      final resp = await http.get(Uri.parse('$baseUrl/factures/summary'));
      if (resp.statusCode == 200) {
        setState(() => facturesSummary = jsonDecode(resp.body));
      }
    } catch (_) {
      facturesSummary = null;
    }
  }

  Future<void> _fetchFactures() async {
    String url = '$baseUrl/factures';
    if (selectedSeasonId != null && allSeasons.isNotEmpty) {
      url = '$baseUrl/factures/by_season/$selectedSeasonId';
    }
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as List;
      setState(() {
        allFactures = data;
        if (allFactures.isNotEmpty && selectedFactureId == null) {
          selectedFactureId = allFactures.first['id'] as int;
        } else if (selectedFactureId != null &&
            !allFactures.any((f) => f['id'] == selectedFactureId)) {
          selectedFactureId =
              allFactures.isNotEmpty ? allFactures.first['id'] as int : null;
        }
      });
    } else {
      throw Exception(
          'Failed to load factures: ${resp.statusCode} - ${resp.body}');
    }
  }

  Future<void> _fetchClients() async {
    String url = '$baseUrl/clients';
    if (selectedSeasonId != null && allSeasons.isNotEmpty) {
      url = '$baseUrl/clients/by_season/$selectedSeasonId';
    }
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      setState(() => allClients = data is List ? data : []);
    } else {
      throw Exception('Failed to load clients: ${resp.statusCode}');
    }
  }

  Future<void> _fetchModels() async {
    String url = '$baseUrl/models';
    if (selectedSeasonId != null && allSeasons.isNotEmpty) {
      url = '$baseUrl/models/by_season/$selectedSeasonId';
    }
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      setState(() => allModels = data is List ? data : []);
    } else {
      throw Exception('Failed to load models: ${resp.statusCode}');
    }
  }

  dynamic get selectedFacture {
    if (selectedFactureId == null || allFactures.isEmpty) return null;
    return allFactures
        .firstWhere((f) => f['id'] == selectedFactureId, orElse: () => null);
  }

  Future<Map<String, dynamic>> _loadFactureDetail(int id) async {
    final resp = await http.get(Uri.parse('$baseUrl/factures/$id'));
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body);
    } else {
      throw Exception(
          'Failed to load facture details: ${resp.statusCode} - ${resp.body}');
    }
  }

  Future<void> _onSeasonChanged(int? val) async {
    setState(() => selectedSeasonId = val);
    await Future.wait([
      _fetchFactures(),
      _fetchClients(),
      _fetchModels(),
      _fetchFacturesSummary(),
    ]);
  }

  Future<void> _addNewFacture() async {
  int? clientId;
  String payType = 'debt';
  double paidOnCreation = 0.0;
  final amountCtrl = TextEditingController();

  final List<Map<String, dynamic>> items = [];
  DateTime factureDate = DateTime.now();

  double getTotal() => items.fold<double>(
        0.0,
        (s, it) => s + (it['quantity'] as int) * (it['unit_price'] as double),
      );

  double getTotalProfit() => items.fold<double>(
        0.0,
        (s, it) =>
            s +
            (it['quantity'] as int) *
                ((it['unit_price'] as double) - (it['cost_price'] as double)),
      );

  Future<void> _addLineItem(StateSetter outerSetState) async {
  int? modelId;
  final qtyCtrl = TextEditingController();
  final priceCtrl = TextEditingController();

  // Filter: only products that have stock > 0
  final List<dynamic> inStockModels = allModels.where((m) {
    final q = m['available_quantity'];
    final qty = q is num ? q.toInt() : int.tryParse(q.toString()) ?? 0;
    return qty > 0;
  }).toList();

  if (inStockModels.isEmpty) {
    _showSnackBar('لا توجد منتجات متاحة في المخزن حالياً', color: Colors.orange);
    return;
  }

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, st) => AlertDialog(
        title: const Text('إضافة منتج للفاتورة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'اختر المنتج'),
                value: modelId,
                items: inStockModels.map((m) {
                  return DropdownMenuItem<int>(
                    value: m['id'] as int,
                    child: Text(
                      '${m['name']} (متاح: ${m['available_quantity']}, تكلفة: ${m['cost_price']})',
                    ),
                  );
                }).toList(),
                onChanged: (v) => st(() => modelId = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(labelText: 'الكمية'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'سعر البيع'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final q = int.tryParse(qtyCtrl.text) ?? 0;
              final p = double.tryParse(priceCtrl.text) ?? 0.0;

              if (modelId == null) {
                _showSnackBar('يرجى اختيار المنتج');
                return;
              }
              if (q <= 0) {
                _showSnackBar('يرجى إدخال كمية صحيحة');
                return;
              }
              if (p <= 0) {
                _showSnackBar('يرجى إدخال سعر صحيح');
                return;
              }

              final prod = inStockModels.firstWhere((m) => m['id'] == modelId);
              final availableQty = prod['available_quantity'] is int
                  ? prod['available_quantity'] as int
                  : int.tryParse(prod['available_quantity'].toString()) ?? 0;

              if (q > availableQty) {
                _showSnackBar(
                    'الكمية أكبر من الموجود في المخزن (متاح: $availableQty)');
                return;
              }

              // If the item already exists, update it; otherwise add new
              final existingIndex =
                  items.indexWhere((item) => item['model_id'] == modelId);
              if (existingIndex != -1) {
                items[existingIndex]['quantity'] = q;
                items[existingIndex]['unit_price'] = p;
              } else {
                items.add({
                  'model_id': modelId,
                  'model_name': prod['name'],
                  'quantity': q,
                  'unit_price': p,
                  'available_quantity': availableQty,
                  'cost_price': prod['cost_price'],
                });
              }

              // Refresh the parent dialog totals & list
              outerSetState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    ),
  );
}


  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, dialogSetState) => AlertDialog(
        title: const Text('إضافة فاتورة جديدة'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Date picker (MAIN dialog)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Text(
                          'تاريخ الفاتورة: ${factureDate.toLocal().toString().split(' ')[0]}',
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: factureDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              dialogSetState(() => factureDate = picked);
                            }
                          },
                          child: const Text('تغيير التاريخ'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'اختر العميل'),
                  value: clientId,
                  items: allClients.map((c) {
                    return DropdownMenuItem(
                      value: c['id'] as int,
                      child: Text(c['full_name']),
                    );
                  }).toList(),
                  onChanged: (v) => dialogSetState(() => clientId = v),
                ),

                const SizedBox(height: 16),

                if (items.isNotEmpty)
                  Card(
                    color: Colors.grey[50],
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('المنتجات المضافة',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'الإجمالي: ${getTotal().toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                  Text(
                                    'إجمالي الربح: ${getTotalProfit().toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(),
                          ...items.asMap().entries.map((e) {
                            final idx = e.key;
                            final it = e.value;
                            final profit = (it['unit_price'] - it['cost_price']) *
                                it['quantity'];
                            return ListTile(
                              title: Text(it['model_name']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'المتاح: ${it['available_quantity']}, التكلفة: ${it['cost_price']}'),
                                  Text(
                                      'الكمية: ${it['quantity']} × ${it['unit_price']} = ${(it['quantity'] * it['unit_price']).toStringAsFixed(2)}'),
                                  Text('الربح: ${profit.toStringAsFixed(2)} دج',
                                      style: TextStyle(color: Colors.green[700])),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () =>
                                    dialogSetState(() => items.removeAt(idx)),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    Text('عدد المنتجات: ${items.length}'),
                    const Spacer(),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة منتج'),
                      onPressed: () => _addLineItem(dialogSetState),
                    ),
                  ],
                ),

                const Divider(),

                Text(
                  'الإجمالي: ${getTotal().toStringAsFixed(2)} دج',
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                ListTile(
                  title: const Text('بيع بالدين'),
                  leading: Radio<String>(
                    value: 'debt',
                    groupValue: payType,
                    onChanged: (v) => dialogSetState(() => payType = v!),
                  ),
                ),
                ListTile(
                  title: const Text('بيع نقدي'),
                  leading: Radio<String>(
                    value: 'cash',
                    groupValue: payType,
                    onChanged: (v) => dialogSetState(() => payType = v!),
                  ),
                ),

                if (payType == 'cash')
                  TextField(
                    controller: amountCtrl,
                    decoration: InputDecoration(
                      labelText:
                          'دفعة أولى (الحد الأقصى: ${getTotal().toStringAsFixed(2)})',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      final amount = double.tryParse(v) ?? 0.0;
                      final total = getTotal();
                      if (amount > total) {
                        amountCtrl.text = total.toStringAsFixed(2);
                        paidOnCreation = total;
                      } else {
                        paidOnCreation = amount;
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (clientId == null) {
                _showSnackBar('يرجى اختيار العميل');
                return;
              }
              if (items.isEmpty) {
                _showSnackBar('يرجى إضافة منتج واحد على الأقل');
                return;
              }
              final total = getTotal();
              if (total <= 0) {
                _showSnackBar('إجمالي الفاتورة يجب أن يكون أكبر من صفر');
                return;
              }
              if (payType == 'cash' && paidOnCreation > total) {
                _showSnackBar(
                    'الدفعة الأولى لا يمكن أن تكون أكبر من إجمالي الفاتورة');
                return;
              }

              final payload = {
                'client_id': clientId,
                'total_amount': total,
                'amount_paid_on_creation':
                    payType == 'cash' ? paidOnCreation : 0.0,
                'facture_date':
                    factureDate.toIso8601String().split('T')[0], // YYYY-MM-DD
                'items': items
                    .map((it) => {
                          'model_id': it['model_id'],
                          'color': null,
                          'quantity': it['quantity'],
                          'unit_price': it['unit_price'],
                        })
                    .toList(),
              };

              try {
                final resp = await http.post(
                  Uri.parse('$baseUrl/factures'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(payload),
                );
                if (resp.statusCode == 201) {
                  _showSnackBar('تم إضافة الفاتورة بنجاح!', color: Colors.green);
                  Navigator.pop(ctx);
                  await _fetchFactures();
                  await _fetchFacturesSummary();
                } else {
                  final error = jsonDecode(resp.body);
                  _showSnackBar(
                      'فشل إضافة الفاتورة: ${error['error'] ?? 'خطأ غير معروف'}');
                }
              } catch (e) {
                _showSnackBar('خطأ في الاتصال: $e');
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}


  Future<void> _deleteFacture(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الفاتورة'),
        content: Text('هل أنت متأكد من حذف الفاتورة رقم "${f['id']}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        final resp =
            await http.delete(Uri.parse('$baseUrl/factures/${f['id']}'));
        if (resp.statusCode == 200) {
          _showSnackBar('تم حذف الفاتورة بنجاح', color: Colors.green);
          await _fetchFactures();
          await _fetchFacturesSummary();
        } else {
          final error = jsonDecode(resp.body);
          _showSnackBar(
              'فشل حذف الفاتورة: ${error['error'] ?? 'خطأ غير معروف'}');
        }
      } catch (e) {
        _showSnackBar('خطأ في الاتصال: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    // ==================== FACTURES TAB ====================
    if (selectedTab == 2) {
      content = Column(
        children: [
          if (facturesSummary != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  summaryCard(typeLabels, 'factures',
                      '${facturesSummary!['total_factures']}'),
                  const SizedBox(width: 8),
                  summaryCard(
                      typeLabels,
                      'income',
                      '${(facturesSummary!['total_income'] as num?)?.toStringAsFixed(2) ?? '0'} دج'),
                  const SizedBox(width: 8),
                  summaryCard(
                      typeLabels,
                      'remaining',
                      '${(facturesSummary!['total_remaining'] as num?)?.toStringAsFixed(2) ?? '0'} دج'),
                  const SizedBox(width: 8),
                  summaryCard(
                      typeLabels,
                      'profit',
                      '${(facturesSummary!['total_profit'] as num?)?.toStringAsFixed(2) ?? '0'} دج'),
                ],
              ),
            ),
          Expanded(
            child: Row(
              children: [
                SidePanel(
                  title: 'فواتير المبيعات',
                  topFilters: Column(
                    children: [
                      if (allSeasons.isNotEmpty)
                        Column(
                          children: [
                            DropdownButtonFormField<int?>(
                              value: selectedSeasonId,
                              decoration: const InputDecoration(
                                labelText: 'تصفية حسب الموسم',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('جميع المواسم'),
                                ),
                                ...allSeasons.map<DropdownMenuItem<int?>>((season) {
                                  return DropdownMenuItem<int?>(
                                    value: season['id'] as int,
                                    child: Text(season['name'] as String),
                                  );
                                }).toList(),
                              ],
                              onChanged: _onSeasonChanged,
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      // Add new facture button under the dropdown
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text('فاتورة جديدة',
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[700],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: allModels.isNotEmpty && allClients.isNotEmpty
                              ? _addNewFacture
                              : null,
                        ),
                      ),
                    ],
                  ),
                  list: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : allFactures.isEmpty
                          ? const Center(child: Text('لا توجد فواتير'))
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              itemCount: allFactures.length,
                              itemBuilder: (_, i) {
                                final f = allFactures[i];
                                final isSel = f['id'] == selectedFactureId;
                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  elevation: isSel ? 4 : 1,
                                  color:
                                      isSel ? Colors.grey[100] : Colors.white,
                                  child: ListTile(
                                    selected: isSel,
                                    title: Text(
                                      'فاتورة رقم ${f['id']}',
                                      style: TextStyle(
                                        fontWeight: isSel
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            'تاريخ: ${fmtDate(f['facture_date'])}'),
                                        Text(
                                            'العميل: ${f['client_name'] ?? 'غير محدد'}',
                                            style: TextStyle(
                                                color: Colors.teal[700])),
                                        Text(
                                            'الإجمالي: ${f['total_amount']?.toStringAsFixed(2) ?? '0'} دج'),
                                        Text(
                                          'المتبقي: ${f['remaining_amount']?.toStringAsFixed(2) ?? '0'} دج',
                                          style: TextStyle(
                                              color: Colors.red[700]),
                                        ),
                                      ],
                                    ),
                                    onTap: () => setState(
                                        () => selectedFactureId = f['id']),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () => _deleteFacture(f),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selectedFacture == null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'اختر فاتورة من القائمة الجانبية',
                                style: TextStyle(
                                    fontSize: 18, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: FutureBuilder<Map<String, dynamic>>(
                            future: _loadFactureDetail(selectedFactureId!),
                            builder: (ctx, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              if (snap.hasError) {
                                return Center(
                                    child: Text('خطأ: ${snap.error}'));
                              }
                              final d = snap.data!;
                              return SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'تفاصيل فاتورة رقم ${d['id']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.indigo[800],
                                          ),
                                    ),
                                    const SizedBox(height: 24),

                                    // معلومات الفاتورة
                                    Card(
                                      color: Colors.blue[50],
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'معلومات الفاتورة',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue[800],
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                const Icon(Icons.calendar_today,
                                                    size: 20,
                                                    color: Colors.blue),
                                                const SizedBox(width: 8),
                                                Text(
                                                    'التاريخ: ${fmtDate(d['facture_date'])}'),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(Icons.person,
                                                    size: 20,
                                                    color: Colors.blue),
                                                const SizedBox(width: 8),
                                                Text('العميل: ${d['client_name']}'),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(Icons.phone,
                                                    size: 20,
                                                    color: Colors.blue),
                                                const SizedBox(width: 8),
                                                Text('الهاتف: ${d['client_phone']}'),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(Icons.location_on,
                                                    size: 20,
                                                    color: Colors.blue),
                                                const SizedBox(width: 8),
                                                Text('العنوان: ${d['client_address']}'),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // معلومات الدفع
                                    Card(
                                      color: Colors.green[50],
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'معلومات الدفع',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green[800],
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: costItem('الإجمالي',
                                                      d['total_amount'],
                                                      Colors.green[700]!),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: costItem('المدفوع',
                                                      d['total_paid'],
                                                      Colors.blue[700]!),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: costItem('المتبقي',
                                                      d['remaining_amount'],
                                                      Colors.orange[700]!),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: d[
                                                                  'remaining_amount'] <=
                                                              0
                                                          ? Colors.green
                                                              .withOpacity(0.1)
                                                          : Colors.orange
                                                              .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      border: Border.all(
                                                          color: (d['remaining_amount'] <=
                                                                      0
                                                                  ? Colors.green
                                                                  : Colors
                                                                      .orange)
                                                              .withOpacity(
                                                                  0.3)),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'الحالة',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: d['remaining_amount'] <=
                                                                    0
                                                                ? Colors
                                                                    .green[700]
                                                                : Colors.orange[
                                                                    700],
                                                          ),
                                                        ),
                                                        Text(
                                                          d['remaining_amount'] <=
                                                                  0
                                                              ? 'مدفوع بالكامل'
                                                              : d['total_paid'] >
                                                                      0
                                                                  ? 'مدفوع جزئياً'
                                                                  : 'غير مدفوع',
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: d['remaining_amount'] <=
                                                                    0
                                                                ? Colors
                                                                    .green[700]
                                                                : Colors.orange[
                                                                    700],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    // تفاصيل المنتجات
                                    Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'تفاصيل المنتجات',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey[800],
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: DataTable(
                                                headingRowColor:
                                                    MaterialStateProperty.all(
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .primary),
                                                headingTextStyle:
                                                    const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                columns: const [
                                                  DataColumn(
                                                      label: Text('المنتج')),
                                                  DataColumn(
                                                      label: Text('الكمية')),
                                                  DataColumn(
                                                      label: Text('سعر البيع')),
                                                  DataColumn(
                                                      label: Text('ربح/قطعة')),
                                                  DataColumn(
                                                      label:
                                                          Text('إجمالي الربح')),
                                                  DataColumn(
                                                      label: Text('الإجمالي')),
                                                ],
                                                rows: (d['items']
                                                        as List<dynamic>)
                                                    .map<DataRow>((it) {
                                                  final totalProfit =
                                                      (it['profit_per_piece'] ??
                                                              0) *
                                                          (it['quantity'] ?? 0);
                                                  return DataRow(cells: [
                                                    DataCell(Text(
                                                        '${it['model_name'] ?? 'غير محدد'}')),
                                                    DataCell(Text(it['quantity']
                                                        .toString())),
                                                    DataCell(Text(
                                                        '${it['unit_price']} دج')),
                                                    DataCell(Text(
                                                        '${(it['profit_per_piece'] ?? 0).toStringAsFixed(2)} دج')),
                                                    DataCell(Text(
                                                        '${totalProfit.toStringAsFixed(2)} دج')),
                                                    DataCell(Text(
                                                        '${(it['line_total'] ?? 0).toStringAsFixed(2)} دج')),
                                                  ]);
                                                }).toList(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // الدفعات
                                    Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'الدفعات',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey[800],
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            if (d['amount_paid_on_creation'] !=
                                                    null &&
                                                d['amount_paid_on_creation'] >
                                                    0)
                                              ListTile(
                                                leading: const Icon(Icons.payment,
                                                    color: Colors.green),
                                                title: Text(
                                                    '${d['amount_paid_on_creation']?.toStringAsFixed(2) ?? '0'} دج'),
                                                subtitle: Text(
                                                    'دفعة عند الإنشاء - تاريخ: ${fmtDate(d['facture_date'])}'),
                                              ),
                                            if (d['payments'] != null &&
                                                (d['payments'] as List)
                                                    .isNotEmpty)
                                              ...((d['payments'] as List).map<
                                                      Widget>((p) =>
                                                  ListTile(
                                                    leading: const Icon(
                                                        Icons.payment),
                                                    title: Text(
                                                        '${p['amount_paid']?.toStringAsFixed(2) ?? '0'} دج'),
                                                    subtitle: Text(
                                                        'تاريخ: ${fmtDate(p['payment_date'])}'),
                                                  ))).toList()
                                            else if (d['amount_paid_on_creation'] == null ||
                                                d['amount_paid_on_creation'] ==
                                                    0)
                                              const Text('لا توجد دفعات'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // ==================== MODELS TAB ====================
    else if (selectedTab == 0) {
      content = Row(
        children: [
          SidePanel(
            title: 'الموديلات',
            topFilters: allSeasons.isNotEmpty
                ? DropdownButtonFormField<int?>(
                    value: selectedSeasonId,
                    decoration: const InputDecoration(
                      labelText: 'تصفية حسب الموسم',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('جميع المواسم'),
                      ),
                      ...allSeasons.map<DropdownMenuItem<int?>>((season) {
                        return DropdownMenuItem<int?>(
                          value: season['id'] as int,
                          child: Text(season['name'] as String),
                        );
                      }).toList(),
                    ],
                    onChanged: _onSeasonChanged,
                  )
                : null,
            list: isLoading
                ? const Center(child: CircularProgressIndicator())
                : allModels.isEmpty
                    ? const Center(child: Text('لا يوجد موديلات'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: allModels.length,
                        itemBuilder: (_, i) {
                          final m = allModels[i];
                          final isSel = m['id'] == selectedModelId;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            elevation: isSel ? 4 : 1,
                            color: isSel ? Colors.grey[100] : Colors.white,
                            child: ListTile(
                              selected: isSel,
                              title: Text(
                                m['name'],
                                style: TextStyle(
                                  fontWeight: isSel
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('المتاح: ${m['available_quantity']}'),
                                  Text('التكلفة: ${m['cost_price']} دج',
                                      style:
                                          TextStyle(color: Colors.teal[700])),
                                ],
                              ),
                              onTap: () =>
                                  setState(() => selectedModelId = m['id']),
                            ),
                          );
                        },
                      ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selectedModelId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'اختر موديل لعرض التفاصيل',
                          style:
                              TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ModelBuyersPanel(
                    modelId: selectedModelId!,
                    seasonId: selectedSeasonId,
                  ),
          ),
        ],
      );
    }

    // ==================== CLIENTS TAB ====================
    else {
      content = Row(
        children: [
          SidePanel(
            title: 'العملاء',
            topFilters: allSeasons.isNotEmpty
                ? DropdownButtonFormField<int?>(
                    value: selectedSeasonId,
                    decoration: const InputDecoration(
                      labelText: 'تصفية حسب الموسم',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('جميع المواسم'),
                      ),
                      ...allSeasons.map<DropdownMenuItem<int?>>((season) {
                        return DropdownMenuItem<int?>(
                          value: season['id'] as int,
                          child: Text(season['name'] as String),
                        );
                      }).toList(),
                    ],
                    onChanged: _onSeasonChanged,
                  )
                : null,
            list: isLoading
                ? const Center(child: CircularProgressIndicator())
                : allClients.isEmpty
                    ? const Center(child: Text('لا يوجد عملاء'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: allClients.length,
                        itemBuilder: (_, i) {
                          final c = allClients[i];
                          final isSel = c['id'] == selectedClientId;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            elevation: isSel ? 4 : 1,
                            color: isSel ? Colors.grey[100] : Colors.white,
                            child: ListTile(
                              selected: isSel,
                              title: Text(
                                c['full_name'],
                                style: TextStyle(
                                  fontWeight: isSel
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c['phone'] ?? ''),
                                  Text(c['address'] ?? '',
                                      style: TextStyle(color: Colors.teal[700])),
                                ],
                              ),
                              onTap: () =>
                                  setState(() => selectedClientId = c['id']),
                            ),
                          );
                        },
                      ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selectedClientId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'اختر عميل لعرض التفاصيل',
                          style:
                              TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ClientDetailsTabs(
                    clientId: selectedClientId!,
                    seasonId: selectedSeasonId,
                  ),
          ),
        ],
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          TabHeader(
            tabs: const ['الموديلات', 'العملاء', 'الفواتير'],
            selected: selectedTab,
            onChanged: (i) {
              setState(() {
                selectedTab = i;
                if (i != 1) selectedClientId = null;
                if (i != 0) selectedModelId = null;
              });
            },
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// =============================================================
/// ModelBuyersPanel - Enhanced Design
/// =============================================================
class ModelBuyersPanel extends StatefulWidget {
  final int modelId;
  final int? seasonId;
  const ModelBuyersPanel({super.key, required this.modelId, this.seasonId});

  @override
  State<ModelBuyersPanel> createState() => _ModelBuyersPanelState();
}

class _ModelBuyersPanelState extends State<ModelBuyersPanel> {
  bool isLoading = false;
  List<dynamic> buyers = [];

  @override
  void initState() {
    super.initState();
    _fetchBuyers();
  }

  @override
  void didUpdateWidget(ModelBuyersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelId != widget.modelId ||
        oldWidget.seasonId != widget.seasonId) {
      _fetchBuyers();
    }
  }

  Future<void> _fetchBuyers() async {
    setState(() {
      isLoading = true;
      buyers = [];
    });
    try {
      final resp = await http.get(Uri.parse(
          'http://localhost:8888/sales/models/${widget.modelId}/clients'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        if (widget.seasonId == null) {
          setState(() => buyers = data);
        } else {
          setState(() => buyers = data);
        }
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (buyers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا يوجد عملاء اشتروا هذا الموديل',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // Group by client
    final Map<int, List<Map<String, dynamic>>> byClient = {};
    for (final b in buyers) {
      final id = b['client_id'] as int;
      byClient.putIfAbsent(id, () => []).add(Map<String, dynamic>.from(b));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'العملاء الذين اشتروا هذا الموديل',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.indigo[800],
            ),
          ),
          const SizedBox(height: 24),
          ...byClient.entries.map((entry) {
            final client = entry.value.first;
            final sales = entry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Client Info Card
                    Card(
                      color: Colors.blue[50],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.blue[200],
                              child: Icon(Icons.person, color: Colors.blue[800]),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    client['client_name'],
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[800],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.phone, size: 16, color: Colors.blue[600]),
                                      const SizedBox(width: 4),
                                      Text('${client['client_phone']}'),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.location_on, size: 16, color: Colors.blue[600]),
                                      const SizedBox(width: 4),
                                      Expanded(child: Text('${client['client_address']}')),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'سجلات بيع هذا الموديل لهذا العميل:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.all(
                            Theme.of(context).colorScheme.primary),
                        headingTextStyle: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        columns: const [
                          DataColumn(label: Text('تاريخ الفاتورة')),
                          DataColumn(label: Text('رقم الفاتورة')),
                          DataColumn(label: Text('الكمية')),
                          DataColumn(label: Text('سعر البيع')),
                          DataColumn(label: Text('الإجمالي')),
                        ],
                        rows: sales
                            .map<DataRow>((s) => DataRow(cells: [
  DataCell(Text(fmtDate(s['facture_date'].toString()))),
  DataCell(Text(s['facture_id'].toString())),
  DataCell(Text(s['quantity'].toString())),
  DataCell(Text('${s['unit_price']} دج')),
  DataCell(Text(
    '${(s['quantity'] * double.parse(s['unit_price'].toString())).toStringAsFixed(2)} دج'
  )),
]))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}

/// =============================================================
/// ClientDetailsTabs - Enhanced Design with Print Function
/// =============================================================
class ClientDetailsTabs extends StatefulWidget {
  final int clientId;
  final int? seasonId;
  const ClientDetailsTabs({super.key, required this.clientId, this.seasonId});

  @override
  State<ClientDetailsTabs> createState() => _ClientDetailsTabsState();
}

class _ClientDetailsTabsState extends State<ClientDetailsTabs> {
  int selectedTab = 0;
  List<dynamic> clientFactures = [];
  List<dynamic> clientTransactions = [];
  Set<int> expandedFactureIds = {};

  bool loadingFactures = false;
  bool loadingTransactions = false;

  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    _fetchFactures();
    _fetchTransactions();
  }

  @override
  void didUpdateWidget(ClientDetailsTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId ||
        oldWidget.seasonId != widget.seasonId) {
      _fetchFactures();
      _fetchTransactions();
      expandedFactureIds.clear();
    }
  }

  Future<void> _fetchFactures() async {
    setState(() {
      loadingFactures = true;
      clientFactures = [];
    });
    try {
      String url =
          'http://localhost:8888/sales/clients/${widget.clientId}/factures';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        setState(() => clientFactures = data);
      }
    } finally {
      setState(() => loadingFactures = false);
    }
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      loadingTransactions = true;
      clientTransactions = [];
    });
    try {
      String url =
          'http://localhost:8888/sales/clients/${widget.clientId}/transactions';
      if (startDate != null && endDate != null) {
        final start = startDate!.toIso8601String().split('T')[0];
        final end = endDate!.toIso8601String().split('T')[0];
        url += '?start_date=$start&end_date=$end';
      }
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        setState(() => clientTransactions = jsonDecode(resp.body));
      }
    } finally {
      setState(() => loadingTransactions = false);
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: startDate != null && endDate != null
          ? DateTimeRange(start: startDate!, end: endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
      _fetchTransactions();
    }
  }

  Future<void> _printTransactions() async {
    if (clientTransactions.isEmpty) return;

    final pdf = pw.Document();

    // Get client info
    String clientName = 'عميل غير معروف';
    if (clientTransactions.isNotEmpty) {
      try {
        final clientResp = await http.get(
            Uri.parse('http://localhost:8888/sales/clients'));
        if (clientResp.statusCode == 200) {
          final clients = jsonDecode(clientResp.body) as List;
          final client = clients.firstWhere(
            (c) => c['id'] == widget.clientId,
            orElse: () => null,
          );
          if (client != null) {
            clientName = client['full_name'];
          }
        }
      } catch (e) {
        print('Error fetching client info: $e');
      }
    }

    // Load Arabic font
    final arabicFont = await PdfGoogleFonts.notoSansArabicRegular();

    pdf.addPage(
      pw.Page(
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'كشف حساب العميل: $clientName',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  font: arabicFont,
                ),
              ),
              pw.SizedBox(height: 10),
              if (startDate != null && endDate != null)
                pw.Text(
                  'من ${fmtDate(startDate!.toIso8601String())} إلى ${fmtDate(endDate!.toIso8601String())}',
                  style: pw.TextStyle(font: arabicFont),
                ),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                context: context,
                headers: ['التاريخ', 'نوع العملية', 'رقم الفاتورة', 'المبلغ'],
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  font: arabicFont,
                ),
                cellStyle: pw.TextStyle(font: arabicFont),
                data: clientTransactions.map((transaction) {
                  return [
                    fmtDate(transaction['date'].toString()),
                    transaction['label'].toString(),
                    transaction['facture_id']?.toString() ?? '-',
                    '${transaction['amount'].toString()} دج',
                  ];
                }).toList(),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[100], // Same background as main area
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ...['الفواتير', 'الحساب'].asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
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
                    ),
                  ),
            ],
          ),
        ),
        Expanded(
          child: selectedTab == 0 ? _buildFacturesTab() : _buildAccountTab(),
        ),
      ],
    );
  }

  Widget _buildFacturesTab() {
    if (loadingFactures) {
      return const Center(child: CircularProgressIndicator());
    }
    if (clientFactures.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا توجد فواتير',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'فواتير العميل',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.indigo[800],
            ),
          ),
          const SizedBox(height: 16),
          ...clientFactures.map((f) {
            final expanded = expandedFactureIds.contains(f['id']);
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              elevation: 2,
              child: Column(
                children: [
                  Card(
                    color: Colors.blue[50],
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue[200],
                        child: Text('${f['id']}'),
                      ),
                      title: Text(
                        'فاتورة رقم ${f['id']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 16, color: Colors.blue[600]),
                              const SizedBox(width: 4),
                              Text('التاريخ: ${fmtDate(f['facture_date'])}'),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: costItem('الإجمالي', f['total_amount'], Colors.green[700]!),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: costItem('المدفوع', f['total_paid'], Colors.blue[700]!),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: costItem('المتبقي', f['remaining_amount'], Colors.orange[700]!),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: expanded ? Colors.blue : Colors.grey,
                      ),
                      onTap: () {
                        setState(() {
                          if (expanded) {
                            expandedFactureIds.remove(f['id']);
                          } else {
                            expandedFactureIds.add(f['id']);
                          }
                        });
                      },
                    ),
                  ),
                  if (expanded)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تفاصيل المنتجات:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(
                                  Theme.of(context).colorScheme.primary),
                              headingTextStyle: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold),
                              columns: const [
                                DataColumn(label: Text('المنتج')),
                                DataColumn(label: Text('الكمية')),
                                DataColumn(label: Text('سعر البيع')),
                                DataColumn(label: Text('ربح/قطعة')),
                                DataColumn(label: Text('الإجمالي')),
                              ],
                              rows: (f['items'] as List)
                                  .map<DataRow>(
                                    (it) => DataRow(cells: [
                                      DataCell(Text(it['model_name'] ?? '')),
                                      DataCell(Text(it['quantity'].toString())),
                                      DataCell(Text(
                                          '${it['unit_price'].toStringAsFixed(2)} دج')),
                                      DataCell(Text(
                                          '${(it['profit_per_piece'] ?? 0).toStringAsFixed(2)} دج')),
                                      DataCell(Text(
                                          '${it['line_total'].toStringAsFixed(2)} دج')),
                                    ]),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildAccountTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        startDate != null && endDate != null
                            ? 'من ${fmtDate(startDate!.toIso8601String())} إلى ${fmtDate(endDate!.toIso8601String())}'
                            : 'اختر نطاق التاريخ',
                      ),
                      onPressed: _selectDateRange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (startDate != null && endDate != null)
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          startDate = null;
                          endDate = null;
                        });
                        _fetchTransactions();
                      },
                      child: const Text('إزالة التصفية'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (clientTransactions.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.print, color: Colors.white),
                    label: const Text('طباعة المعاملات', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _printTransactions,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: loadingTransactions
              ? const Center(child: CircularProgressIndicator())
              : clientTransactions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance_outlined, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'لا يوجد بيانات حساب',
                            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المعاملات المالية',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo[800],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                    Theme.of(context).colorScheme.primary),
                                headingTextStyle: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold),
                                columns: const [
                                  DataColumn(label: Text('التاريخ')),
                                  DataColumn(label: Text('نوع العملية')),
                                  DataColumn(label: Text('رقم الفاتورة')),
                                  DataColumn(label: Text('المبلغ')),
                                ],
                                rows: clientTransactions
                                    .map<DataRow>(
                                      (e) => DataRow(cells: [
                                        DataCell(Text(fmtDate(e['date'].toString()))),
                                        DataCell(Text(e['label'].toString())),
                                        DataCell(Text(e['facture_id']?.toString() ?? '-')),
                                        DataCell(Text(
                                          '${e['amount'].toString()} دج',
                                          style: TextStyle(
                                            color: (e['amount'] as num) >= 0
                                                ? Colors.red
                                                : Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )),
                                      ]),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}
