import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SewingSuppliersSection extends StatefulWidget {
  const SewingSuppliersSection({super.key});

  @override
  State<SewingSuppliersSection> createState() => _SewingSuppliersSectionState();
}

class _SewingSuppliersSectionState extends State<SewingSuppliersSection> {
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchController = TextEditingController();
  final String _apiUrl = 'http://127.0.0.1:8888/suppliers/';

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
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _suppliers.where((s) {
        final name = (s['full_name'] ?? '').toString().toLowerCase();
        final company = (s['company_name'] ?? '').toString().toLowerCase();
        return name.contains(query) || company.contains(query);
      }).toList();
    });
  }

  Future<void> _fetchSuppliers() async {
    try {
      final res = await http.get(Uri.parse(_apiUrl));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final List<dynamic> list = jsonDecode(res.body);
        _suppliers = list.cast<Map<String, dynamic>>();
        _suppliers.sort((a, b) =>
            a['full_name'].toString().compareTo(b['full_name'].toString()));
        setState(() => _filtered = List.from(_suppliers));
      } else {
        throw Exception('Server error ${res.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في جلب الموردين: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showSupplierDialog({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['full_name'] ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone'] ?? '');
    final addrCtrl = TextEditingController(text: existing?['address'] ?? '');
    final compCtrl =
        TextEditingController(text: existing?['company_name'] ?? '');
    final _formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(isEdit ? 'تعديل مورد' : 'إضافة مورد'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'الاسم الكامل'),
                    validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: phoneCtrl,
                    decoration:
                        const InputDecoration(labelText: 'رقم الهاتف'),
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'مطلوب';
                      final phone = v.trim();
                      if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
                        return 'رقم الهاتف يجب أن يبدأ بـ 0 ويحتوي على 10 أرقام';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: addrCtrl,
                    decoration: const InputDecoration(labelText: 'العنوان'),
                    validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: compCtrl,
                    decoration: const InputDecoration(
                        labelText: 'اسم الشركة (اختياري)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
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
                  late http.Response res;
                  if (isEdit) {
                    final uri =
                        Uri.parse(_apiUrl).resolve('${existing!['id']}');
                    res = await http.put(
                      uri,
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(payload),
                    );
                  } else {
                    res = await http.post(
                      Uri.parse(_apiUrl),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(payload),
                    );
                  }

                  if (res.statusCode < 200 || res.statusCode >= 300) {
                    throw Exception('HTTP ${res.statusCode}');
                  }

                  Navigator.of(dialogContext).pop();
                  _fetchSuppliers();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('خطأ في الحفظ: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: Text(isEdit ? 'تحديث' : 'حفظ'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('حذف مورد'),
        content: const Text('هل أنت متأكد من حذف هذا المورد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final uri = Uri.parse(_apiUrl).resolve('$id');
        final res = await http.delete(uri);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('HTTP ${res.statusCode}');
        }
        _fetchSuppliers();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'بحث بالمورد',
                    prefixIcon: Icon(Icons.search),
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
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Scrollbar(
              thumbVisibility: true,
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
                            icon: Icon(
                              Icons.edit,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
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
          ),
        ),
      ],
    );
  }
}
