// lib/embroidery/embroidery_purchases_section.dart
// UI replica of SewingPurchasesSection but for EMBROIDERY purchases.
// Scrollbars added (vertical + horizontal) for tables and lists.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class EmbroideryPurchasesSection extends StatefulWidget {
  const EmbroideryPurchasesSection({super.key});

  @override
  State<EmbroideryPurchasesSection> createState() => _EmbroideryPurchasesSectionState();
}

class _EmbroideryPurchasesSectionState extends State<EmbroideryPurchasesSection> {
  // ==================== CONFIG ====================
  final String _baseUrl = 'http://127.0.0.1:8888/embrodry/purchases';

  // ==================== STATE =====================
  final TextEditingController _searchCtl = TextEditingController();
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _filtered = [];
  List<dynamic> _materials = [];
  List<dynamic> _materialTypes = [];
  List<dynamic> _suppliers = [];
  List<dynamic> _seasons = [];

  bool _loading = false;
  int? _selectedId;
  int? _selectedSeasonId; // null => all

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(_applyFilter);
    _fetchAll();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  // ==================== HELPERS ====================
  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: err ? Colors.red : Colors.green),
    );
  }

  void _applyFilter() {
    final q = _searchCtl.text.toLowerCase();
    setState(() {
      _filtered = _purchases.where((p) {
        final id  = p['id'].toString();
        final sup = (p['supplier_name'] ?? '').toLowerCase();
        final drv = (p['driver'] ?? '').toString().toLowerCase();
        return id.contains(q) || sup.contains(q) || drv.contains(q);
      }).toList();
    });
  }

  String _fmtDate(String? s) {
    if (s == null || s.isEmpty) return '';
    try {
      final d = DateTime.parse(s);
      return '${d.day.toString().padLeft(2,'0')}-${d.month.toString().padLeft(2,'0')}-${d.year}';
    } catch (_) {
      return s.split('T').first;
    }
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Map<String, dynamic>? get _selectedPurchase =>
      _purchases.firstWhere((p) => p['id'] == _selectedId, orElse: () => {});

  // ==================== NETWORK ====================
  Future<void> _fetchAll() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _fetchMaterials(),
        _fetchMaterialTypes(),
        _fetchSuppliers(),
        _fetchSeasonsIfAvailable(),
        _fetchPurchases(),
      ]);
    } catch (e) {
      _snack('خطأ في جلب البيانات: $e', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchPurchases() async {
    String url = _baseUrl;
    if (_selectedSeasonId != null) {
      final tryUrl = '$_baseUrl/by_season/$_selectedSeasonId';
      try {
        final test = await http.get(Uri.parse(tryUrl));
        if (test.statusCode == 200) url = tryUrl;
      } catch (_) {}
    }
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) throw Exception('Server error: ${res.statusCode}');
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    list.sort((a, b) => b['purchase_date'].toString().compareTo(a['purchase_date'].toString()));
    setState(() {
      _purchases = list;
      _filtered = List.from(_purchases);
      if (_selectedId == null && _purchases.isNotEmpty) {
        _selectedId = _purchases.first['id'] as int;
      } else if (!_purchases.any((p) => p['id'] == _selectedId)) {
        _selectedId = _purchases.isNotEmpty ? _purchases.first['id'] as int : null;
      }
    });
  }

  Future<void> _fetchSeasonsIfAvailable() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/seasons'));
      if (res.statusCode == 200) _seasons = jsonDecode(res.body);
    } catch (_) {
      _seasons = [];
    }
  }

  Future<void> _fetchMaterials() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/materials'));
      if (res.statusCode == 200) _materials = jsonDecode(res.body);
    } catch (_) {}
  }

  Future<void> _fetchMaterialTypes() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/material_types'));
      if (res.statusCode == 200) _materialTypes = jsonDecode(res.body);
    } catch (_) {}
  }

  Future<void> _fetchSuppliers() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/suppliers'));
      if (res.statusCode == 200) _suppliers = jsonDecode(res.body);
    } catch (_) {}
  }

  Future<List<dynamic>> _fetchMaterialsByType(int typeId) async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/materials/by_type/$typeId'));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return [];
  }

  Future<void> _deletePurchase(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الشراء'),
        content: const Text('هل أنت متأكد من حذف هذا الشراء؟'),
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
      final res = await http.delete(Uri.parse('$_baseUrl/$id'));
      if (res.statusCode != 200) throw Exception(res.statusCode);
      _snack('تم حذف الشراء');
      await _fetchAll();
    } catch (e) {
      _snack('فشل الحذف: $e', err: true);
    }
  }

  // ==================== DIALOGS ====================
  Future<void> _showPurchaseDialog({Map<String, dynamic>? initial}) async {
    await Future.wait([
      _fetchMaterials(),
      _fetchMaterialTypes(),
      _fetchSuppliers(),
    ]);

    DateTime purchaseDate = initial != null && initial['purchase_date'] != null
        ? DateTime.parse(initial['purchase_date'])
        : DateTime.now();

    int? selectedSupplierId = initial?['supplier_id'] as int?;
    List<Map<String, dynamic>> items = initial == null
        ? []
        : List<Map<String, dynamic>>.from(initial['items']);

    // ── Driver ───────────────────────────────────────────
    String driver = initial?['driver'] ?? '';
    final driverCtl = TextEditingController(text: driver);

    double _totalAmount() {
      return items.fold<double>(0.0, (sum, it) {
        final q = _toDouble(it['quantity']) ?? 0.0;
        final p = _toDouble(it['unit_price']) ?? 0.0;
        return sum + q * p;
      });
    }

    double amountPaid = _toDouble(initial?['amount_paid_on_creation']) ?? 0.0;
    final amountCtl = TextEditingController(text: amountPaid.toStringAsFixed(2));
    String paymentType =
        amountPaid >= _totalAmount() && _totalAmount() > 0 ? 'cash' : 'debt';

    final _formKey = GlobalKey<FormState>();
    bool _itemsValid = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        void updatePayment(String v) {
          setD(() {
            paymentType = v;
            if (v == 'cash') {
              amountPaid = _totalAmount();
              amountCtl.text = amountPaid.toStringAsFixed(2);
            } else {
              amountPaid = 0.0;
              amountCtl.text = '0.00';
            }
          });
        }

        return AlertDialog(
          title: Text(initial == null ? 'إضافة شراء جديد' : 'تعديل الشراء'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Basic info ─────────────────────────────
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('المعلومات الأساسية',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Text('التاريخ:'),
                                const SizedBox(width: 8),
                                Text('${purchaseDate.toLocal()}'.split(' ')[0]),
                                const Spacer(),
                                ElevatedButton(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: ctx,
                                      initialDate: purchaseDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2100),
                                      locale: const Locale('ar'),
                                    );
                                    if (picked != null) setD(() => purchaseDate = picked);
                                  },
                                  child: const Text('تغيير التاريخ'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              value: selectedSupplierId,
                              decoration: const InputDecoration(labelText: 'اختر المورد'),
                              items: _suppliers
                                  .map<DropdownMenuItem<int>>(
                                    (s) => DropdownMenuItem<int>(
                                      value: s['id'] as int,
                                      child: Text((s['full_name'] ?? s['name']) as String),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setD(() => selectedSupplierId = v),
                              validator: (v) =>
                                  v == null ? 'يرجى اختيار المورد' : null,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: driverCtl,
                              decoration: const InputDecoration(
                                labelText: 'اسم السائق',
                                hintText: 'أدخل اسم السائق',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Items ────────────────────────────────────
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('المواد المضافة',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('الإجمالي: ${_totalAmount().toStringAsFixed(2)} دج',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, color: Colors.green)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (items.isNotEmpty)
                              ...items.asMap().entries.map((e) {
                                final idx = e.key;
                                final item = e.value;
                                final material = _materials.firstWhere(
                                  (m) => m['id'] == item['material_id'],
                                  orElse: () => {'code': 'غير محدد', 'type_name': ''},
                                );
                                final subtotal = (_toDouble(item['quantity']) ?? 0.0) *
                                    (_toDouble(item['unit_price']) ?? 0.0);
                                return Card(
                                  color: Colors.grey[50],
                                  child: ListTile(
                                    title: Text(
                                        '${material['code']} (${material['type_name'] ?? ''})'),
                                    subtitle: Text(
                                        'الكمية: ${item['quantity']} × ${item['unit_price']} = ${subtotal.toStringAsFixed(2)} دج'),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => setD(() => items.removeAt(idx)),
                                    ),
                                  ),
                                );
                              })
                            else if (!_itemsValid) ...[
                              const SizedBox(height: 4),
                              const Text(
                                'يرجى إضافة مادة واحدة على الأقل',
                                style: TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('إضافة مادة'),
                                onPressed: () => _showAddMaterialDialog(setD, items),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Payment ──────────────────────────────────
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('طريقة الدفع',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ListTile(
                              title: const Text('شراء بالدين'),
                              leading: Radio<String>(
                                value: 'debt',
                                groupValue: paymentType,
                                onChanged: (v) => setD(() => updatePayment(v!)),
                              ),
                            ),
                            ListTile(
                              title: const Text('شراء نقدي'),
                              leading: Radio<String>(
                                value: 'cash',
                                groupValue: paymentType,
                                onChanged: (v) => setD(() => updatePayment(v!)),
                              ),
                            ),
                            if (paymentType == 'cash' && items.isNotEmpty)
                              TextFormField(
                                controller: amountCtl,
                                decoration: InputDecoration(
                                  labelText:
                                      'دفعة أولى (الحد الأقصى: ${_totalAmount().toStringAsFixed(2)})',
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                validator: (v) {
                                  final val = double.tryParse(v ?? '');
                                  if (val == null) return 'يرجى إدخال مبلغ صحيح';
                                  if (val > _totalAmount()) return 'الدفعة أكبر من الإجمالي';
                                  if (val < 0) return 'الدفعة لا يمكن أن تكون سالبة';
                                  return null;
                                },
                                onChanged: (v) {
                                  final amt = double.tryParse(v) ?? 0.0;
                                  amountCtl.text =
                                      amt.clamp(0.0, _totalAmount()).toStringAsFixed(2);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Actions inside the same AlertDialog ─────────────────
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final validForm = _formKey.currentState!.validate();
                setD(() => _itemsValid = items.isNotEmpty);
                if (!validForm || !_itemsValid) return;

                final body = jsonEncode({
                  'purchase_date': purchaseDate.toIso8601String(),
                  'supplier_id': selectedSupplierId,
                  'driver': driverCtl.text.trim().isEmpty ? null : driverCtl.text.trim(),
                  'amount_paid_on_creation': paymentType == 'cash' ? amountPaid : 0.0,
                  'items': items,
                });

                try {
                  if (initial == null) {
                    final res = await http.post(
                      Uri.parse(_baseUrl),
                      headers: {'Content-Type': 'application/json'},
                      body: body,
                    );
                    if (res.statusCode < 200 || res.statusCode >= 300) {
                      throw Exception('${res.statusCode} ${res.body}');
                    }
                    _snack('تمت الإضافة');
                  } else {
                    final int id = initial['id'] as int;
                    final r1 = await http.put(
                      Uri.parse('$_baseUrl/$id'),
                      headers: {'Content-Type': 'application/json'},
                      body: body,
                    );
                    if (r1.statusCode != 200) throw Exception(r1.body);
                    final r2 = await http.post(
                      Uri.parse('$_baseUrl/$id/items'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({'items': items}),
                    );
                    if (r2.statusCode != 200) throw Exception(r2.body);
                    _snack('تم التحديث');
                  }
                  if (mounted) Navigator.pop(ctx);
                  await _fetchAll();
                } catch (e) {
                  _snack('خطأ في الحفظ: $e', err: true);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      }),
    );
  }

  void _showAddMaterialDialog(StateSetter setDialogState, List<Map<String, dynamic>> items) {
    int? typeId;
    int? materialId;
    List<dynamic> filteredMaterials = [];
    double qty = 0.0;
    double up = 0.0;
    final qtyCtl   = TextEditingController();
    final priceCtl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setD) => AlertDialog(
          title: const Text('إضافة مادة'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: typeId,
                  decoration: const InputDecoration(labelText: 'نوع المادة'),
                  items: _materialTypes
                      .map((t) => DropdownMenuItem<int>(
                            value: t['id'] as int,
                            child: Text(t['name'] as String),
                          ))
                      .toList(),
                  onChanged: (v) async {
                    typeId = v;
                    filteredMaterials = await _fetchMaterialsByType(v!);
                    setD(() => materialId = null);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: materialId,
                  decoration: const InputDecoration(labelText: 'المادة'),
                  items: filteredMaterials
                      .map((m) => DropdownMenuItem<int>(
                            value: m['id'] as int,
                            child: Text(m['code'] as String),
                          ))
                      .toList(),
                  onChanged: (v) => setD(() => materialId = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: qtyCtl,
                  decoration: const InputDecoration(labelText: 'الكمية'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => qty = double.tryParse(v) ?? 0.0,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceCtl,
                  decoration: const InputDecoration(labelText: 'سعر الوحدة'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => up = double.tryParse(v) ?? 0.0,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                if (materialId != null && qty > 0 && up > 0) {
                  setDialogState(() => items.add({
                        'material_id': materialId,
                        'quantity': qty,
                        'unit_price': up,
                      }));
                  Navigator.pop(ctx);
                } else {
                  _snack('املأ الحقول بقيم صحيحة', err: true);
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    final sel = _selectedPurchase;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // Sidebar list
                Container(
                  width: 400,
                  color: Colors.grey[100],
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              'مشتريات قسم التطريز',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800]),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _searchCtl,
                              decoration: InputDecoration(
                                hintText: 'بحث برقم الشراء، اسم المورد أو السائق',
                                prefixIcon: const Icon(Icons.search),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_seasons.isNotEmpty)
                              DropdownButtonFormField<int?>(
                                value: _selectedSeasonId,
                                decoration: const InputDecoration(
                                  labelText: 'تصفية حسب الموسم',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  const DropdownMenuItem<int?>(
                                      value: null, child: Text('جميع المواسم')),
                                  ..._seasons.map((s) => DropdownMenuItem<int?>(
                                        value: s['id'] as int,
                                        child: Text(s['name']),
                                      )),
                                ],
                                onChanged: (v) async {
                                  setState(() => _selectedSeasonId = v);
                                  await _fetchPurchases();
                                },
                              ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.add, color: Colors.white),
                                label: const Text('شراء جديد',
                                    style: TextStyle(color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[600],
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _showPurchaseDialog(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : Scrollbar(
                                thumbVisibility: true,
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  itemCount: _filtered.length,
                                  itemBuilder: (_, i) {
                                    final p = _filtered[i];
                                    final isSel = p['id'] == _selectedId;
                                    return Card(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      elevation: isSel ? 4 : 1,
                                      color: isSel ? Colors.grey[100] : Colors.white,
                                      child: ListTile(
                                        selected: isSel,
                                        title: Text('شراء رقم ${p['id']}',
                                            style: TextStyle(
                                                fontWeight:
                                                    isSel ? FontWeight.bold : FontWeight.normal)),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(_fmtDate(p['purchase_date'])),
                                            Text('${p['supplier_name'] ?? ''}',
                                                style: TextStyle(color: Colors.teal[700])),
                                            Text('سائق: ${p['driver'] ?? 'غير محدد'}',
                                                style: TextStyle(color: Colors.teal[700])),
                                          ],
                                        ),
                                        onTap: () => setState(() => _selectedId = p['id'] as int),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit, color: Colors.teal),
                                              onPressed: () => _showPurchaseDialog(initial: p),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete, color: Colors.red),
                                              onPressed: () => _deletePurchase(p['id']),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),

                const VerticalDivider(width: 1),

                // Details pane
                Expanded(
                  child: sel == null || sel.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text('اختر عملية شراء من القائمة الجانبية',
                                  style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                            ],
                          ),
                        )
                      : Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تفاصيل شراء رقم ${sel['id']}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo[800]),
                                ),
                                const SizedBox(height: 24),

                                // Purchase info
                                Card(
                                  color: Colors.blue[50],
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('معلومات الشراء',
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
                                            Text('التاريخ: ${_fmtDate(sel['purchase_date'])}'),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(Icons.store,
                                                size: 20, color: Colors.blue),
                                            const SizedBox(width: 8),
                                            Text('المورد: ${sel['supplier_name'] ?? ''}'),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(Icons.local_shipping,
                                                size: 20, color: Colors.blue),
                                            const SizedBox(width: 8),
                                            Text('السائق: ${sel['driver'] ?? 'غير محدد'}'),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // Payment info
                                Card(
                                  color: Colors.green[50],
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Builder(
                                      builder: (_) {
                                        final total = _toDouble(sel['total']) ?? 0.0;
                                        final paid0 = _toDouble(sel['amount_paid_on_creation']) ?? 0.0;
                                        final extra = _toDouble(sel['extra_paid']) ?? 0.0;
                                        final paid = paid0 + extra;
                                        final rem  = (total - paid).clamp(0.0, double.infinity);
                                        final status = paid >= total
                                            ? 'مدفوع بالكامل'
                                            : paid > 0
                                                ? 'مدفوع جزئياً'
                                                : 'غير مدفوع';

                                        return Column(
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
                                                    child: _costItem('الإجمالي', total,
                                                        Colors.green[700]!)),
                                                Expanded(
                                                    child: _costItem('مدفوع', paid,
                                                        Colors.blue[700]!)),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                    child: _costItem('المتبقي', rem,
                                                        Colors.orange[700]!)),
                                                Expanded(
                                                  child: Container(
                                                    padding: const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: paid >= total
                                                          ? Colors.green.withOpacity(0.1)
                                                          : Colors.orange.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(
                                                          color: (paid >= total
                                                                  ? Colors.green
                                                                  : Colors.orange)
                                                              .withOpacity(0.3)),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment.start,
                                                      children: [
                                                        Text('الحالة',
                                                            style: TextStyle(
                                                                fontSize: 12,
                                                                color: paid >= total
                                                                    ? Colors.green[700]
                                                                    : Colors.orange[700])),
                                                        Text(status,
                                                            style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight: FontWeight.bold,
                                                                color: paid >= total
                                                                    ? Colors.green[700]
                                                                    : Colors.orange[700])),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // Items table
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('تفاصيل المواد',
                                            style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey[800])),
                                        const SizedBox(height: 16),
                                        Scrollbar(
                                          thumbVisibility: true,
                                          controller: ScrollController(),
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Scrollbar(
                                              thumbVisibility: true,
                                              child: SingleChildScrollView(
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
                                                    DataColumn(label: Text('المادة')),
                                                    DataColumn(label: Text('النوع')),
                                                    DataColumn(label: Text('الكمية')),
                                                    DataColumn(label: Text('سعر الوحدة')),
                                                    DataColumn(label: Text('الإجمالي')),
                                                  ],
                                                  rows: (sel['items']
                                                          as List<dynamic>)
                                                      .map<DataRow>((it) {
                                                    final subtotal =
                                                        (_toDouble(it['quantity']) ??
                                                                0.0) *
                                                            (_toDouble(
                                                                    it['unit_price']) ??
                                                                0.0);
                                                    return DataRow(cells: [
                                                      DataCell(Text(
                                                          '${it['material_code'] ?? 'غير محدد'}')),
                                                      DataCell(Text(
                                                          '${it['type_name'] ?? ''}')),
                                                      DataCell(Text(it['quantity']
                                                          .toString())),
                                                      DataCell(Text(
                                                          '${it['unit_price']} دج')),
                                                      DataCell(Text(
                                                          '${subtotal.toStringAsFixed(2)} دج')),
                                                    ]);
                                                  }).toList(),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _costItem(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          Text('${value.toStringAsFixed(2)} دج',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}