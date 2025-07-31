// lib/embroidery/embroidery_expenses_section.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class EmbroideryExpensesSection extends StatefulWidget {
  const EmbroideryExpensesSection({super.key});
  @override
  State<EmbroideryExpensesSection> createState() => _EmbroideryExpensesSectionState();
}

class _EmbroideryExpensesSectionState extends State<EmbroideryExpensesSection> {
  final String apiUrl        = 'http://127.0.0.1:8888/embrodry/expenses/';
  final String warehouseBase = 'http://127.0.0.1:8888/embrodry/warehouse';

  // Data
  List expenses = [];
  List allExpenses = [];
  List materialTypes = [];
  List materials = [];

  // Loading
  bool isLoading = false;

  // Year & Month
  List<int> years = [];
  List<String> months = [];
  int selectedYear = DateTime.now().year;
  String selectedYearMonth =
      '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

  final ScrollController _vCtrl = ScrollController();
  final ScrollController _hCtrl = ScrollController();

  final Map<String, Map<String, dynamic>> typeLabels = {
    'electricity': {
      'label': 'الكهرباء',
      'lightColor': Colors.blue[50],
      'darkColor': Colors.blue[800],
      'darkerColor': Colors.blue[900],
    },
    'rent': {
      'label': 'الإيجار',
      'lightColor': Colors.green[50],
      'darkColor': Colors.green[800],
      'darkerColor': Colors.green[900],
    },
    'water': {
      'label': 'الماء',
      'lightColor': Colors.cyan[50],
      'darkColor': Colors.cyan[800],
      'darkerColor': Colors.cyan[900],
    },
    'maintenance': {
      'label': 'الصيانة',
      'lightColor': Colors.orange[50],
      'darkColor': Colors.orange[800],
      'darkerColor': Colors.orange[900],
    },
    'raw_materials': {
      'label': 'مواد خام مستعملة',
      'lightColor': Colors.pink[50],
      'darkColor': Colors.pink[800],
      'darkerColor': Colors.pink[900],
    },
    'custom': {
      'label': 'أخرى',
      'lightColor': Colors.grey[50],
      'darkColor': Colors.grey[800],
      'darkerColor': Colors.grey[900],
    },
  };

