import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../main.dart';

// >>> Added to match Sewing's print/export capabilities
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'dart:io' as io;

/// ===================== CONFIG =====================
String get kBaseUrl => '${globalServerUri.toString()}/embrodry/sales';

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
        Text(label,
            style: TextStyle(
                fontSize: isTotal ? 14 : 12,
                color: color,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
        Text('${numVal.toStringAsFixed(2)} دج',
            style: TextStyle(
                fontSize: isTotal ? 18 : 16,
                color: color,
                fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

/// ===================== SHARED =====================
class TabHeader extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;
  const TabHeader(
      {super.key,
      required this.tabs,
      required this.selected,
      required this.onChanged});

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
              labelStyle:
                  TextStyle(color: sel ? Colors.white : null, fontWeight: FontWeight.bold),
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
                Text(title,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
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
class EmbroiderySalesSection extends StatefulWidget {
  const EmbroiderySalesSection({Key? key}) : super(key: key);

  @override
  State<EmbroiderySalesSection> createState() => _EmbroiderySalesSectionState();
}

class _EmbroiderySalesSectionState extends State<EmbroiderySalesSection> {
  int selectedTab = 2; // 0=Models, 1=Clients, 2=Factures

  List<Map<String, dynamic>> seasons = [];
  List<Map<String, dynamic>> models = [];
  List<Map<String, dynamic>> clients = [];
  List<Map<String, dynamic>> factures = [];
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
      showSnack(context, 'خطأ في تحميل: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _fetchSeasons() async {
    try {
      final r = await http.get(Uri.parse('$kBaseUrl/seasons'));
      if (r.statusCode == 200) seasons = List<Map<String, dynamic>>.from(jsonDecode(r.body));
    } catch (_) {
      seasons = [];
    }
  }

  Future<void> _fetchModels() async {
    String url = '$kBaseUrl/models';
    if (seasonId != null) url = '$kBaseUrl/models/by_season/$seasonId';
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw Exception('models ${r.statusCode}');
    models = List<Map<String, dynamic>>.from(jsonDecode(r.body));
  }

  Future<void> _fetchClients() async {
    String url = '$kBaseUrl/clients';
    if (seasonId != null) url = '$kBaseUrl/clients/by_season/$seasonId';
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw Exception('clients ${r.statusCode}');
    clients = List<Map<String, dynamic>>.from(jsonDecode(r.body));
  }

  Future<void> _fetchFactures() async {
    String url = '$kBaseUrl/factures';
    if (seasonId != null) url = '$kBaseUrl/factures/by_season/$seasonId';
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw Exception('factures ${r.statusCode}');
    factures = List<Map<String, dynamic>>.from(jsonDecode(r.body));
    if (factures.isNotEmpty) {
      selectedFactureId ??= factures.first['id'];
      if (!factures.any((f) => f['id'] == selectedFactureId)) {
        selectedFactureId = factures.first['id'];
      }
    } else {
      selectedFactureId = null;
    }
  }

  Future<void> _fetchSummary() async {
    try {
      final r = await http.get(Uri.parse('$kBaseUrl/factures/summary'));
      if (r.statusCode == 200) facturesSummary = jsonDecode(r.body);
    } catch (_) {
      facturesSummary = null;
    }
  }

  Future<void> _onSeasonChanged(int? v) async {
    setState(() => seasonId = v);
    await Future.wait([
      _fetchModels(),
      _fetchClients(),
      _fetchFactures(),
      _fetchSummary(),
    ]);
    setState(() {});
  }

  Future<void> _deleteFacture(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الفاتورة'),
        content: Text('هل تريد حذف الفاتورة ${f['id']}؟'),
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
      showSnack(context, 'فشل: ${r.body}', color: Colors.red);
    }
  }

  void _showModelImagePopup(String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.network(
            '${globalServerUri.toString()}$imageUrl',
            fit: BoxFit.contain,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (ctx, err, st) => const Center(
              child: Icon(Icons.broken_image, size: 64),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addFactureDialog() async {
    int? clientId;
    String payType = 'debt';
    double paidOnCreation = 0.0;
    final amountCtrl = TextEditingController();
    final items = <Map<String, dynamic>>[];
    DateTime fDate = DateTime.now();

    double getTotal() => items.fold<double>(
          0,
          (sum, it) {
            final qty = it['quantity'] as int;
            final pricePerStitch = it['unit_price'] as double;
            final stitches = it['stitch_number'] as int;
            return sum + qty * pricePerStitch * stitches;
          },
        );

    // INNER DIALOG TO ADD A PRODUCT
    Future<void> addItem(StateSetter setOuter) async {
      int? modelId;
      final qtyCtrl = TextEditingController();

      final availModels = models.where((m) => parseInt(m['available_quantity']) > 0).toList();
      if (availModels.isEmpty) {
        showSnack(context, 'لا يوجد مخزون', color: Colors.orange);
        return;
      }

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx2, setDialog) {
            final prod = availModels.firstWhere(
              (m) => m['id'] == modelId,
              orElse: () => <String, dynamic>{},
            );
            final avail = parseInt(prod['available_quantity'] ?? 0);

            return AlertDialog(
              title: const Text('إضافة منتج'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Autocomplete<Map<String, dynamic>>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        final query = textEditingValue.text.toLowerCase();
                        return availModels.where((m) {
                          final name = m['model_name'].toString().toLowerCase();
                          return name.contains(query);
                        }).toList();
                      },
                      displayStringForOption: (option) =>
                          '${option['model_name']} (متاح: ${option['available_quantity']}, سعر الغرزة: ${option['stitch_price']})',
                      fieldViewBuilder: (
                        BuildContext context,
                        TextEditingController textEditingController,
                        FocusNode focusNode,
                        VoidCallback onFieldSubmitted,
                      ) {
                        return TextField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'اختر الموديل',
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (textEditingController.text.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      textEditingController.clear();
                                      setDialog(() => modelId = null);
                                    },
                                  ),
                                if (modelId != null)
                                  IconButton(
                                    icon: const Icon(Icons.image, color: Colors.blue),
                                    onPressed: () {
                                      final selectedModel = availModels.firstWhere(
                                        (m) => m['id'] == modelId,
                                        orElse: () => {},
                                      );
                                      final imageUrl = selectedModel['image_url'] as String?;
                                      if (imageUrl != null && imageUrl.isNotEmpty) {
                                        _showModelImagePopup(imageUrl);
                                      } else {
                                        showSnack(context, 'لا توجد صورة');
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                      onSelected: (Map<String, dynamic> option) {
                        setDialog(() => modelId = option['id'] as int);
                      },
                      optionsViewBuilder: (
                        BuildContext context,
                        AutocompleteOnSelected<Map<String, dynamic>> onSelected,
                        Iterable<Map<String, dynamic>> options,
                      ) {
                        return Align(
                          alignment: Alignment.topRight,
                          child: Material(
                            elevation: 4.0,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final option = options.elementAt(index);
                                  final imageUrl = option['image_url'] as String?;
                                  return GestureDetector(
                                    onTap: () => onSelected(option),
                                    child: ListTile(
                                      leading: (imageUrl != null && imageUrl.isNotEmpty)
                                          ? GestureDetector(
                                              onTap: () => _showModelImagePopup(imageUrl),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(4),
                                                child: Image.network(
                                                  '${globalServerUri.toString()}$imageUrl',
                                                  width: 40,
                                                  height: 40,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const Icon(Icons.image_not_supported),
                                                ),
                                              ),
                                            )
                                          : const Icon(Icons.image, size: 40, color: Colors.grey),
                                      title: Text(
                                        '${option['model_name']} (متاح: ${option['available_quantity']}, سعر الغرزة: ${option['stitch_price']})',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: qtyCtrl,
                      decoration: InputDecoration(
                        labelText: prod.isEmpty ? 'الكمية' : 'الكمية (حد أقصى: $avail)',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (modelId == null) {
                      showSnack(context, 'اختر الموديل');
                      return;
                    }
                    final q = int.tryParse(qtyCtrl.text) ?? 0;
                    if (q <= 0) {
                      showSnack(context, 'أدخل كمية صحيحة');
                      return;
                    }
                    if (q > avail) {
                      showSnack(context, 'الكمية أكبر من $avail');
                      return;
                    }

                    final unitPrice = parseNum(prod['stitch_price']);
                    final idx = items.indexWhere((i) => i['model_id'] == modelId);
                    if (idx != -1) {
                      items[idx]['quantity'] = q;
                    } else {
                      items.add({
                        'model_id': modelId,
                        'model_name': prod['model_name'],
                        'quantity': q,
                        'unit_price': unitPrice,
                        'stitch_number': prod['stitch_number'],
                        'image_url': prod['image_url'],
                      });
                    }
                    setState(() {}); // refresh parent dialog state
                    Navigator.pop(ctx2);
                  },
                  child: const Text('إضافة'),
                ),
              ],
            );
          },
        ),
      );
    }

    // MAIN FACTURE DIALOG
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
        return AlertDialog(
          title: const Text('فاتورة جديدة'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Date picker
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(children: [
                        Text('تاريخ: ${fDate.toLocal().toString().split(' ')[0]}'),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx2,
                              initialDate: fDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setD(() => fDate = picked);
                            }
                          },
                          child: const Text('تغيير'),
                        )
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Client dropdown
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'اختر العميل'),
                    value: clientId,
                    items: clients.map((c) {
                      return DropdownMenuItem<int>(
                        value: c['id'] as int,
                        child: Text(c['full_name']),
                      );
                    }).toList(),
                    onChanged: (v) => setD(() => clientId = v),
                    validator: (v) => v == null ? 'اختر العميل' : null,
                  ),
                  const SizedBox(height: 8),

                  // Items list
                  if (items.isNotEmpty)
                    Card(
                      color: Colors.grey[50],
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('المنتجات',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('الإجمالي: ${getTotal().toStringAsFixed(2)} دج',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                          const Divider(),
                          ...items.asMap().entries.map((e) {
                            final idx = e.key;
                            final it = e.value;
                            final imageUrl = it['image_url'] as String?;
                            return ListTile(
                              leading: (imageUrl != null && imageUrl.isNotEmpty)
                                  ? GestureDetector(
                                      onTap: () => _showModelImagePopup(imageUrl),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.network(
                                          '${globalServerUri.toString()}$imageUrl',
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.image_not_supported),
                                        ),
                                      ),
                                    )
                                  : const Icon(Icons.image, size: 40, color: Colors.grey),
                              title: Text(it['model_name']),
                              subtitle: Text(
                                  '${it['quantity']} * ${it['unit_price'].toStringAsFixed(2)} دج/غرزة'
                                  ' * ${it['stitch_number']} غرز'
                                  ' = ${(it['quantity'] * it['unit_price'] * it['stitch_number']).toStringAsFixed(2)} دج'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => setD(() => items.removeAt(idx)),
                              ),
                            );
                          }).toList(),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Add item button
                  Row(children: [
                    Text('عدد المنتجات: ${items.length}'),
                    const Spacer(),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة منتج'),
                      onPressed: () => addItem(setD),
                    )
                  ]),
                  const Divider(),

                  // Total display
                  Text('الإجمالي: ${getTotal().toStringAsFixed(2)} دج',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  // Payment type radios
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

                  // Amount-on-creation if cash
                  if (payType == 'cash')
                    TextFormField(
                      controller: amountCtrl,
                      decoration: InputDecoration(
                        labelText: 'دفعة أولى (حد أقصى: ${getTotal().toStringAsFixed(2)})',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final a = double.tryParse(v ?? '') ?? 0.0;
                        if (a < 0 || a > getTotal()) {
                          return 'الدفعة يجب أن تكون بين 0 و ${getTotal().toStringAsFixed(2)}';
                        }
                        return null;
                      },
                      onChanged: (v) {
                        final a = double.tryParse(v) ?? 0.0;
                        paidOnCreation = a > getTotal() ? getTotal() : a;
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (clientId == null) {
                  showSnack(context, 'اختر العميل', color: Colors.red);
                  return;
                }
                if (items.isEmpty) {
                  showSnack(context, 'أضف منتجًا واحدًا على الأقل', color: Colors.red);
                  return;
                }
                final tot = getTotal();
                if (payType == 'cash' && (double.tryParse(amountCtrl.text) ?? 0) > tot) {
                  showSnack(context, 'الدفعة الأولى لا يمكن أن تكون أكبر من الإجمالي',
                      color: Colors.red);
                  return;
                }
                final payload = {
                  'client_id': clientId,
                  'facture_date': fDate.toIso8601String().split('T')[0],
                  'total_amount': tot,
                  'amount_paid_on_creation': payType == 'cash' ? paidOnCreation : 0.0,
                  'items': items
                      .map((e) => {
                            'model_id': e['model_id'],
                            'quantity': e['quantity'],
                            'unit_price': e['unit_price'],
                          })
                      .toList(),
                };
                try {
                  final r = await http.post(
                    Uri.parse('$kBaseUrl/factures'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  );
                  if (r.statusCode == 201) {
                    showSnack(context, 'تمت الإضافة', color: Colors.green);
                    Navigator.pop(ctx2);
                    await _fetchFactures();
                    await _fetchSummary();
                    setState(() {});
                  } else {
                    showSnack(context, 'فشل: ${r.body}', color: Colors.red);
                  }
                } catch (e) {
                  showSnack(context, 'خطأ اتصال: $e', color: Colors.red);
                }
              },
              child: const Text('حفظ'),
            )
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (selectedTab == 2) {
      // FACTURES TAB
      body = Column(
        children: [
          Expanded(
            child: Row(children: [
              SidePanel(
                title: 'فواتير المخيَّط',
                topFilters: Column(children: [
                  if (seasons.isNotEmpty)
                    DropdownButtonFormField<int?>(
                      value: seasonId,
                      decoration: const InputDecoration(
                        labelText: 'حسب الموسم',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('جميع المواسم')),
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
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed:
                          (models.isNotEmpty && clients.isNotEmpty) ? _addFactureDialog : null,
                    ),
                  ),
                ]),
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
                                  title: Text('فاتورة ${f['id']}',
                                      style: TextStyle(
                                          fontWeight: sel
                                              ? FontWeight.bold
                                              : FontWeight.normal)),
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
                                          style: TextStyle(color: Colors.red[700])),
                                    ],
                                  ),
                                  onTap: () =>
                                      setState(() => selectedFactureId = f['id']),
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
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('اختر فاتورة',
                                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                          ],
                        ),
                      )
                    : _FactureDetailView(factureId: selectedFactureId!),
              )
            ]),
          ),
        ],
      );
    } else if (selectedTab == 0) {
      // MODELS TAB
      body = Row(children: [
        SidePanel(
          title: 'الموديلات',
          topFilters: seasons.isNotEmpty
              ? DropdownButtonFormField<int?>(
                  value: seasonId,
                  decoration: const InputDecoration(
                    labelText: 'حسب الموسم',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('جميع المواسم')),
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
                        final imageUrl = m['image_url'] as String?;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          elevation: sel ? 4 : 1,
                          color: sel ? Colors.grey[100] : Colors.white,
                          child: ListTile(
                            leading: (imageUrl != null && imageUrl.isNotEmpty)
                                ? GestureDetector(
                                    onTap: () => _showModelImagePopup(imageUrl),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        '${globalServerUri.toString()}$imageUrl',
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.broken_image),
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.image, size: 40, color: Colors.grey),
                            selected: sel,
                            title: Text(m['model_name'],
                                style: TextStyle(
                                    fontWeight:
                                        sel ? FontWeight.bold : FontWeight.normal)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('متاح: ${m['available_quantity']}'),
                                Text(
                                    'سعر الغرزة: ${parseNum(m['stitch_price']).toStringAsFixed(2)} دج'),
                                Text('عدد الغرز: ${m['stitch_number']}'),
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
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('اختر موديل',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                    ],
                  ),
                )
              : ModelBuyersPanel(modelId: selectedModelId!, seasonId: seasonId),
        )
      ]);
    } else {
      // CLIENTS TAB
      body = Row(children: [
        SidePanel(
          title: 'العملاء',
          topFilters: seasons.isNotEmpty
              ? DropdownButtonFormField<int?>(
                  value: seasonId,
                  decoration: const InputDecoration(
                    labelText: 'حسب الموسم',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('جميع المواسم')),
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
                            title: Text(c['full_name'],
                                style: TextStyle(
                                    fontWeight:
                                        sel ? FontWeight.bold : FontWeight.normal)),
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
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'اختر عميل',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              // >>> Replaced with the new (Sewing-like) implementation
              : ClientDetailsTabs(clientId: selectedClientId!, seasonId: seasonId),
        )
      ]);
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(children: [
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
      ]),
    );
  }
}

/// ==================== Facture Detail & Model/Client Panels ====================
/// ===================== FACTURE DETAIL VIEW =====================
class _FactureDetailView extends StatelessWidget {
  final int factureId;
  const _FactureDetailView({super.key, required this.factureId});

  void _showModelImagePopup(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.network(
            '${globalServerUri.toString()}$imageUrl',
            fit: BoxFit.contain,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (ctx, err, st) => const Center(
              child: Icon(Icons.broken_image, size: 64),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printFacture(Map<String, dynamic> facture) async {
  // ========= Fonts =========
  final arabicData = await rootBundle.load('assets/fonts/NotoSansArabic_Condensed-Black.ttf');
  final latinData  = await rootBundle.load('assets/fonts/Roboto_Condensed-Black.ttf');
  final arabicFont = pw.Font.ttf(arabicData);
  final latinFont  = pw.Font.ttf(latinData);

  // ========= Helpers =========
  String _s(dynamic v) => v == null ? '' : v.toString();

  num _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  // Western digits: 0 decimals if integer, else 2 decimals (like Sewing)
  String _dz(num v) {
    final hasFraction = (v % 1) != 0;
    final s = hasFraction ? v.toStringAsFixed(2) : v.toStringAsFixed(0);
    return '$s دج';
  }

  List<List<T>> _chunk<T>(List<T> list, int size) {
    if (list.isEmpty) return const [];
    final out = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      out.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return out;
  }

  // Arabic amount-in-words, same as Sewing
  String _intToArabicWords(int n) {
    if (n == 0) return 'صفر';
    if (n < 0) return 'سالب ${_intToArabicWords(-n)}';

    const units = [
      'صفر','واحد','اثنان','ثلاثة','أربعة','خمسة','ستة','سبعة','ثمانية','تسعة',
      'عشرة','أحد عشر','اثنا عشر','ثلاثة عشر','أربعة عشر','خمسة عشر','ستة عشر',
      'سبعة عشر','ثمانية عشر','تسعة عشر'
    ];
    const tensMap = {20:'عشرون',30:'ثلاثون',40:'أربعون',50:'خمسون',60:'ستون',70:'سبعون',80:'ثمانون',90:'تسعون'};
    const hundredsMap = {
      1:'مائة',2:'مائتان',3:'ثلاثمائة',4:'أربعمائة',5:'خمسمائة',
      6:'ستمائة',7:'سبعمائة',8:'ثمانمائة',9:'تسعمائة'
    };

    String below100(int x) {
      if (x < 20) return units[x];
      final t = (x ~/ 10) * 10;
      final r = x % 10;
      if (r == 0) return tensMap[t]!;
      return '${units[r]} و ${tensMap[t]}';
    }

    String below1000(int x) {
      final h = x ~/ 100;
      final r = x % 100;
      String res = '';
      if (h > 0) res = hundredsMap[h]!;
      if (r > 0) {
        if (res.isNotEmpty) res += ' و ';
        res += below100(r);
      }
      return res.isNotEmpty ? res : 'صفر';
    }

    final millions = n ~/ 1000000;
    final thousands = (n % 1000000) ~/ 1000;
    final rest = n % 1000;

    final parts = <String>[];
    if (millions > 0) {
      if (millions == 1) parts.add('مليون');
      else if (millions == 2) parts.add('مليونان');
      else if (millions <= 10) parts.add('${below1000(millions)} ملايين');
      else parts.add('${below1000(millions)} مليون');
    }
    if (thousands > 0) {
      if (thousands == 1) parts.add('ألف');
      else if (thousands == 2) parts.add('ألفان');
      else if (thousands <= 10) parts.add('${below1000(thousands)} آلاف');
      else parts.add('${below1000(thousands)} ألف');
    }
    if (rest > 0) parts.add(below1000(rest));
    return parts.join(' و ');
  }

  String _currencyForm(int n, String singular, String dual, String plural) {
    if (n == 1) return singular;
    if (n == 2) return dual;
    return plural;
  }

  String _toArabicAmountWords(num amount) {
    final dinars = amount.floor();
    final cents  = ((amount - dinars) * 100).round();

    final wordsDinars = _intToArabicWords(dinars);
    final formDinars  = _currencyForm(dinars, 'دينار جزائري', 'ديناران جزائريان', 'دنانير جزائرية');

    String res = '$wordsDinars $formDinars';
    if (cents > 0) {
      final wordsCents = _intToArabicWords(cents);
      final formCents  = _currencyForm(cents, 'سنتيم', 'سنتيمان', 'سنتيمات');
      res += ' و $wordsCents $formCents';
    }
    return res;
  }

  pw.Widget _kvRowAr(pw.Font ar, pw.Font lat, String key, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey700, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(key,   style: pw.TextStyle(font: ar, fontSize: 11, fontFallback: [lat])),
          pw.Text(value, style: pw.TextStyle(font: ar, fontSize: 11, fontFallback: [lat])),
        ],
      ),
    );
  }

  // ========= Facture data =========
  final items      = (facture['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final total      = _num(facture['total_amount']);     // invoice total
  final totalPaid  = _num(facture['total_paid']);       // paid on this invoice
  final remaining  = _num(facture['remaining_amount']); // remaining on this invoice

  final clientName    = _s(facture['client_name']);
  final clientAddress = _s(facture['client_address']);
  final clientPhone   = _s(facture['client_phone']);
  final fDateStr      = facture['facture_date']?.toString();

  // ========= clientId (Embroidery) =========
  int? clientId;
  try {
    clientId = (facture['client_id'] as num?)?.toInt();
  } catch (_) {
    clientId = null;
  }

  // ========= Global remaining (for the client) =========
  num globalRemaining = remaining; // fallback
  try {
    if (clientId != null) {
      final resp = await http.get(
        Uri.parse('${globalServerUri.toString()}/embrodry/sales/clients/$clientId/account'),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final summary = (data['summary'] as Map?) ?? {};
        globalRemaining = _num(summary['remaining']);
      }
    }
  } catch (_) {/* keep fallback */}

  final oldDebtNow  = (globalRemaining - remaining) > 0 ? (globalRemaining - remaining) : 0;
  final grandTotal  = oldDebtNow + total;
  final totalWords  = _toArabicAmountWords(total);

  // ========= Styles =========
  final headerTitle   = pw.TextStyle(font: arabicFont, fontSize: 18, fontWeight: pw.FontWeight.bold, fontFallback: [latinFont]);
  final headerBrand   = pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold, fontFallback: [latinFont]);
  final headerAddr    = pw.TextStyle(font: arabicFont, fontSize: 10, fontFallback: [latinFont]);
  final h1            = pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold, fontFallback: [latinFont]);
  final label         = pw.TextStyle(font: arabicFont, fontSize: 11, fontFallback: [latinFont]);
  final labelB        = pw.TextStyle(font: arabicFont, fontSize: 11, fontWeight: pw.FontWeight.bold, fontFallback: [latinFont]);
  final thStyle       = pw.TextStyle(font: arabicFont, fontSize: 11, fontWeight: pw.FontWeight.bold, fontFallback: [latinFont]);
  final tdStyle       = pw.TextStyle(font: arabicFont, fontSize: 10, fontFallback: [latinFont]);

  final pdf = pw.Document();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,   // edge-to-edge header (same as Sewing)
      build: (ctx) {
        final body = <pw.Widget>[];

        // ======= Company header (RTL, full width) =======
        body.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1)),
            ),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('الإنتاج الصناعي للملابس', style: headerTitle),
                  pw.SizedBox(height: 2),
                  pw.Text('HALA MOD', style: headerBrand),
                  pw.SizedBox(height: 4),
                  pw.Text('العنوان: LOCAL N°03 SEC 05 GRP N°21 OULED MOUSSA BOUMERDES', style: headerAddr),
                ],
              ),
            ),
          ),
        );

        // ======= Content =======
        body.add(
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(24, 10, 24, 24),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Invoice id & date (date via fmtDate to drop 00:00:00.000Z)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('فاتورة رقم ${_s(facture['id'])}', style: h1),
                      pw.Text('التاريخ: ${fDateStr == null ? '' : fmtDate(fDateStr)}', style: labelB),
                    ],
                  ),
                  pw.SizedBox(height: 8),

                  // Client card
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Row(
                          children: [
                            pw.Expanded(
                              flex: 2,
                              child: pw.Container(
                                padding: const pw.EdgeInsets.all(8),
                                decoration: pw.BoxDecoration(
                                  border: pw.Border(
                                    left: pw.BorderSide(color: PdfColors.grey700, width: 0.8),
                                  ),
                                ),
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text('العميل', style: labelB),
                                    pw.SizedBox(height: 2),
                                    pw.Text(clientName, style: label),
                                  ],
                                ),
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Container(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text('الهاتف', style: labelB),
                                    pw.SizedBox(height: 2),
                                    pw.Text(clientPhone, style: label),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        pw.Container(height: 0.8, color: PdfColors.grey700),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('العنوان', style: labelB),
                              pw.SizedBox(height: 2),
                              pw.Text(clientAddress, style: label),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 12),

                  // ===== Items table (identical to Sewing): amount | unit | qty | product (RTL, right-aligned)
                  () {
                    final headers = ['المبلغ', 'سعر الوحدة', 'الكمية', 'المنتج'];
                    final rows = items.map((it) {
                      final q  = _num(it['quantity']);
                      final pu = _num(it['unit_price']);
                      final mt = _num(it['line_total']) == 0 ? q * pu : _num(it['line_total']);
                      return [
                        _dz(mt),
                        _dz(pu),
                        q % 1 == 0 ? q.toInt().toString() : q.toString(),
                        _s(it['model_name'] ?? ''),
                      ];
                    }).toList();

                    const rowsPerChunk = 35;
                    final chunks = _chunk(rows, rowsPerChunk);
                    final widgets = <pw.Widget>[];

                    if (chunks.isEmpty) {
                      widgets.add(
                        pw.Table.fromTextArray(
                          context: ctx,
                          headers: headers,
                          data: const <List<String>>[],
                          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                          border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
                          headerStyle: thStyle,
                          cellStyle: tdStyle,
                          columnWidths: const {
                            0: pw.FlexColumnWidth(3), // amount
                            1: pw.FlexColumnWidth(3), // unit
                            2: pw.FlexColumnWidth(2), // qty
                            3: pw.FlexColumnWidth(6), // product
                          },
                          cellAlignments: const {
                            0: pw.Alignment.centerRight,
                            1: pw.Alignment.centerRight,
                            2: pw.Alignment.centerRight,
                            3: pw.Alignment.centerRight,
                          },
                        ),
                      );
                    } else {
                      for (var i = 0; i < chunks.length; i++) {
                        widgets.add(
                          pw.Table.fromTextArray(
                            context: ctx,
                            headers: headers,
                            data: chunks[i],
                            tableWidth: pw.TableWidth.max,
                            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
                            headerStyle: thStyle,
                            cellStyle: tdStyle,
                            columnWidths: const {
                              0: pw.FlexColumnWidth(3),
                              1: pw.FlexColumnWidth(3),
                              2: pw.FlexColumnWidth(2),
                              3: pw.FlexColumnWidth(6),
                            },
                            cellAlignments: const {
                              0: pw.Alignment.centerRight,
                              1: pw.Alignment.centerRight,
                              2: pw.Alignment.centerRight,
                              3: pw.Alignment.centerRight,
                            },
                          ),
                        );
                        if (i != chunks.length - 1) widgets.add(pw.SizedBox(height: 6));
                      }
                    }
                    return pw.Column(children: widgets);
                  }(),

                  pw.SizedBox(height: 10),

                  // ===== Totals (5 lines)
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Container(
                      width: 320,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey700, width: 0.6),
                      ),
                      child: pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          _kvRowAr(arabicFont, latinFont, 'إجمالي الفاتورة', _dz(total)),
                          _kvRowAr(arabicFont, latinFont, 'الإجمالي',           _dz(grandTotal)),
                          _kvRowAr(arabicFont, latinFont, 'المدفوع',            _dz(totalPaid)),
                          _kvRowAr(arabicFont, latinFont, 'المتبقي',            _dz(remaining)),
                          _kvRowAr(arabicFont, latinFont, 'المتبقي الإجمالي',   _dz(globalRemaining)),
                        ],
                      ),
                    ),
                  ),

                  pw.SizedBox(height: 10),

                  // ===== Amount in words
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey700, width: 0.6),
                      color: PdfColors.grey200,
                    ),
                    child: pw.Text(
                      'هذه الفاتورة مقفلة على مبلغ: $totalWords (${_dz(total)}).',
                      style: label,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        return body;
      },
    ),
  );

  // ========= Save =========
  final bytes = await pdf.save();
  final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'اختر مجلد الحفظ');
  if (dir != null) {
    final path = '$dir/فاتورة_${_s(facture['id'])}.pdf';
    await io.File(path).writeAsBytes(bytes);
  }
}


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
                            const Icon(Icons.calendar_today, size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text('التاريخ: ${fmtDate(d['facture_date'])}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.person, size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text('العميل: ${d['client_name']}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.phone, size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text('الهاتف: ${d['client_phone']}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text('العنوان: ${d['client_address']}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                                child: costItem(
                                    'الإجمالي', d['total_amount'], Colors.green[700]!)),
                            const SizedBox(width: 8),
                            Expanded(
                                child:
                                    costItem('المدفوع', d['total_paid'], Colors.blue[700]!)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                                child: costItem(
                                    'المتبقي', d['remaining_amount'], Colors.orange[700]!)),
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
                                  color: Colors.white, fontWeight: FontWeight.bold),
                              columns: [
                                const DataColumn(label: Text('صورة')),
                                const DataColumn(label: Text('المنتج')),
                                const DataColumn(label: Text('النوع')),
                                const DataColumn(label: Text('عدد الغرز')),
                                const DataColumn(label: Text('سعر الغرزة')),
                                const DataColumn(label: Text('الكمية')),
                                const DataColumn(label: Text('الإجمالي')),
                              ],
                              rows: (d['items'] as List).map<DataRow>((it) {
                                final qty = parseInt(it['quantity']);
                                final price = parseNum(it['unit_price']);
                                final snum = it['stitch_number'] ?? '';
                                final mtype = it['model_type'] ?? '';
                                final stitches = parseInt(it['stitch_number']);
                                final imageUrl = it['image_url'] as String?;
                                return DataRow(cells: [
                                  DataCell(
                                    (imageUrl != null && imageUrl.isNotEmpty)
                                        ? GestureDetector(
                                            onTap: () => _showModelImagePopup(context, imageUrl),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: Image.network(
                                                '${globalServerUri.toString()}$imageUrl',
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(Icons.image_not_supported),
                                              ),
                                            ),
                                          )
                                        : const Icon(Icons.image,
                                            size: 40, color: Colors.grey),
                                  ),
                                  DataCell(Text(it['model_name'] ?? '')),
                                  DataCell(Text(mtype.toString())),
                                  DataCell(Text(snum.toString())),
                                  DataCell(Text('${price.toStringAsFixed(2)} دج')),
                                  DataCell(Text(qty.toString())),
                                  DataCell(Text(
                                      '${(qty * price * stitches).toStringAsFixed(2)} دج')),
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
                if (d['returns'] != null && (d['returns'] as List).isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المرتجعات',
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
                              headingRowColor: MaterialStateProperty.all(
                                  Theme.of(context).colorScheme.primary),
                              headingTextStyle: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold),
                              columns: const [
                                DataColumn(label: Text('المنتج')),
                                DataColumn(label: Text('الكمية')),
                                DataColumn(label: Text('تاريخ الإرجاع')),
                                DataColumn(label: Text('ملاحظات')),
                              ],
                              rows: (d['returns'] as List)
                                  .map<DataRow>((r) => DataRow(cells: [
                                        DataCell(Text(r['model_name'] ?? '')),
                                        DataCell(Text('${r['quantity'] ?? 0}')),
                                        DataCell(Text(fmtDate(r['return_date']))),
                                        DataCell(Text(r['notes'] ?? '')),
                                      ]))
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.print),
                      label: const Text('طباعة الفاتورة'),
                      onPressed: () => _printFacture(d),
                    ),
                  ],
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
      final r =
          await http.get(Uri.parse('$kBaseUrl/models/${widget.modelId}/clients'));
      if (r.statusCode == 200) buyers = jsonDecode(r.body);
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (buyers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('لا يوجد عملاء اشتروا هذا الموديل',
                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          ],
        ),
      );
    }

    final byClient = <int, List<Map<String, dynamic>>>{};
    for (var b in buyers) {
      final cid = b['client_id'] as int;
      byClient.putIfAbsent(cid, () => []).add(Map.from(b));
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
                                      Icon(Icons.location_on,
                                          size: 16, color: Colors.blue[600]),
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
                      'سجلات بيع هذا الموديل:',
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
                            DataColumn(label: Text('المنتج')),
                            DataColumn(label: Text('النوع')),
                            DataColumn(label: Text('عدد الغرز')),
                            DataColumn(label: Text('سعر الغرزة')),
                            DataColumn(label: Text('الكمية')),
                            DataColumn(label: Text('الإجمالي')),
                            DataColumn(label: Text('تاريخ الفاتورة')),
                            DataColumn(label: Text('رقم الفاتورة')),
                          ],
                          rows: sales.map<DataRow>((s) {
                            final qty = parseInt(s['quantity']);
                            final price = parseNum(s['unit_price']);
                            final snum = s['stitch_number'] ?? '';
                            final mtype = s['model_type'] ?? '';
                            final stitches = parseInt(s['stitch_number']);
                            return DataRow(cells: [
                              DataCell(Text(s['model_name'] ?? '')),
                              DataCell(Text(mtype.toString())),
                              DataCell(Text(snum.toString())),
                              DataCell(Text('${price.toStringAsFixed(2)} دج')),
                              DataCell(Text(qty.toString())),
                              DataCell(Text(
                                  '${(qty * price * stitches).toStringAsFixed(2)} دج')),
                              DataCell(Text(fmtDate(s['facture_date']))),
                              DataCell(Text(s['facture_id'].toString())),
                            ]);
                          }).toList(),
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
}

