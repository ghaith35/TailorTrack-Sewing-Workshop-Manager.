import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../main.dart';

class EmbroiderySuppliersSection extends StatefulWidget {
  const EmbroiderySuppliersSection({super.key});

  @override
  State<EmbroiderySuppliersSection> createState() => _EmbroiderySuppliersSectionState();
}

class _EmbroiderySuppliersSectionState extends State<EmbroiderySuppliersSection> {
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _filtered  = [];
  final _searchController = TextEditingController();
String get _apiUrl => '${globalServerUri.toString()}/embrodry/suppliers/';

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
        final name    = (s['full_name']    ?? '').toString().toLowerCase();
        final company = (s['company_name'] ?? '').toString().toLowerCase();
        return name.contains(q) || company.contains(q);
      }).toList();
    });
  }

  Future<void> _fetchSuppliers() async {
    try {
      final res = await http.get(Uri.parse(_apiUrl));
      if (res.statusCode == 200) {
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
        SnackBar(content: Text('خطأ في جلب الموردين: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // add this helper to your State class (above or below _applyFilter, etc.)
void _showSnackBar(String msg, {Color color = Colors.red}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: color),
  );
}

// replace your existing _showSupplierDialog with this:

Future<void> _showSupplierDialog({Map<String, dynamic>? existing}) async {
  final isEdit = existing != null;
  final _formKey = GlobalKey<FormState>();

  final nameCtl  = TextEditingController(text: existing?['full_name']    ?? '');
  final phoneCtl = TextEditingController(text: existing?['phone']        ?? '');
  final addrCtl  = TextEditingController(text: existing?['address']      ?? '');
  final compCtl  = TextEditingController(text: existing?['company_name'] ?? '');

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
              // Full name
              TextFormField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                validator: (v) =>
                  v == null || v.trim().isEmpty
                    ? 'الاسم الكامل مطلوب'
                    : null,
              ),
              const SizedBox(height: 8),
              // Phone
              TextFormField(
                controller: phoneCtl,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'رقم الهاتف مطلوب';
                  }
                  final trimmed = v.trim();
                  if (!trimmed.startsWith('0') || trimmed.length != 10 || int.tryParse(trimmed) == null) {
                    return 'رقم يجب أن يبدأ بـ0 ويحتوي على 10 أرقام';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              // Address
              TextFormField(
                controller: addrCtl,
                decoration: const InputDecoration(labelText: 'العنوان'),
                validator: (v) =>
                  v == null || v.trim().isEmpty
                    ? 'العنوان مطلوب'
                    : null,
              ),
              const SizedBox(height: 8),
              // Company (optional)
              TextFormField(
                controller: compCtl,
                decoration: const InputDecoration(labelText: 'اسم الشركة (اختياري)'),
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
              'full_name'   : nameCtl.text.trim(),
              'phone'       : phoneCtl.text.trim(),
              'address'     : addrCtl.text.trim(),
              'company_name': compCtl.text.trim().isNotEmpty
                                ? compCtl.text.trim()
                                : null,
            };

            try {
              final uri = isEdit
                ? Uri.parse(_apiUrl).resolve('${existing!['id']}/')
                : Uri.parse(_apiUrl);
              final res = isEdit
                ? await http.put(uri,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload))
                : await http.post(uri,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload));

              if (res.statusCode < 200 || res.statusCode >= 300) {
                String msg = 'خطأ ${res.statusCode}';
                try {
                  final body = jsonDecode(res.body);
                  if (body['error'] != null) msg = body['error'];
                } catch (_) {}
                throw Exception(msg);
              }
              Navigator.pop(context);
              await _fetchSuppliers();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم الحفظ'), backgroundColor: Colors.green),
              );
            } catch (e) {
              final text = e.toString().replaceFirst('Exception: ', '');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('خطأ في الحفظ: $text'), backgroundColor: Colors.red),
              );
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final uri = Uri.parse(_apiUrl).resolve('$id');
        final res = await http.delete(uri);
        if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('فشل الحذف');
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
        // Search + Refresh + Add
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
              IconButton(onPressed: _fetchSuppliers, icon: const Icon(Icons.refresh)),
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
                  DataCell(Text(s['full_name']    ?? '-')),
                  DataCell(Text(s['phone']        ?? '-')),
                  DataCell(Text(s['address']      ?? '-')),
                  DataCell(Text(s['company_name'] ?? '-')),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.secondary),
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
