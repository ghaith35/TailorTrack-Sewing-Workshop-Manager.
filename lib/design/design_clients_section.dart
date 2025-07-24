import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DesignClientsSection extends StatefulWidget {
  const DesignClientsSection({super.key});

  @override
  State<DesignClientsSection> createState() => _DesignClientsSectionState();
}

class _DesignClientsSectionState extends State<DesignClientsSection> {
  final String _apiUrl = 'http://127.0.0.1:8888/design/clients/';
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _filtered = [];

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

  // ───────────────────── Helpers ─────────────────────

  void _applyFilter() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _clients.where((c) {
        final name = (c['full_name'] ?? '').toString().toLowerCase();
        final phone = (c['phone'] ?? '').toString().toLowerCase();
        final addr = (c['address'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q) || addr.contains(q);
      }).toList();
    });
  }

  Future<void> _fetchClients() async {
    try {
      final res = await http.get(Uri.parse(_apiUrl));
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        _clients = list.cast<Map<String, dynamic>>();
        _clients.sort((a, b) =>
            a['full_name'].toString().compareTo(b['full_name'].toString()));
        setState(() => _filtered = List.from(_clients));
      } else {
        throw Exception('Server error ${res.statusCode}');
      }
    } catch (e) {
      _snack('خطأ في جلب العملاء: $e', error: true);
    }
  }

  Future<void> _showClientDialog({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final nameCtrl  = TextEditingController(text: existing?['full_name'] ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone'] ?? '');
    final addrCtrl  = TextEditingController(text: existing?['address'] ?? '');

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? 'تعديل عميل' : 'إضافة عميل'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl,  decoration: const InputDecoration(labelText: 'الاسم الكامل')),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'رقم الهاتف'), keyboardType: TextInputType.phone),
              const SizedBox(height: 8),
              TextField(controller: addrCtrl,  decoration: const InputDecoration(labelText: 'العنوان')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final payload = {
                'full_name': nameCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
                'address': addrCtrl.text.trim(),
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
                _fetchClients();
                _snack('تم الحفظ بنجاح');
              } catch (e) {
                _snack('خطأ في الحفظ: $e', error: true);
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
        _fetchClients();
        _snack('تم الحذف');
      } catch (e) {
        _snack('فشل الحذف: $e', error: true);
      }
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : Colors.green),
    );
  }

  // ───────────────────── UI ─────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search + Add
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
                DataColumn(label: Text('خيارات')),
              ],
              rows: _filtered.map((c) {
                return DataRow(cells: [
                  DataCell(Text(c['full_name'] ?? '-')),
                  DataCell(Text(c['phone'] ?? '-')),
                  DataCell(Text(c['address'] ?? '-')),
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