  @override
  void initState() {
    super.initState();
    _fetchMaterialTypes();
    _fetchAllExpenses();
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchMaterialTypes() async {
    try {
      final r = await http.get(Uri.parse('$warehouseBase/material-types'));
      if (r.statusCode == 200) {
        materialTypes = jsonDecode(r.body) as List;
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _fetchMaterialsByType(int typeId) async {
    materials = [];
    try {
      final r = await http.get(Uri.parse('$warehouseBase/materials?type_id=$typeId'));
      if (r.statusCode == 200) {
        materials = (jsonDecode(r.body) as Map)['materials'] as List;
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _fetchAllExpenses() async {
    try {
      final r = await http.get(Uri.parse(apiUrl));
      if (r.statusCode == 200) {
        allExpenses = jsonDecode(r.body) as List;
      } else {
        allExpenses = [];
      }
    } catch (_) {
      allExpenses = [];
    }

    years = allExpenses
        .map((e) => int.tryParse((e['expense_date'] ?? '').toString().substring(0, 4)) ??
            DateTime.now().year)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (!years.contains(selectedYear)) selectedYear = years.isEmpty ? DateTime.now().year : years.first;

    _buildMonths();
    await _fetchExpenses();
  }

  void _buildMonths() {
    months = allExpenses
        .where((e) => (e['expense_date'] ?? '').toString().startsWith('$selectedYear-'))
        .map((e) => e['expense_date'].toString().substring(5, 7))
        .toSet()
        .toList()
      ..sort();

    final nowM = DateTime.now().month.toString().padLeft(2, '0');
    if (selectedYear == DateTime.now().year && months.contains(nowM)) {
      selectedYearMonth = '$selectedYear-$nowM';
    } else if (months.isNotEmpty) {
      selectedYearMonth = '$selectedYear-${months.first}';
    } else {
      selectedYearMonth =
          '$selectedYear-${DateTime.now().month.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _fetchExpenses() async {
    setState(() => isLoading = true);
    try {
      final parts = selectedYearMonth.split('-');
      final year = parts[0], month = parts[1];
      final r = await http.get(Uri.parse('$apiUrl?year=$year&month=$month'));
      if (r.statusCode == 200) {
        expenses = jsonDecode(r.body) as List;
      } else {
        expenses = [];
        _snack('خطأ في السيرفر: ${r.statusCode}', err: true);
      }
    } catch (e) {
      expenses = [];
      _snack('خطأ في الجلب: $e', err: true);
    }
    setState(() => isLoading = false);
  }

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), backgroundColor: err ? Colors.red : Colors.green));
  }

  double _sumType(String t) {
    return expenses.where((e) => e['expense_type'] == t).fold<double>(
        0.0, (s, e) => s + (e['amount'] as num).toDouble());
  }

  Future<void> _addOrEdit({Map? existing}) async {
  final _formKey = GlobalKey<FormState>();

  // Initial values
  String type = existing?['expense_type'] ?? typeLabels.keys.first;
  int? selTypeId    = existing?['material_type_id'] as int?;
  int? selMatId     = existing?['material_id']      as int?;
  DateTime expDate  = existing != null
      ? DateTime.tryParse(existing['expense_date'] ?? '') ?? DateTime.now()
      : DateTime.now();
  final descCtl     = TextEditingController(text: existing?['description'] ?? '');
  final amountCtl   = TextEditingController(text: existing?['amount']?.toString() ?? '');
  final qtyCtl      = TextEditingController(text: existing?['quantity']?.toString() ?? '');
  final priceCtl    = TextEditingController(text: (existing?['unit_price'] as num?)?.toStringAsFixed(2) ?? '0.00');
  double totalRM    = (existing?['amount'] as num?)?.toDouble() ?? 0.0;

  if (type == 'raw_materials' && selTypeId != null) {
    await _fetchMaterialsByType(selTypeId);
  }

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setD) {
        void recalcTotal() {
          final q = double.tryParse(qtyCtl.text) ?? 0;
          final p = double.tryParse(priceCtl.text) ?? 0;
          totalRM = q * p;
          setD(() {});
        }
        Future<void> pickDate() async {
          final p = await showDatePicker(
            context: ctx,
            initialDate: expDate,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            locale: const Locale('ar'),
          );
          if (p != null) setD(() => expDate = p);
        }

        return AlertDialog(
          title: Text(existing == null ? 'إضافة مصروف' : 'تعديل مصروف'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Expense type
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(labelText: 'النوع'),
                      items: typeLabels.entries.map((e) {
                        return DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(e.value['label'] as String),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        type = v;
                        // reset raw-materials fields if switching back
                        if (type != 'raw_materials') {
                          selTypeId = selMatId = null;
                          qtyCtl.text = '';
                          priceCtl.text = '0.00';
                          totalRM = 0;
                        }
                        setD(() {});
                      },
                      validator: (_) => null,
                    ),
                    const SizedBox(height: 12),

                    // If raw materials: show material chooser + qty
                    if (type == 'raw_materials') ...[
                      DropdownButtonFormField<int>(
                        value: selTypeId,
                        decoration: const InputDecoration(labelText: 'نوع المادة'),
                        items: materialTypes.map((t) {
                          return DropdownMenuItem<int>(
                            value: t['id'] as int,
                            child: Text(t['name'] as String),
                          );
                        }).toList(),
                        onChanged: (v) async {
                          selTypeId = v;
                          selMatId = null;
                          priceCtl.text = '0.00';
                          totalRM = 0;
                          if (v != null) await _fetchMaterialsByType(v);
                          setD(() {});
                        },
                        validator: (v) =>
                            v == null ? 'اختر نوع المادة' : null,
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<int>(
                        value: selMatId,
                        decoration: const InputDecoration(labelText: 'المادة'),
                        items: materials.map((m) {
                          return DropdownMenuItem<int>(
                            value: m['id'] as int,
                            child: Text(m['code'] as String),
                          );
                        }).toList(),
                        onChanged: (v) {
                          selMatId = v;
                          if (v != null) {
                            final m = materials.firstWhere((e) => e['id'] == v);
                            priceCtl.text = (m['unit_price'] as num).toStringAsFixed(2);
                          } else {
                            priceCtl.text = '0.00';
                          }
                          recalcTotal();
                        },
                        validator: (v) =>
                            v == null ? 'اختر المادة' : null,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: qtyCtl,
                        decoration: const InputDecoration(labelText: 'الكمية'),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          final q = double.tryParse(v ?? '') ?? 0;
                          if (q <= 0) return 'أدخل كمية صالحة';
                          return null;
                        },
                        onChanged: (_) => recalcTotal(),
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: priceCtl,
                        readOnly: true,
                        decoration: const InputDecoration(labelText: 'سعر الوحدة'),
                      ),
                      const SizedBox(height: 8),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'الإجمالي: ${totalRM.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ] else ...[
                      // For non–raw_materials
                      if (type == 'custom') ...[
                        TextFormField(
                          controller: descCtl,
                          decoration: const InputDecoration(labelText: 'الوصف'),
                          validator: (v) => null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: amountCtl,
                        decoration: const InputDecoration(labelText: 'المبلغ'),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          final a = double.tryParse(v ?? '') ?? 0;
                          if (a <= 0) return 'أدخل مبلغًا أكبر من الصفر';
                          return null;
                        },
                      ),
                    ],

                    const SizedBox(height: 12),
                    // Date picker
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          'التاريخ: ${expDate.toIso8601String().split('T').first}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: pickDate,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;

                // Build payload based on type
                Map<String, dynamic> payload;
                if (type == 'raw_materials') {
                  final q = double.tryParse(qtyCtl.text) ?? 0;
                  payload = {
                    'expense_type':        type,
                    'description':         '',
                    'expense_date':        expDate.toIso8601String(),
                    'material_type_id':    selTypeId,
                    'material_id':         selMatId,
                    'quantity':            q,
                  };
                } else {
                  final amt = double.tryParse(amountCtl.text) ?? 0;
                  payload = {
                    'expense_type':        type,
                    'description':         type == 'custom' ? descCtl.text.trim() : '',
                    'amount':              amt,
                    'expense_date':        expDate.toIso8601String(),
                  };
                }

                try {
                  final resp = existing == null
                      ? await http.post(Uri.parse(apiUrl),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(payload))
                      : await http.put(Uri.parse('$apiUrl${existing!['id']}'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(payload));

                  if (resp.statusCode >= 200 && resp.statusCode < 300) {
                    _snack(existing == null ? 'تمت الإضافة' : 'تم التحديث');
                    Navigator.pop(ctx);
                    await _fetchAllExpenses();
                  } else {
                    _snack('فشل العملية: ${resp.body}', err: true);
                  }
                } catch (e) {
                  _snack('خطأ: $e', err: true);
                }
              },
              child: Text(existing == null ? 'حفظ' : 'تحديث'),
            ),
          ],
        );
      },
    ),
  );
}


  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final r = await http.delete(Uri.parse('$apiUrl$id'));
      if (r.statusCode == 200) {
        _snack('تم الحذف');
        await _fetchExpenses();
      } else {
        _snack('فشل الحذف: ${r.body}', err: true);
      }
    } catch (e) {
      _snack('خطأ اتصال: $e', err: true);
    }
  }

  void _showExpenseDetails(Map e) {
    final t = e['expense_type'];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تفاصيل المصروف #${e['id']}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('النوع:', typeLabels[t]?['label'] ?? t),
                _row('التاريخ:', (e['expense_date'] as String).split(RegExp(r'[T ]')).first),
                _row('المبلغ:', (e['amount'] as num).toStringAsFixed(2)),
                if (t == 'custom') _row('الوصف:', (e['description'] ?? '-').toString()),
                if (t == 'raw_materials') ...[
                  const Divider(),
                  const Text('بيانات المواد الخام', style: TextStyle(fontWeight: FontWeight.bold)),
                  _row('نوع المادة:', e['material_type_name'] ?? '-'),
                  _row('الكود:', e['material_code'] ?? '-'),
                  _row('الكمية:', ((e['quantity'] as num?)?.toStringAsFixed(3) ?? '-')),
                  _row('سعر الوحدة:', ((e['unit_price'] as num?)?.toStringAsFixed(2) ?? '-')),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(v)),
        ],
      ));

  @override
  Widget build(BuildContext context) {
    const monthNames = [
      'جانفي','فيفري','مارس','أفريل','ماي','جوان',
      'جويلية','أوت','سبتمبر','أكتوبر','نوفمبر','ديسمبر'
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _addOrEdit(),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('+ إضافة مصروف'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  DropdownButton<int>(
                    value: selectedYear,
                    items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                    onChanged: (y) {
                      if (y == null) return;
                      setState(() {
                        selectedYear = y;
                        _buildMonths();
                        _fetchExpenses();
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: selectedYearMonth.substring(5, 7),
                    items: months.map((m) {
                      final idx = int.parse(m);
                      return DropdownMenuItem(value: m, child: Text(monthNames[idx - 1]));
                    }).toList(),
                    onChanged: (m) {
                      if (m == null) return;
                      setState(() {
                        selectedYearMonth = '$selectedYear-$m';
                        _fetchExpenses();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: typeLabels.entries.map((e) {
                  return Expanded(
                    child: Card(
                      color: e.value['lightColor'] as Color,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              e.value['label'] as String,
                              style: TextStyle(
                                color: e.value['darkColor'] as Color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_sumType(e.key).toStringAsFixed(2)} دج',
                              style: TextStyle(
                                fontSize: 22,
                                color: e.value['darkerColor'] as Color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : expenses.isEmpty
                        ? const Center(child: Text('لا توجد مصروفات'))
                        : Scrollbar(
                            controller: _vCtrl,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _vCtrl,
                              scrollDirection: Axis.vertical,
                              child: Scrollbar(
                                controller: _hCtrl,
                                thumbVisibility: true,
                                notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                                child: SingleChildScrollView(
                                  controller: _hCtrl,
                                  scrollDirection: Axis.horizontal,
                                  child: Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: DataTable(
                                        headingRowColor: MaterialStateProperty.all(
                                          Theme.of(context).colorScheme.primary,
                                        ),
                                        headingTextStyle: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        columns: const [
                                          DataColumn(label: Text('النوع')),
                                          DataColumn(label: Text('المبلغ')),
                                          DataColumn(label: Text('التاريخ')),
                                          DataColumn(label: Text('إجراءات')),
                                        ],
                                        rows: expenses.map((e) {
                                          final t   = e['expense_type'];
                                          final cfg = typeLabels[t];
                                          final label = cfg?['label'] as String? ?? t;
                                          final dateOnly = (e['expense_date'] as String)
                                              .split(RegExp(r'[T ]')).first;

                                          return DataRow(cells: [
                                            DataCell(Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: cfg?['lightColor'] as Color? ?? Colors.grey[200],
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                label,
                                                style: TextStyle(
                                                  color: cfg?['darkColor'] as Color? ?? Colors.grey[800],
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            )),
                                            DataCell(Text('${(e['amount'] as num).toStringAsFixed(2)} دج')),
                                            DataCell(Text(dateOnly)),
                                            DataCell(Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.visibility, color: Colors.blue),
                                                  tooltip: 'تفاصيل',
                                                  onPressed: () => _showExpenseDetails(e),
                                                ),
                                                IconButton(
                                                  icon: Icon(Icons.edit,
                                                      color: Theme.of(context).colorScheme.primary),
                                                  tooltip: 'تعديل',
                                                  onPressed: () => _addOrEdit(existing: e),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete, color: Colors.red),
                                                  tooltip: 'حذف',
                                                  onPressed: () => _delete(e['id']),
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
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
