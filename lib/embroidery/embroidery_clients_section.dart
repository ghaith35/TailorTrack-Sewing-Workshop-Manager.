import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../main.dart';

class EmbroideryClientsSection extends StatefulWidget {
  const EmbroideryClientsSection({super.key});

  @override
  State<EmbroideryClientsSection> createState() => _EmbroideryClientsSectionState();
}

class _EmbroideryClientsSectionState extends State<EmbroideryClientsSection> {
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchController = TextEditingController();
String get _apiUrl => '${globalServerUri.toString()}/embrodry/clients/';

  @override
  void initState() {
    super.initState();
    _fetchClients();
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
      _filtered = _clients.where((c) {
        final name    = (c['full_name'] ?? '').toString().toLowerCase();
        final phone   = (c['phone']     ?? '').toString().toLowerCase();
        final address = (c['address']   ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q) || address.contains(q);
      }).toList();
    });
  }

  Future<void> _fetchClients() async {
    try {
      final res = await http.get(Uri.parse(_apiUrl));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        _clients = list.cast<Map<String, dynamic>>();
        _clients.sort((a,b) => a['full_name'].compareTo(b['full_name']));
        setState(() => _filtered = List.from(_clients));
      } else {
        throw Exception('Server error ${res.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في جلب العملاء: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 1) Add this helper to your State class:
void _showSnackBar(String msg, {Color color = Colors.red}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: color),
  );
}

// 2) Replace your existing _showClientDialog with this:
Future<void> _showClientDialog({Map<String, dynamic>? existing}) async {
  final isEdit = existing != null;
  final _formKey = GlobalKey<FormState>();

  final nameCtl  = TextEditingController(text: existing?['full_name'] ?? '');
  final phoneCtl = TextEditingController(text: existing?['phone']     ?? '');
  final addrCtl  = TextEditingController(text: existing?['address']   ?? '');

  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(isEdit ? 'تعديل عميل' : 'إضافة عميل'),
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
                    return 'رقم يجب أن يبدأ ب0 ويحتوي على 10 أرقام';
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
              'full_name': nameCtl.text.trim(),
              'phone'    : phoneCtl.text.trim(),
              'address'  : addrCtl.text.trim(),
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
              await _fetchClients();
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
        title: const Text('حذف عميل'),
        content: const Text('هل أنت متأكد من حذف هذا العميل؟'),
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
        if (res.statusCode != 200) throw Exception('حذف فشل');
        _fetchClients();
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
                    labelText: 'بحث بالعميل',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              IconButton(onPressed: _fetchClients, icon: const Icon(Icons.refresh)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showClientDialog(),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('إضافة عميل'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),

        // DataTable
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
              headingTextStyle:
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              columns: const [
                DataColumn(label: Text('الاسم الكامل')),
                DataColumn(label: Text('رقم الهاتف')),
                DataColumn(label: Text('العنوان')),
                DataColumn(label: Text('خيارات')),
              ],
              rows: _filtered.map((c) {
                return DataRow(cells: [
                  DataCell(Text(c['full_name'] ?? '-')),
                  DataCell(Text(c['phone']     ?? '-')),
                  DataCell(Text(c['address']   ?? '-')),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.secondary),
                        onPressed: () => _showClientDialog(existing: c),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDelete(c['id']),
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