/// ===================== CLIENT DETAILS TABS (Sewing-like) =====================
class ClientDetailsTabs extends StatefulWidget {
  final int clientId;
  final int? seasonId;
  const ClientDetailsTabs({super.key, required this.clientId, this.seasonId});

  @override
  State<ClientDetailsTabs> createState() => _ClientDetailsTabsState();
}

class _ClientDetailsTabsState extends State<ClientDetailsTabs> {
  int selected = 0; // 0 = factures, 1 = transactions
  List<dynamic> factures = [];
  List<dynamic> transactions = [];
  Set<int> expandedFactureIds = {};

  bool loadingFactures = false;
  bool loadingTransactions = false;

  DateTime? startDate;
  DateTime? endDate;

  final _txHorizCtrl = ScrollController();
  final _itemsHorizCtrl = ScrollController();

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
      expandedFactureIds.clear();
      _fetchFactures();
      _fetchTransactions();
    }
  }

  Future<void> _fetchFactures() async {
    setState(() {
      loadingFactures = true;
      factures = [];
    });
    try {
      final r = await http.get(Uri.parse('$kBaseUrl/clients/${widget.clientId}/factures'));
      if (r.statusCode == 200) {
        factures = jsonDecode(r.body) as List;
      }
    } finally {
      setState(() => loadingFactures = false);
    }
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      loadingTransactions = true;
      transactions = [];
    });
    try {
      var url = '$kBaseUrl/clients/${widget.clientId}/transactions';
      if (startDate != null && endDate != null) {
        final s = startDate!.toIso8601String().split('T')[0];
        final e = endDate!.toIso8601String().split('T')[0];
        url += '?start_date=$s&end_date=$e';
      }
      final r = await http.get(Uri.parse(url));
      if (r.statusCode == 200) transactions = jsonDecode(r.body) as List;
    } finally {
      setState(() => loadingTransactions = false);
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
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
      _fetchTransactions();
    }
  }

  Future<void> _printTransactions() async {
    if (transactions.isEmpty) return;

    final pdf = pw.Document();

    // Load fonts from assets (same as Sewing)
    final arabicData =
        await rootBundle.load('assets/fonts/NotoSansArabic_Condensed-Black.ttf');
    final latinData =
        await rootBundle.load('assets/fonts/Roboto_Condensed-Black.ttf');
    final arabicFont = pw.Font.ttf(arabicData);
    final latinFont = pw.Font.ttf(latinData);

    // Find client name
    String clientName = 'عميل غير معروف';
    try {
      final resp = await http.get(Uri.parse('$kBaseUrl/clients'));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        final found = list.cast<Map>().firstWhere(
          (c) => c['id'] == widget.clientId,
          orElse: () => {},
        );
        if (found.isNotEmpty) clientName = (found['full_name'] ?? '').toString();
      }
    } catch (_) {}

    final headers = ['التاريخ', 'نوع العملية', 'رقم الفاتورة', 'المبلغ'];
    final dataRows = transactions.map<List<String>>((tx) {
      final amt = parseNum(tx['amount']);
      return [
        fmtDate(tx['date']?.toString()),
        tx['label']?.toString() ?? '',
        tx['facture_id']?.toString() ?? '-',
        '${amt.toStringAsFixed(2)} دج',
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (ctx) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'كشف حساب العميل: $clientName',
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    fontFallback: [latinFont],
                  ),
                ),
                pw.SizedBox(height: 4),
                if (startDate != null && endDate != null)
                  pw.Text(
                    'من ${fmtDate(startDate!.toIso8601String())} إلى ${fmtDate(endDate!.toIso8601String())}',
                    style: pw.TextStyle(font: arabicFont, fontFallback: [latinFont]),
                  ),
                pw.SizedBox(height: 12),
                pw.Table.fromTextArray(
                  headers: headers,
                  data: dataRows,
                  headerStyle: pw.TextStyle(
                    font: arabicFont,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                    fontFallback: [latinFont],
                  ),
                  cellStyle: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 12,
                    fontFallback: [latinFont],
                  ),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  border: pw.TableBorder.all(width: 0.5),
                  cellAlignment: pw.Alignment.centerRight,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final String? dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'اختر مجلد الحفظ',
    );
    if (dir != null) {
      final ts = DateTime.now();
      final stamp =
          '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}_${ts.hour.toString().padLeft(2, '0')}-${ts.minute.toString().padLeft(2, '0')}';
      final filePath = '$dir/كشف_حساب_${widget.clientId}_$stamp.pdf';
      await io.File(filePath).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ الملف في $filePath'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Widget _chip(String lbl, int idx) => ChoiceChip(
        label: Text(lbl),
        selected: selected == idx,
        selectedColor: Theme.of(context).colorScheme.primary,
        labelStyle: TextStyle(
            color: selected == idx ? Colors.white : null, fontWeight: FontWeight.bold),
        onSelected: (_) => setState(() => selected = idx),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.grey[100],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _chip('الفواتير', 0),
            const SizedBox(width: 8),
            _chip('المعاملات', 1),
          ]),
        ),
        Expanded(child: selected == 0 ? _facturesTab() : _transactionsTab()),
      ],
    );
  }

  Widget _facturesTab() {
    if (loadingFactures) return const Center(child: CircularProgressIndicator());
    if (factures.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('لا توجد فواتير',
                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: factures.map((f) {
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
                    title: Text('فاتورة ${f['id']}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.blue[800])),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.calendar_today, size: 16, color: Colors.blue[600]),
                          const SizedBox(width: 4),
                          Text('تاريخ: ${fmtDate(f['facture_date'])}'),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(
                              child: costItem(
                                  'الإجمالي', f['total_amount'], Colors.green[700]!)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: costItem(
                                  'المدفوع', f['total_paid'], Colors.blue[700]!)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: costItem(
                                  'المتبقي', f['remaining_amount'], Colors.orange[700]!)),
                        ]),
                      ],
                    ),
                    trailing: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: expanded ? Colors.blue : Colors.grey),
                    onTap: () {
                      setState(() {
                        if (expanded) expandedFactureIds.remove(f['id']);
                        else expandedFactureIds.add(f['id']);
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
                                  color: Colors.white, fontWeight: FontWeight.bold),
                              columns: const [
                                DataColumn(label: Text('المنتج')),
                                DataColumn(label: Text('النوع')),
                                DataColumn(label: Text('عدد الغرز')),
                                DataColumn(label: Text('سعر الغرزة')),
                                DataColumn(label: Text('الكمية')),
                                DataColumn(label: Text('الإجمالي')),
                              ],
                              rows: (f['items'] as List).map<DataRow>((it) {
                                final qty = parseInt(it['quantity']);
                                final price = parseNum(it['unit_price']);
                                final snum = it['stitch_number'] ?? '';
                                final mtype = it['model_type'] ?? '';
                                final stitches = parseInt(it['stitch_number']);
                                return DataRow(cells: [
                                  DataCell(Text(it['model_name'] ?? '')),
                                  DataCell(Text(mtype.toString())),
                                  DataCell(Text(snum.toString())),
                                  DataCell(Text('${price.toStringAsFixed(2)} دج')),
                                  DataCell(Text(qty.toString())),
                                  DataCell(Text(
                                      '${(qty * price * stitches).toStringAsFixed(2)} دج')),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                        if (f['returns'] != null && (f['returns'] as List).isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('المرتجعات:',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800])),
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
                                DataColumn(label: Text('تاريخ الإرجاع')),
                                DataColumn(label: Text('ملاحظات')),
                              ],
                              rows: (f['returns'] as List)
                                  .map<DataRow>((r) => DataRow(cells: [
                                        DataCell(Text(r['model_name'] ?? '')),
                                        DataCell(Text('${r['quantity'] ?? 0}')),
                                        DataCell(Text(fmtDate(r['return_date']))),
                                        DataCell(Text(r['notes'] ?? '')),
                                      ]))
                                  .toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _transactionsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(startDate != null && endDate != null
                    ? 'من ${fmtDate(startDate!.toIso8601String())} إلى ${fmtDate(endDate!.toIso8601String())}'
                    : 'اختر نطاق التاريخ'),
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
                  _fetchTransactions();
                },
                child: const Text('إزالة التصفية'),
              ),
          ]),
        ),
        if (!loadingTransactions && transactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.print, color: Colors.white),
                label: const Text('طباعة المعاملات', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: _printTransactions,
              ),
            ),
          ),
        Expanded(
          child: loadingTransactions
              ? const Center(child: CircularProgressIndicator())
              : transactions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance_outlined,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text('لا توجد معاملات',
                              style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المعاملات المالية',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                                      color: Colors.white, fontWeight: FontWeight.bold),
                                  columns: const [
                                    DataColumn(label: Text('التاريخ')),
                                    DataColumn(label: Text('نوع العملية')),
                                    DataColumn(label: Text('رقم الفاتورة')),
                                    DataColumn(label: Text('المبلغ')),
                                  ],
                                  rows: transactions.map<DataRow>((e) {
                                    final amt = parseNum(e['amount']);
                                    return DataRow(cells: [
                                      DataCell(Text(fmtDate(e['date']?.toString()))),
                                      DataCell(Text(e['label']?.toString() ?? '')),
                                      DataCell(Text(e['facture_id']?.toString() ?? '-')),
                                      DataCell(Text(
                                        '${amt.toStringAsFixed(2)} دج',
                                        style: TextStyle(
                                            color: amt >= 0 ? Colors.red : Colors.green,
                                            fontWeight: FontWeight.bold),
                                      )),
                                    ]);
                                  }).toList(),
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
}
