import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SewingPurchasesSection extends StatefulWidget {
  const SewingPurchasesSection({super.key});

  @override
  State<SewingPurchasesSection> createState() => _SewingPurchasesSectionState();
}

class _SewingPurchasesSectionState extends State<SewingPurchasesSection> {
  final String _baseUrl = 'http://localhost:8888/purchases';

  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _filtered = [];
  List<dynamic> _materials = [];
  List<dynamic> _materialTypes = [];
  List<dynamic> _suppliers = [];
  List<dynamic> _seasons = [];

  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  int? _selectedId;
  int? _selectedSeasonId; // null means "ALL"

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _fetchAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      List<Map<String, dynamic>> tempFiltered = _purchases.where((p) {
        final id = p['id'].toString();
        final sup = (p['supplier_name'] ?? '').toLowerCase();
        return id.contains(q) || sup.contains(q);
      }).toList();

      // Apply season filter if selected
      if (_selectedSeasonId != null) {
        tempFiltered = tempFiltered.where((p) {
          // This is a simple client-side filter
          // For better performance, implement server-side filtering
          return true; // Placeholder - implement season filtering logic
        }).toList();
      }

      _filtered = tempFiltered;
    });
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return "${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}";
    } catch (e) {
      return dateStr.split('T').first;
    }
  }

  Future<void> _fetchAll() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _fetchMaterials(),
        _fetchMaterialTypes(),
        _fetchSuppliers(),
        _fetchSeasonsIfAvailable(),
        _fetchPurchases(),
      ]);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في جلب البيانات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSeasonsIfAvailable() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/seasons'));
      if (res.statusCode == 200) {
        setState(() {
          _seasons = jsonDecode(res.body);
        });
      }
    } catch (_) {
      // If seasons endpoint doesn't exist, just continue without it
      _seasons = [];
    }
  }

  Future<void> _fetchMaterials() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/materials'));
      if (res.statusCode == 200) {
        _materials = jsonDecode(res.body);
      }
    } catch (_) {}
  }

  Future<void> _fetchMaterialTypes() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/material_types'));
      if (res.statusCode == 200) {
        _materialTypes = jsonDecode(res.body);
      }
    } catch (_) {}
  }

  Future<void> _fetchSuppliers() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/suppliers'));
      if (res.statusCode == 200) {
        _suppliers = jsonDecode(res.body);
      }
    } catch (_) {}
  }

  Future<void> _fetchPurchases() async {
    String url = _baseUrl;
    
    // Use season filtering only if the endpoint exists and season is selected
    if (_selectedSeasonId != null && _seasons.isNotEmpty) {
      try {
        url = '$_baseUrl/by_season/$_selectedSeasonId';
        final testRes = await http.get(Uri.parse(url));
        if (testRes.statusCode != 200) {
          // Fallback to main endpoint
          url = _baseUrl;
        }
      } catch (_) {
        url = _baseUrl;
      }
    }
    
    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) {
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
    } else {
      throw Exception('Server error: ${res.statusCode}');
    }
  }

  Map<String, dynamic>? get _selectedPurchase {
    return _purchases.firstWhere(
      (p) => p['id'] == _selectedId,
      orElse: () => {},
    );
  }

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

  // Driver controller
  String driver = initial?['driver'] ?? 'غير محدد';
  final TextEditingController driverController = TextEditingController(text: driver);

  double _totalAmount() {
    return items.fold<double>(0.0, (sum, it) {
      final q = _parseDouble(it['quantity']) ?? 0.0;
      final p = _parseDouble(it['unit_price']) ?? 0.0;
      return sum + q * p;
    });
  }

  double amountPaidOnCreation = _parseDouble(initial?['amount_paid_on_creation']) ?? 0.0;
  final TextEditingController amountController = TextEditingController(text: amountPaidOnCreation.toStringAsFixed(2));
  String paymentType = amountPaidOnCreation >= _totalAmount() && _totalAmount() > 0 ? 'cash' : 'debt';

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setDialogState) {
        void updatePaymentType(String newType) {
          setDialogState(() {
            paymentType = newType;
            if (newType == 'cash') {
              amountPaidOnCreation = _totalAmount();
              amountController.text = amountPaidOnCreation.toStringAsFixed(2);
            } else {
              amountPaidOnCreation = 0.0;
              amountController.text = '0.00';
            }
          });
        }

        return AlertDialog(
          title: Text(initial == null ? 'إضافة شراء جديد' : 'تعديل الشراء'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- Basic Info Card (with driver) ---
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المعلومات الأساسية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              const Text('التاريخ:', style: TextStyle(fontWeight: FontWeight.w500)),
                              const SizedBox(width: 8),
                              Text('${purchaseDate.toLocal()}'.split(' ')[0]),
                              const Spacer(),
                              ElevatedButton(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: purchaseDate,
                                    firstDate: DateTime(2022),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => purchaseDate = picked);
                                  }
                                },
                                child: const Text('تغيير التاريخ'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                            value: selectedSupplierId,
                            decoration: const InputDecoration(labelText: 'اختر المورد'),
                            items: _suppliers.map<DropdownMenuItem<int>>((s) {
                              return DropdownMenuItem(
                                value: s['id'] as int,
                                child: Text(s['name'] as String),
                              );
                            }).toList(),
                            onChanged: (val) => setDialogState(() => selectedSupplierId = val),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: driverController,
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

                  // --- Materials Card ---
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('المواد المضافة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(
                                'الإجمالي: ${_totalAmount().toStringAsFixed(2)} دج',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                              ),
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
                              final subtotal = (_parseDouble(item['quantity']) ?? 0.0) * (_parseDouble(item['unit_price']) ?? 0.0);

                              return Card(
                                color: Colors.grey[50],
                                child: ListTile(
                                  title: Text('${material['code']} (${material['type_name'] ?? ''})'),
                                  subtitle: Text('الكمية: ${item['quantity']} × ${item['unit_price']} = ${subtotal.toStringAsFixed(2)} دج'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => setDialogState(() => items.removeAt(idx)),
                                  ),
                                ),
                              );
                            }).toList(),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة مادة'),
                              onPressed: () => _showAddMaterialDialog(setDialogState, items),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- Payment Card ---
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('طريقة الدفع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          ListTile(
                            title: const Text('شراء بالدين'),
                            leading: Radio<String>(
                              value: 'debt',
                              groupValue: paymentType,
                              onChanged: (v) => updatePaymentType(v!),
                            ),
                          ),
                          ListTile(
                            title: const Text('شراء نقدي'),
                            leading: Radio<String>(
                              value: 'cash',
                              groupValue: paymentType,
                              onChanged: (v) => updatePaymentType(v!),
                            ),
                          ),
                          if (paymentType == 'cash' && items.isNotEmpty)
                            TextField(
                              controller: amountController,
                              decoration: InputDecoration(
                                labelText: 'دفعة أولى (الحد الأقصى: ${_totalAmount().toStringAsFixed(2)})',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (v) {
                                final amt = double.tryParse(v) ?? 0.0;
                                final total = _totalAmount();
                                if (amt > total) {
                                  amountController.text = total.toStringAsFixed(2);
                                  amountPaidOnCreation = total;
                                } else {
                                  amountPaidOnCreation = amt;
                                }
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedSupplierId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى اختيار المورد'), backgroundColor: Colors.red),
                  );
                  return;
                }

                if (items.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى إضافة مادة واحدة على الأقل'), backgroundColor: Colors.red),
                  );
                  return;
                }

                final total = _totalAmount();
                if (total <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('إجمالي الشراء يجب أن يكون أكبر من صفر'), backgroundColor: Colors.red),
                  );
                  return;
                }

                if (paymentType == 'cash' && amountPaidOnCreation > total) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الدفعة الأولى لا يمكن أن تكون أكبر من إجمالي الشراء'), backgroundColor: Colors.red),
                  );
                  return;
                }

                final body = jsonEncode({
                  'purchase_date': purchaseDate.toIso8601String(),
                  'supplier_id': selectedSupplierId,
                  'amount_paid_on_creation': paymentType == 'cash' ? amountPaidOnCreation : 0.0,
                  'driver': driverController.text.trim().isEmpty ? 'غير محدد' : driverController.text.trim(),
                  'items': items,
                });

                try {
                  if (initial == null) {
                    final response = await http.post(
                      Uri.parse(_baseUrl),
                      headers: {'Content-Type': 'application/json'},
                      body: body,
                    );
                    if (response.statusCode == 200 || response.statusCode == 201) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم إضافة الشراء بنجاح!'), backgroundColor: Colors.green),
                      );
                      await _fetchAll();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('فشل الإضافة: ${response.statusCode} ${response.body}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } else {
                    await http.put(
                      Uri.parse('$_baseUrl/${initial['id']}'),
                      headers: {'Content-Type': 'application/json'},
                      body: body,
                    );
                    await http.post(
                      Uri.parse('$_baseUrl/${initial['id']}/items'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({'items': items}),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم تحديث الشراء بنجاح!'), backgroundColor: Colors.green),
                    );
                  }

                  Navigator.pop(context);
                  await _fetchAll();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ في الاتصال: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    ),
  );
}


  void _showAddMaterialDialog(StateSetter setDialogState, List<Map<String, dynamic>> items) {
    int? selectedTypeId;
    int? selectedMaterialId;
    List<dynamic> filteredMaterials = [];
    double quantity = 0.0;
    double unitPrice = 0.0;

    final TextEditingController quantityController = TextEditingController();
    final TextEditingController priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('إضافة مادة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: selectedTypeId,
                decoration: const InputDecoration(labelText: 'اختر نوع المادة'),
                items: _materialTypes.map((type) {
                  return DropdownMenuItem(
                    value: type['id'] as int,
                    child: Text(type['name'] as String),
                  );
                }).toList(),
                onChanged: (val) async {
                  selectedTypeId = val;
                  filteredMaterials = await _fetchMaterialsByType(val!);
                  setState(() {
                    selectedMaterialId = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: selectedMaterialId,
                decoration: const InputDecoration(labelText: 'اختر المادة'),
                items: filteredMaterials.map((m) {
                  return DropdownMenuItem(
                    value: m['id'] as int,
                    child: Text(m['code'] as String),
                  );
                }).toList(),
                onChanged: (val) => setState(() => selectedMaterialId = val),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'الكمية'),
                keyboardType: TextInputType.number,
                onChanged: (v) => quantity = double.tryParse(v) ?? 0.0,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'سعر الوحدة'),
                keyboardType: TextInputType.number,
                onChanged: (v) => unitPrice = double.tryParse(v) ?? 0.0,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedMaterialId != null && quantity > 0 && unitPrice > 0) {
                  setDialogState(() => items.add({
                        'material_id': selectedMaterialId,
                        'quantity': quantity,
                        'unit_price': unitPrice,
                      }));
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى ملء جميع الحقول بقيم صحيحة'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<dynamic>> _fetchMaterialsByType(int typeId) async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/materials/by_type/$typeId'));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return [];
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<void> _deletePurchase(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الشراء'),
        content: const Text('هل أنت متأكد من حذف هذا الشراء؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الشراء'), backgroundColor: Colors.green),
      );
      await _fetchAll();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selectedPurchase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 400,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            'مشتريات المواد الخام',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'بحث برقم الفاتورة أو اسم المورد',
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
                          // Show season dropdown only if seasons are available
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
                                  value: null,
                                  child: Text('جميع المواسم'),
                                ),
                                ..._seasons.map<DropdownMenuItem<int?>>((season) {
                                  return DropdownMenuItem<int?>(
                                    value: season['id'] as int,
                                    child: Text(season['name'] as String),
                                  );
                                }).toList(),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedSeasonId = val;
                                });
                                _fetchPurchases();
                              },
                            ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add, color: Colors.white),
                              label: const Text('شراء جديد', style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[600],
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => _showPurchaseDialog(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                    title: Text(
                                      'شراء رقم ${p['id']}',
                                      style: TextStyle(
                                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${_formatDate(p['purchase_date'])}'),
                                        Text('${p['supplier_name'] ?? ''}', style: TextStyle(color: Colors.teal[700])),
                                      ],
                                    ),
                                    onTap: () => setState(() => _selectedId = p['id']),
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
                  ],
                ),
              ),

              const VerticalDivider(width: 1),

              Expanded(
                child: sel == null || sel.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'اختر عملية شراء من القائمة الجانبية',
                              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تفاصيل شراء رقم ${sel['id']}',
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
                                    Text(
                                      'معلومات الشراء',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[800],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Icon(Icons.calendar_today, size: 20, color: Colors.blue),
                                        const SizedBox(width: 8),
                                        Text('التاريخ: ${_formatDate(sel['purchase_date'])}'),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.store, size: 20, color: Colors.blue),
                                        const SizedBox(width: 8),
                                        Text('المورد: ${sel['supplier_name'] ?? ''}'),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
Row(
  children: [
    const Icon(Icons.local_shipping, size: 20, color: Colors.blue),
    const SizedBox(width: 8),
    Text('السائق: ${sel['driver'] ?? 'غير محدد'}'),
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
                                child: Builder(builder: (_) {
                                  final total = _parseDouble(sel['total']) ?? 0.0;
                                  final paid0 = _parseDouble(sel['amount_paid_on_creation']) ?? 0.0;
                                  final extra = _parseDouble(sel['extra_paid']) ?? 0.0;
                                  final paid = paid0 + extra;
                                  final rem = (total - paid).clamp(0.0, double.infinity);
                                  final status = paid >= total ? 'مدفوع بالكامل' : paid > 0 ? 'مدفوع جزئياً' : 'غير مدفوع';
                                  
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                            child: _costItem('الإجمالي', total, Colors.green[700]!),
                                          ),
                                          Expanded(
                                            child: _costItem('مدفوع', paid, Colors.blue[700]!),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _costItem('المتبقي', rem, Colors.orange[700]!),
                                          ),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: paid >= total ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: (paid >= total ? Colors.green : Colors.orange).withOpacity(0.3)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'الحالة',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: paid >= total ? Colors.green[700] : Colors.orange[700],
                                                    ),
                                                  ),
                                                  Text(
                                                    status,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: paid >= total ? Colors.green[700] : Colors.orange[700],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),

                            const SizedBox(height: 24),

                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'تفاصيل المواد',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                                        headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                                        headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        columns: const [
                                          DataColumn(label: Text('المادة')),
                                          DataColumn(label: Text('النوع')),
                                          DataColumn(label: Text('الكمية')),
                                          DataColumn(label: Text('سعر الوحدة')),
                                          DataColumn(label: Text('الإجمالي')),
                                        ],
                                        rows: (sel['items'] as List<dynamic>).map<DataRow>((it) {
                                          final subtotal = (_parseDouble(it['quantity']) ?? 0.0) * (_parseDouble(it['unit_price']) ?? 0.0);
                                          return DataRow(cells: [
                                            DataCell(Text('${it['material_code'] ?? 'غير محدد'}')),
                                            DataCell(Text('${it['type_name'] ?? ''}')),
                                            DataCell(Text(it['quantity'].toString())),
                                            DataCell(Text('${it['unit_price']} دج')),
                                            DataCell(Text('${subtotal.toStringAsFixed(2)} دج')),
                                          ]);
                                        }).toList(),
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _costItem(String label, dynamic value, Color color, {bool isTotal = false}) {
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
            '${(value ?? 0.0).toStringAsFixed(2)} دج',
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
}
