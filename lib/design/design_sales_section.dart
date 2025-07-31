// lib/design/design_sales_section.dart
// Compatible with your NEW design schema (no global_price/cost columns)
// - Uses m.price
// - Removes profit columns/calculations
// - Adds vertical & horizontal Scrollbars to all tables
// - Keeps same UX as your sewing sales section (tabs, side panels, dialogs)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// ===================== CONFIG =====================
const String kBaseUrl = 'http://localhost:8888/design/sales'; // << adjust if needed

/// ===================== HELPERS =====================
void showSnack(BuildContext ctx, String msg, {Color? color}) {
  ScaffoldMessenger.of(ctx)
      .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
}

String fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final d = DateTime.parse(iso);
    return "${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}";
  } catch (_) {
    return iso.split('T').first;
  }
}

double parseNum(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int parseInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
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

/// ===================== SHARED WIDGETS =====================
class TabHeader extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;
  const TabHeader({super.key, required this.tabs, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(tabs.length, (i) {
          final sel = selected == i;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
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
  const SidePanel({super.key, required this.title, this.topFilters, required this.list});

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

/// ===================== MAIN SECTION =====================
class DesignSalesSection extends StatefulWidget {
  const DesignSalesSection({super.key});

  @override
  State<DesignSalesSection> createState() => _DesignSalesSectionState();
}

class _DesignSalesSectionState extends State<DesignSalesSection> {
  int selectedTab = 2; // 0 Models, 1 Clients, 2 Factures

  List<dynamic> seasons = [];
  List<dynamic> models = [];
  List<dynamic> clients = [];
  List<dynamic> factures = [];
  Map<String, dynamic>? facturesSummary;

  int? seasonId;
  int? selectedFactureId;
  int? selectedModelId;
  int? selectedClientId;

  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);
    try {
      await Future.wait([
        _fetchSeasons(),
        _fetchModels(),
        _fetchClients(),
        _fetchFactures(),
        _fetchSummary(),
      ]);
    } catch (e) {
      showSnack(context, 'خطأ في تحميل البيانات: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _fetchSeasons() async {
    try {
      final r = await http.get(Uri.parse('$kBaseUrl/seasons'));
      if (r.statusCode == 200) {
        seasons = jsonDecode(r.body);
      }
    } catch (_) {
      seasons = [];
    }
  }

  Future<void> _fetchModels() async {
    String url = '$kBaseUrl/models';
    if (seasonId != null && seasons.isNotEmpty) {
      url = '$kBaseUrl/models/by_season/$seasonId';
    }
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw Exception('models ${r.statusCode}');
    models = jsonDecode(r.body);
  }

  Future<void> _fetchClients() async {
    String url = '$kBaseUrl/clients';
    if (seasonId != null && seasons.isNotEmpty) {
      url = '$kBaseUrl/clients/by_season/$seasonId';
    }
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw Exception('clients ${r.statusCode}');
    clients = jsonDecode(r.body);
  }

  Future<void> _fetchFactures() async {
    String url = '$kBaseUrl/factures';
    if (seasonId != null && seasons.isNotEmpty) {
      url = '$kBaseUrl/factures/by_season/$seasonId';
    }
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw Exception('factures ${r.statusCode}');
    factures = jsonDecode(r.body);
    if (factures.isNotEmpty) {
      if (selectedFactureId == null) {
        selectedFactureId = factures.first['id'];
      } else if (!factures.any((f) => f['id'] == selectedFactureId)) {
        selectedFactureId = factures.first['id'];
      }
    } else {
      selectedFactureId = null;
    }
  }

  Future<void> _fetchSummary() async {
    try {
      final r = await http.get(Uri.parse('$kBaseUrl/factures/summary'));
      if (r.statusCode == 200) {
        facturesSummary = jsonDecode(r.body);
      } else {
        facturesSummary = null;
      }
    } catch (_) {
      facturesSummary = null;
    }
  }

  Future<Map<String, dynamic>> _loadFacture(int id) async {
    final r = await http.get(Uri.parse('$kBaseUrl/factures/$id'));
    if (r.statusCode != 200) throw Exception('facture ${r.statusCode}');
    return jsonDecode(r.body);
  }

  Future<void> _onSeasonChanged(int? v) async {
    setState(() => seasonId = v);
    await Future.wait([
      _fetchModels(),
      _fetchClients(),
      _fetchFactures(),
      _fetchSummary(),
    ]);
    setState(() {}); // refresh
  }

  Future<void> _deleteFacture(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الفاتورة'),
        content: Text('هل أنت متأكد من حذف الفاتورة رقم ${f['id']}؟'),
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
    if (ok != true) return;
    final r = await http.delete(Uri.parse('$kBaseUrl/factures/${f['id']}'));
    if (r.statusCode == 200) {
      showSnack(context, 'تم الحذف', color: Colors.green);
      await _fetchFactures();
      await _fetchSummary();
      setState(() {});
    } else {
      showSnack(context, 'فشل الحذف: ${r.body}', color: Colors.red);
    }
  }

  Future<void> _addFactureDialog() async {
    int? clientId;
    String payType = 'debt';
    double paidOnCreation = 0.0;
    final amountCtrl = TextEditingController();
    final factureNameCtrl = TextEditingController();

    final List<Map<String, dynamic>> items = [];
    DateTime factureDate = DateTime.now();

    double getTotal() =>
        items.fold<double>(0, (s, it) => s + it['quantity'] * it['unit_price']);

    Future<void> addItem(StateSetter setOuter) async {
  int? modelId;
  final qtyCtrl   = TextEditingController();
  final priceCtrl = TextEditingController();

  // 1) Only products with stock > 0
  final availableModels = models
      .where((m) => parseInt(m['available_quantity']) > 0)
      .toList();
  if (availableModels.isEmpty) {
    showSnack(context, 'لا يوجد مخزون متاح', color: Colors.orange);
    return;
  }

  // 2) Show dialog
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setDialog) => AlertDialog(
        title: const Text('إضافة منتج'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Product dropdown
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'اختر المنتج'),
                items: availableModels.map((m) {
                  return DropdownMenuItem<int>(
                    value: m['id'] as int,
                    child: Text('${m['name']} (متاح: ${m['available_quantity']})'),
                  );
                }).toList(),
                onChanged: (v) => setDialog(() => modelId = v),
              ),
              const SizedBox(height: 12),
              // Quantity
              TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(labelText: 'الكمية'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              // Price
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'سعر البيع'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              // 3) Validation
              if (modelId == null) {
                showSnack(context, 'يرجى اختيار المنتج', color: Colors.red);
                return;
              }
              final q = int.tryParse(qtyCtrl.text) ?? 0;
              final p = double.tryParse(priceCtrl.text) ?? 0.0;
              if (q <= 0 || p <= 0) {
                showSnack(context, 'يرجى إدخال قيم صحيحة', color: Colors.red);
                return;
              }

              final prod  = availableModels.firstWhere((m) => m['id'] == modelId);
              final avail = parseInt(prod['available_quantity']);
              if (q > avail) {
                showSnack(context, 'الكمية أكبر من المتاح (متاح: $avail)', color: Colors.red);
                return;
              }

              // 4) Merge only if same model AND same unit_price
              final existingIdx = items.indexWhere((i) =>
                i['model_id']   == modelId &&
                (i['unit_price'] as double) == p
              );

              if (existingIdx != -1) {
                // Update quantity of that exact line
                items[existingIdx]['quantity'] = q;
              } else {
                // New combination → push a new line
                items.add({
                  'model_id'           : modelId,
                  'model_name'         : prod['name'],
                  'quantity'           : q,
                  'unit_price'         : p,
                  'available_quantity' : avail,
                });
              }

              // 5) Refresh outer dialog & close
              setOuter(() {});
              Navigator.pop(ctx2);
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
        builder: (ctx, setD) => AlertDialog(
          title: const Text('فاتورة جديدة'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Date
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Text('تاريخ: ${factureDate.toLocal().toString().split(' ')[0]}'),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: () async {
                              final p = await showDatePicker(
                                context: context,
                                initialDate: factureDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (p != null) setD(() => factureDate = p);
                            },
                            child: const Text('تغيير'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // TextField(
                  //   controller: factureNameCtrl,
                  //   decoration: const InputDecoration(labelText: 'اسم الفاتورة (إجباري)'),
                  // ),
                  // const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'اختر العميل'),
                    value: clientId,
                    items: clients
                        .map((c) => DropdownMenuItem<int>(
                              value: c['id'] as int,
                              child: Text(c['full_name']),
                            ))
                        .toList(),
                    onChanged: (v) => setD(() => clientId = v),
                  ),
                  const SizedBox(height: 12),
                  if (items.isNotEmpty)
                    Card(
                      color: Colors.grey[50],
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('المنتجات',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(
                                  'الإجمالي: ${getTotal().toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                              ],
                            ),
                            const Divider(),
                            ...items.asMap().entries.map((e) {
                              final idx = e.key;
                              final it = e.value;
                              return ListTile(
                                title: Text(it['model_name']),
                                subtitle: Text(
                                  'المتاح: ${it['available_quantity']} | ${it['quantity']} × ${it['unit_price']} = ${(it['quantity'] * it['unit_price']).toStringAsFixed(2)}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => setD(() => items.removeAt(idx)),
                                ),
                              );
                            }).toList()
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
                        onPressed: () => addItem(setD),
                      ),
                    ],
                  ),
                  const Divider(),
                  Text('الإجمالي: ${getTotal().toStringAsFixed(2)} دج',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ListTile(
                    title: const Text('بيع بالدين'),
                    leading: Radio<String>(
                      value: 'debt',
                      groupValue: payType,
                      onChanged: (v) => setD(() => payType = v!),
                    ),
                  ),
                  ListTile(
                    title: const Text('بيع نقدي'),
                    leading: Radio<String>(
                      value: 'cash',
                      groupValue: payType,
                      onChanged: (v) => setD(() => payType = v!),
                    ),
                  ),
                  if (payType == 'cash')
                    TextField(
                      controller: amountCtrl,
                      decoration: InputDecoration(
                        labelText:
                            'دفعة أولى (حد أقصى: ${getTotal().toStringAsFixed(2)})',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) {
                        final a = double.tryParse(v) ?? 0;
                        final total = getTotal();
                        paidOnCreation = a > total ? total : a;
                        if (a > total) amountCtrl.text = total.toStringAsFixed(2);
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                // if (factureNameCtrl.text.trim().isEmpty) {
                //   showSnack(context, 'اسم الفاتورة مطلوب', color: Colors.red);
                //   return;
                // }
                if (clientId == null) {
                  showSnack(context, 'اختر العميل', color: Colors.red);
                  return;
                }
                if (items.isEmpty) {
                  showSnack(context, 'أضف منتج واحد على الأقل', color: Colors.red);
                  return;
                }
                final total = getTotal();
                if (payType == 'cash' && paidOnCreation > total) {
                  showSnack(context, 'الدفعة أكبر من الإجمالي', color: Colors.red);
                  return;
                }
                final payload = {
                  'client_id': clientId,
                  'facture_name': factureNameCtrl.text.trim(),
                  'facture_date': factureDate.toIso8601String().split('T')[0],
                  'total_amount': total,
                  'amount_paid_on_creation': payType == 'cash' ? paidOnCreation : 0.0,
                  'items': items
                      .map((e) => {
                            'model_id': e['model_id'],
                            'quantity': e['quantity'],
                            'unit_price': e['unit_price'],
                          })
                      .toList()
                };
                try {
                  final r = await http.post(
                    Uri.parse('$kBaseUrl/factures'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  );
                  if (r.statusCode == 201) {
                    showSnack(context, 'تمت الإضافة', color: Colors.green);
                    Navigator.pop(ctx);
                    await _fetchFactures();
                    await _fetchSummary();
                    setState(() {});
                  } else {
                    showSnack(context, 'فشل الإضافة: ${r.body}', color: Colors.red);
                  }
                } catch (e) {
                  showSnack(context, 'خطأ اتصال: $e', color: Colors.red);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    // FACTURES
    if (selectedTab == 2) {
      body = Column(
        children: [
          if (facturesSummary != null)
            // Padding(
            //   padding: const EdgeInsets.all(16),
            //   child: Row(
            //     children: [
            //       _summaryCard('عدد الفواتير', '${facturesSummary!['total_factures']}',
            //           Colors.blue),
            //       const SizedBox(width: 8),
            //       _summaryCard(
            //           'إجمالي المدخول',
            //           '${parseNum(facturesSummary!['total_income']).toStringAsFixed(2)} دج',
            //           Colors.green),
            //       const SizedBox(width: 8),
            //       _summaryCard(
            //           'إجمالي المتبقي',
            //           '${parseNum(facturesSummary!['total_remaining']).toStringAsFixed(2)} دج',
            //           Colors.orange),
            //     ],
            //   ),
            // ),
          Expanded(
            child: Row(
              children: [
                SidePanel(
                  title: 'فواتير المبيعات',
                  topFilters: Column(
                    children: [
                      if (seasons.isNotEmpty)
                        DropdownButtonFormField<int?>(
                          value: seasonId,
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
                            ...seasons.map((s) => DropdownMenuItem<int?>(
                                  value: s['id'] as int,
                                  child: Text(s['name']),
                                ))
                          ],
                          onChanged: _onSeasonChanged,
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text('فاتورة جديدة',
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[700],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed:
                              (models.isNotEmpty && clients.isNotEmpty) ? _addFactureDialog : null,
                        ),
                      ),
                    ],
                  ),
                  list: loading
                      ? const Center(child: CircularProgressIndicator())
                      : factures.isEmpty
                          ? const Center(child: Text('لا توجد فواتير'))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              itemCount: factures.length,
                              itemBuilder: (_, i) {
                                final f = factures[i];
                                final sel = f['id'] == selectedFactureId;
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  elevation: sel ? 4 : 1,
                                  color: sel ? Colors.grey[100] : Colors.white,
                                  child: ListTile(
                                    selected: sel,
                                    title: Text(
                                      'فاتورة ${f['id']}',
                                      style: TextStyle(
                                          fontWeight: sel ? FontWeight.bold : FontWeight.normal),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('تاريخ: ${fmtDate(f['facture_date'])}'),
                                        Text('العميل: ${f['client_name'] ?? ''}',
                                            style: TextStyle(color: Colors.teal[700])),
                                        Text(
                                            'الإجمالي: ${parseNum(f['total_amount']).toStringAsFixed(2)} دج'),
                                        Text(
                                          'المتبقي: ${parseNum(f['remaining_amount']).toStringAsFixed(2)} دج',
                                          style: TextStyle(color: Colors.red[700]),
                                        ),
                                      ],
                                    ),
                                    onTap: () => setState(() => selectedFactureId = f['id']),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteFacture(f),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selectedFactureId == null
                      ? _emptyHint(Icons.receipt_long, 'اختر فاتورة من القائمة')
                      : _FactureDetailView(factureId: selectedFactureId!),
                )
              ],
            ),
          ),
        ],
      );
    }

    // MODELS
    else if (selectedTab == 0) {
      body = Row(
        children: [
          SidePanel(
            title: 'الموديلات',
            topFilters: seasons.isNotEmpty
                ? DropdownButtonFormField<int?>(
                    value: seasonId,
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
                      ...seasons.map((s) => DropdownMenuItem<int?>(
                            value: s['id'] as int,
                            child: Text(s['name']),
                          ))
                    ],
                    onChanged: _onSeasonChanged,
                  )
                : null,
            list: loading
                ? const Center(child: CircularProgressIndicator())
                : models.isEmpty
                    ? const Center(child: Text('لا يوجد موديلات'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: models.length,
                        itemBuilder: (_, i) {
                          final m = models[i];
                          final sel = m['id'] == selectedModelId;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            elevation: sel ? 4 : 1,
                            color: sel ? Colors.grey[100] : Colors.white,
                            child: ListTile(
                              selected: sel,
                              title: Text(
                                m['name'],
                                style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('المتاح: ${m['available_quantity']}'),
                                  Text('السعر: ${parseNum(m['price']).toStringAsFixed(2)} دج',
                                      style: TextStyle(color: Colors.teal[700])),
                                ],
                              ),
                              onTap: () => setState(() => selectedModelId = m['id']),
                            ),
                          );
                        },
                      ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selectedModelId == null
                ? _emptyHint(Icons.inventory, 'اختر موديل لعرض التفاصيل')
                : ModelBuyersPanel(modelId: selectedModelId!, seasonId: seasonId),
          )
        ],
      );
    }

    // CLIENTS
    else {
      body = Row(
        children: [
          SidePanel(
            title: 'العملاء',
            topFilters: seasons.isNotEmpty
                ? DropdownButtonFormField<int?>(
                    value: seasonId,
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
                      ...seasons.map((s) => DropdownMenuItem<int?>(
                            value: s['id'] as int,
                            child: Text(s['name']),
                          ))
                    ],
                    onChanged: _onSeasonChanged,
                  )
                : null,
            list: loading
                ? const Center(child: CircularProgressIndicator())
                : clients.isEmpty
                    ? const Center(child: Text('لا يوجد عملاء'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: clients.length,
                        itemBuilder: (_, i) {
                          final c = clients[i];
                          final sel = c['id'] == selectedClientId;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            elevation: sel ? 4 : 1,
                            color: sel ? Colors.grey[100] : Colors.white,
                            child: ListTile(
                              selected: sel,
                              title: Text(
                                c['full_name'],
                                style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c['phone'] ?? ''),
                                  Text(c['address'] ?? '',
                                      style: TextStyle(color: Colors.teal[700])),
                                ],
                              ),
                              onTap: () => setState(() => selectedClientId = c['id']),
                            ),
                          );
                        },
                      ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selectedClientId == null
                ? _emptyHint(Icons.person, 'اختر عميل لعرض التفاصيل')
                : ClientDetailsTabs(clientId: selectedClientId!, seasonId: seasonId),
          )
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
                if (i != 0) selectedModelId = null;
                if (i != 1) selectedClientId = null;
              });
            },
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color baseColor) {
  // Safe tones for any Color
  Color dark(Color c)  => c is MaterialColor ? c.shade800 : c.withOpacity(.85);
  Color darker(Color c)=> c is MaterialColor ? c.shade900 : c.withOpacity(.95);

  return Expanded(
    child: Card(
      color: baseColor.withOpacity(.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: dark(baseColor),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: darker(baseColor),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}


  Widget _emptyHint(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(text, style: TextStyle(fontSize: 18, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

/// ===================== FACTURE DETAIL VIEW =====================
class _FactureDetailView extends StatelessWidget {
  final int factureId;
  const _FactureDetailView({required this.factureId});

  @override
  Widget build(BuildContext context) {
    final horizCtrl = ScrollController();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: FutureBuilder<Map<String, dynamic>>(
        future: http
            .get(Uri.parse('$kBaseUrl/factures/$factureId'))
            .then((r) => jsonDecode(r.body) as Map<String, dynamic>),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return Center(child: Text('خطأ: ${snap.error}'));
          }
          final d = snap.data!;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تفاصيل فاتورة رقم ${d['id']}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo[800],
                      ),
                ),
                const SizedBox(height: 24),

                // Info
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('معلومات الفاتورة',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800])),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text('التاريخ: ${fmtDate(d['facture_date'])}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.person,
                                size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text('العميل: ${d['client_name']}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.phone,
                                size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text('الهاتف: ${d['client_phone']}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text('العنوان: ${d['client_address']}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Payment
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('معلومات الدفع',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800])),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                                child: costItem('الإجمالي', d['total_amount'],
                                    Colors.green[700]!)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: costItem('المدفوع', d['total_paid'],
                                    Colors.blue[700]!)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                                child: costItem('المتبقي', d['remaining_amount'],
                                    Colors.orange[700]!)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: d['remaining_amount'] <= 0
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: (d['remaining_amount'] <= 0
                                              ? Colors.green
                                              : Colors.orange)
                                          .withOpacity(0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('الحالة',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: d['remaining_amount'] <= 0
                                                ? Colors.green[700]
                                                : Colors.orange[700])),
                                    Text(
                                      d['remaining_amount'] <= 0
                                          ? 'مدفوع بالكامل'
                                          : d['total_paid'] > 0
                                              ? 'مدفوع جزئياً'
                                              : 'غير مدفوع',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: d['remaining_amount'] <= 0
                                              ? Colors.green[700]
                                              : Colors.orange[700]),
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

                // Items
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('تفاصيل المنتجات',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800])),
                        const SizedBox(height: 16),
                        Scrollbar(
                          thumbVisibility: true,
                          controller: horizCtrl,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            controller: horizCtrl,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(
                                  Theme.of(context).colorScheme.primary),
                              headingTextStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                              columns: const [
                                DataColumn(label: Text('المنتج')),
                                DataColumn(label: Text('الكمية')),
                                DataColumn(label: Text('سعر البيع')),
                                DataColumn(label: Text('الإجمالي')),
                              ],
                              rows: (d['items'] as List).map<DataRow>((it) {
                                final qty = parseInt(it['quantity']);
                                final unit = parseNum(it['unit_price']);
                                return DataRow(cells: [
                                  DataCell(Text(it['model_name'] ?? '')),
                                  DataCell(Text(qty.toString())),
                                  DataCell(Text('${unit.toStringAsFixed(2)} دج')),
                                  DataCell(Text('${(qty * unit).toStringAsFixed(2)} دج')),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Payments list
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الدفعات',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800])),
                        const SizedBox(height: 8),
                        if (parseNum(d['amount_paid_on_creation']) > 0)
                          ListTile(
                            leading: const Icon(Icons.payment, color: Colors.green),
                            title: Text(
                                '${parseNum(d['amount_paid_on_creation']).toStringAsFixed(2)} دج'),
                            subtitle: Text(
                                'دفعة عند الإنشاء - تاريخ: ${fmtDate(d['facture_date'])}'),
                          ),
                        if (d['payments'] != null && (d['payments'] as List).isNotEmpty)
                          ...((d['payments'] as List).map<Widget>((p) => ListTile(
                                leading: const Icon(Icons.payment),
                                title: Text(
                                    '${parseNum(p['amount_paid']).toStringAsFixed(2)} دج'),
                                subtitle:
                                    Text('تاريخ: ${fmtDate(p['payment_date'])}'),
                              ))).toList()
                        else if (parseNum(d['amount_paid_on_creation']) == 0)
                          const Text('لا توجد دفعات')
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// ===================== MODEL BUYERS PANEL =====================
class ModelBuyersPanel extends StatefulWidget {
  final int modelId;
  final int? seasonId;
  const ModelBuyersPanel({super.key, required this.modelId, this.seasonId});

  @override
  State<ModelBuyersPanel> createState() => _ModelBuyersPanelState();
}

class _ModelBuyersPanelState extends State<ModelBuyersPanel> {
  bool loading = false;
  List<dynamic> buyers = [];

  final _hCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(ModelBuyersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelId != widget.modelId) _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      loading = true;
      buyers = [];
    });
    try {
      final r = await http.get(Uri.parse('$kBaseUrl/models/${widget.modelId}/clients'));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as List;
        buyers = data;
      }
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (buyers.isEmpty) {
      return _empty('لا يوجد عملاء اشتروا هذا الموديل', Icons.people_outline);
    }

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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                  Text(client['client_name'],
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue[800])),
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
                          color: Colors.grey[800]),
                    ),
                    const SizedBox(height: 8),
                    Scrollbar(
                      thumbVisibility: true,
                      controller: _hCtrl,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _hCtrl,
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
                                        '${(s['quantity'] * double.parse(s['unit_price'].toString())).toStringAsFixed(2)} دج')),
                                  ]))
                              .toList(),
                        ),
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

  Widget _empty(String msg, IconData ic) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ic, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(msg, style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          ],
        ),
      );
}

/// ===================== CLIENT DETAILS TABS =====================
class ClientDetailsTabs extends StatefulWidget {
  final int clientId;
  final int? seasonId;
  const ClientDetailsTabs({super.key, required this.clientId, this.seasonId});

  @override
  State<ClientDetailsTabs> createState() => _ClientDetailsTabsState();
}

class _ClientDetailsTabsState extends State<ClientDetailsTabs> {
  int tab = 0; // 0 factures, 1 account
  List<dynamic> factures = [];
  List<dynamic> transactions = [];
  Set<int> expandedIds = {};

  bool loadingFactures = false;
  bool loadingTx = false;

  DateTime? startDate;
  DateTime? endDate;

  final _txHorizCtrl = ScrollController();
  final _itemsHorizCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFactures();
    _loadTransactions();
  }

  @override
  void didUpdateWidget(ClientDetailsTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId) {
      _loadFactures();
      _loadTransactions();
      expandedIds.clear();
    }
  }

  Future<void> _loadFactures() async {
    loadingFactures = true;
    factures = [];
    setState(() {});
    try {
      final r = await http.get(Uri.parse('$kBaseUrl/clients/${widget.clientId}/factures'));
      if (r.statusCode == 200) {
        factures = jsonDecode(r.body);
      }
    } finally {
      loadingFactures = false;
      setState(() {});
    }
  }

  Future<void> _loadTransactions() async {
    loadingTx = true;
    transactions = [];
    setState(() {});
    try {
      String url = '$kBaseUrl/clients/${widget.clientId}/transactions';
      if (startDate != null && endDate != null) {
        final s = startDate!.toIso8601String().split('T')[0];
        final e = endDate!.toIso8601String().split('T')[0];
        url += '?start_date=$s&end_date=$e';
      }
      final r = await http.get(Uri.parse(url));
      if (r.statusCode == 200) {
        transactions = jsonDecode(r.body);
      }
    } finally {
      loadingTx = false;
      setState(() {});
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: (startDate != null && endDate != null)
          ? DateTimeRange(start: startDate!, end: endDate!)
          : null,
    );
    if (picked != null) {
      startDate = picked.start;
      endDate = picked.end;
      _loadTransactions();
    }
  }

  Future<void> _printTx() async {
    if (transactions.isEmpty) return;

    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansArabicRegular();

    pdf.addPage(
      pw.Page(
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('كشف حساب العميل',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, font: font)),
              if (startDate != null && endDate != null)
                pw.Text(
                  'من ${fmtDate(startDate!.toIso8601String())} إلى ${fmtDate(endDate!.toIso8601String())}',
                  style: pw.TextStyle(font: font),
                ),
              pw.SizedBox(height: 16),
              pw.Table.fromTextArray(
                context: context,
                headers: ['التاريخ', 'نوع العملية', 'رقم الفاتورة', 'المبلغ'],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
                cellStyle: pw.TextStyle(font: font),
                data: transactions.map((t) {
                  return [
                    fmtDate(t['date'].toString()),
                    t['label'].toString(),
                    t['facture_id']?.toString() ?? '-',
                    '${t['amount']} دج',
                  ];
                }).toList(),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat f) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.grey[100],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _chip('الفواتير', 0),
              const SizedBox(width: 8),
              _chip('الحساب', 1),
            ],
          ),
        ),
        Expanded(child: tab == 0 ? _facturesTab() : _accountTab()),
      ],
    );
  }

  Widget _chip(String lbl, int i) => ChoiceChip(
        label: Text(lbl),
        selected: tab == i,
        selectedColor: Theme.of(context).colorScheme.primary,
        labelStyle: TextStyle(
          color: tab == i ? Colors.white : null,
          fontWeight: FontWeight.bold,
        ),
        onSelected: (_) => setState(() => tab = i),
      );

  Widget _facturesTab() {
    if (loadingFactures) {
      return const Center(child: CircularProgressIndicator());
    }
    if (factures.isEmpty) {
      return _empty('لا توجد فواتير', Icons.receipt_outlined);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('فواتير العميل',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo[800],
                  )),
          const SizedBox(height: 16),
          ...factures.map((f) {
            final expanded = expandedIds.contains(f['id']);
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
                        'فاتورة ${f['id']}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800]),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 16, color: Colors.blue[600]),
                              const SizedBox(width: 4),
                              Text('التاريخ: ${fmtDate(f['facture_date'])}'),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                  child: costItem(
                                      'الإجمالي', f['total_amount'], Colors.green[700]!)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: costItem('المدفوع', f['total_paid'],
                                      Colors.blue[700]!)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: costItem('المتبقي', f['remaining_amount'],
                                      Colors.orange[700]!)),
                            ],
                          ),
                        ],
                      ),
                      trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                          color: expanded ? Colors.blue : Colors.grey),
                      onTap: () {
                        setState(() {
                          if (expanded) {
                            expandedIds.remove(f['id']);
                          } else {
                            expandedIds.add(f['id']);
                          }
                        });
                      },
                    ),
                  ),
                  if (expanded)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('تفاصيل المنتجات:',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800])),
                          const SizedBox(height: 8),
                          Scrollbar(
                            thumbVisibility: true,
                            controller: _itemsHorizCtrl,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              controller: _itemsHorizCtrl,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                    Theme.of(context).colorScheme.primary),
                                headingTextStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                                columns: const [
                                  DataColumn(label: Text('المنتج')),
                                  DataColumn(label: Text('الكمية')),
                                  DataColumn(label: Text('سعر البيع')),
                                  DataColumn(label: Text('الإجمالي')),
                                ],
                                rows: (f['items'] as List)
                                    .map<DataRow>((it) => DataRow(cells: [
                                          DataCell(Text(it['model_name'] ?? '')),
                                          DataCell(Text(it['quantity'].toString())),
                                          DataCell(Text(
                                              '${parseNum(it['unit_price']).toStringAsFixed(2)} دج')),
                                          DataCell(Text(
                                              '${parseNum(it['line_total']).toStringAsFixed(2)} دج')),
                                        ]))
                                    .toList(),
                              ),
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

  Widget _accountTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
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
                      onPressed: _pickRange,
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
                        _loadTransactions();
                      },
                      child: const Text('إزالة التصفية'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (transactions.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.print, color: Colors.white),
                    label: const Text('طباعة', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _printTx,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: loadingTx
              ? const Center(child: CircularProgressIndicator())
              : transactions.isEmpty
                  ? _empty('لا يوجد بيانات حساب', Icons.account_balance_outlined)
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المعاملات المالية',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo[800])),
                          const SizedBox(height: 16),
                          Card(
                            child: Scrollbar(
                              thumbVisibility: true,
                              controller: _txHorizCtrl,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                controller: _txHorizCtrl,
                                child: DataTable(
                                  headingRowColor: MaterialStateProperty.all(
                                      Theme.of(context).colorScheme.primary),
                                  headingTextStyle: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                  columns: const [
                                    DataColumn(label: Text('التاريخ')),
                                    DataColumn(label: Text('نوع العملية')),
                                    DataColumn(label: Text('رقم الفاتورة')),
                                    DataColumn(label: Text('المبلغ')),
                                  ],
                                  rows: transactions
                                      .map<DataRow>((e) => DataRow(cells: [
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
                                          ]))
                                      .toList(),
                                ),
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

  Widget _empty(String text, IconData icon) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(text, style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          ],
        ),
      );
}
