import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SewingClientsSection extends StatefulWidget {
  const SewingClientsSection({super.key});

  @override
  State<SewingClientsSection> createState() => _SewingClientsSectionState();
}

class _SewingClientsSectionState extends State<SewingClientsSection> {
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchController = TextEditingController();
  final String _apiUrl = 'http://127.0.0.1:8888/clients/';

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
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _clients.where((c) {
        final name = (c['full_name'] ?? '').toString().toLowerCase();
        final phone = (c['phone'] ?? '').toString().toLowerCase();
        final address = (c['address'] ?? '').toString().toLowerCase();
        return name.contains(query) ||
               phone.contains(query) ||
               address.contains(query);
      }).toList();
    });
  }

  Future<void> _fetchClients() async {
    try {
      final res = await http.get(Uri.parse(_apiUrl));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        _clients = list.cast<Map<String, dynamic>>();
        _clients.sort((a, b) =>
          a['full_name'].toString().compareTo(b['full_name'].toString()));
        setState(() => _filtered = List.from(_clients));
      } else {
        throw Exception('Server error ${res.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في جلب العملاء: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showClientDialog({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['full_name'] ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone'] ?? '');
    final addrCtrl = TextEditingController(text: existing?['address'] ?? '');

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? 'تعديل عميل' : 'إضافة عميل'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'الاسم الكامل'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(labelText: 'العنوان'),
              ),
            ],
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
              final payload = {
                'full_name': nameCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
                'address': addrCtrl.text.trim(),
              };
              try {
                if (isEdit) {
                  final uri = Uri.parse(_apiUrl).resolve('${existing!['id']}');
                  final res = await http.put(
                    uri,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  );
                  if (res.statusCode != 200) throw Exception(res.statusCode);
                } else {
                  final res = await http.post(
                    Uri.parse(_apiUrl),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  );
                  if (res.statusCode != 201) throw Exception(res.statusCode);
                }
                Navigator.pop(context);
                _fetchClients();
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
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
        if (res.statusCode != 200) throw Exception(res.statusCode);
        _fetchClients();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الحذف: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top bar: Search + Add button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
                        children: [
                          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const SizedBox(width: 8),
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
              IconButton(
                tooltip: 'تحديث',
                onPressed: _fetchClients,
                icon: const Icon(Icons.refresh),
              ),],),
        // Padding(
        //   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        //   child: Row(
        //     children: [
        //       SizedBox(
        //         width: 200,
        //         child: TextField(
        //           controller: _searchController,
        //           decoration: InputDecoration(
        //             hintText: 'بحث...',
        //             prefixIcon: const Icon(Icons.search),
        //             filled: true,
        //             fillColor: Colors.white,
        //             border: OutlineInputBorder(
        //               borderRadius: BorderRadius.circular(8),
        //               borderSide: BorderSide.none,
        //             ),
        //             contentPadding: const EdgeInsets.symmetric(vertical: 0),
        //           ),
        //         ),
        //       ),
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
                        icon: Icon(
                          Icons.edit,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
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
