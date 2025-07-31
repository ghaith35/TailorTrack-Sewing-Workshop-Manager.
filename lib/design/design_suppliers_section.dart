// lib/design_suppliers_section.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../main.dart';

class DesignSuppliersSection extends StatefulWidget {
  const DesignSuppliersSection({super.key});

  @override
  State<DesignSuppliersSection> createState() => _DesignSuppliersSectionState();
}

class _DesignSuppliersSectionState extends State<DesignSuppliersSection> {
String get _apiUrl => '${globalServerUri.toString()}/design/suppliers/';
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _fetchSuppliers();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _suppliers.where((s) {
        final name = (s['full_name'] ?? '').toString().toLowerCase();
        final company = (s['company_name'] ?? '').toString().toLowerCase();
        return name.contains(q) || company.contains(q);
      }).toList();
    });
  }

  Future<void> _fetchSuppliers() async {
    try {
      final res = await http.get(Uri.parse(_apiUrl));
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        _suppliers = list.cast<Map<String, dynamic>>();
        _suppliers.sort((a, b) =>
            a['full_name'].toString().compareTo(b['full_name'].toString()));
        setState(() => _filtered = List.from(_suppliers));
      } else {
        throw Exception('Server error ${res.statusCode}');
      }
    } catch (e) {
      _showSnack('خطأ في جلب الموردين: $e', isError: true);
    }
  }

  Future<void> _showSupplierDialog({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final _formKey = GlobalKey<FormState>();
    final nameCtrl  = TextEditingController(text: existing?['full_name'] ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone'] ?? '');
    final addrCtrl  = TextEditingController(text: existing?['address'] ?? '');
    final compCtrl  = TextEditingController(text: existing?['company_name'] ?? '');

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? 'تعديل مورد' : 'إضافة مورد'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'الاسم مطلوب';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'رقم الهاتف مطلوب';
                    }
                    // بضعة تحققات بسيطة:
                    if (!RegExp(r'^\+?\d{8,15}$').hasMatch(v.trim())) {
                      return 'رقم غير صالح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: addrCtrl,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'العنوان مطلوب';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: compCtrl,
                  decoration:
                      const InputDecoration(labelText: 'اسم الشركة (اختياري)'),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (!_formKey.currentState!.validate()) return;

              final payload = {
                'full_name': nameCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
                'address': addrCtrl.text.trim(),
                'company_name':
                    compCtrl.text.trim().isEmpty ? null : compCtrl.text.trim(),
              };
              try {
                http.Response res;
                if (isEdit) {
                  res = await http.put(
                    Uri.parse('$_apiUrl${existing!['id']}'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  );
                  if (res.statusCode != 200) throw Exception(res.statusCode);
                } else {
                  res = await http.post(
                    Uri.parse(_apiUrl),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  );
                  if (res.statusCode != 201) throw Exception(res.statusCode);
                }
                Navigator.pop(context);
                _fetchSuppliers();
                _showSnack('تم الحفظ بنجاح');
              } catch (e) {
                _showSnack('خطأ في الحفظ: $e', isError: true);
              }
            },
            child: Text(isEdit ? 'تحديث' : 'حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف مورد'),
        content: const Text('هل أنت متأكد من حذف هذا المورد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final res = await http.delete(Uri.parse('$_apiUrl$id'));
        if (res.statusCode != 200) throw Exception(res.statusCode);
        _fetchSuppliers();
        _showSnack('تم الحذف');
      } catch (e) {
        _showSnack('فشل الحذف: $e', isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'بحث...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showSupplierDialog(),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('إضافة مورد'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),

        // Table
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(
                Theme.of(context).colorScheme.primary,
              ),
              headingTextStyle: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold,
              ),
              columns: const [
                DataColumn(label: Text('الاسم الكامل')),
                DataColumn(label: Text('رقم الهاتف')),
                DataColumn(label: Text('العنوان')),
                DataColumn(label: Text('اسم الشركة')),
                DataColumn(label: Text('خيارات')),
              ],
              rows: _filtered.map((s) {
                return DataRow(cells: [
                  DataCell(Text(s['full_name'] ?? '-')),
                  DataCell(Text(s['phone'] ?? '-')),
                  DataCell(Text(s['address'] ?? '-')),
                  DataCell(Text(s['company_name'] ?? '-')),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit,
                            color: Theme.of(context).colorScheme.secondary),
                        onPressed: () => _showSupplierDialog(existing: s),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDelete(s['id']),
                      ),
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
