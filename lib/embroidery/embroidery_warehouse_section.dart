// lib/embroidery/embroidery_warehouse_section.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class EmbroideryWarehouseSection extends StatefulWidget {
  const EmbroideryWarehouseSection({Key? key}) : super(key: key);

  @override
  State<EmbroideryWarehouseSection> createState() =>
      _EmbroideryWarehouseSectionState();
}

class _EmbroideryWarehouseSectionState
    extends State<EmbroideryWarehouseSection> {
  // ── Tabs ─────────────────────────────────────────────────────
  int _tab = 0;
  final _tabs = const ['المخزون الجاهز', 'المواد الخام'];

  // ── Endpoints ───────────────────────────────────────────────
  final String _modelsBase    = 'http://127.0.0.1:8888/embrodry/models';
  final String _warehouseBase = 'http://127.0.0.1:8888/embrodry/warehouse';

  // ── Helpers ─────────────────────────────────────────────────
  String s(dynamic v) => v == null ? '—' : v.toString();
  double n(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
  String money(dynamic v) => n(v).toStringAsFixed(2);
  String formatYMD(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final d = DateTime.parse(dateStr.toString());
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr.toString().split('T').first;
    }
  }

  // ── “المخزون الجاهز” state ─────────────────────────────────────
  List<Map<String, dynamic>> _ready = [];
  bool _loadingReady = false;
  String? _errReady;

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _seasons = [];
  int? _clientFilter;
  int? _seasonFilter;
  final TextEditingController _searchCtl = TextEditingController();

  // ── “المواد الخام” state ───────────────────────────────────────
  List<dynamic> _types = [];
  int? _selectedTypeId;
  List<dynamic> _specs = [];
  List<dynamic> _materials = [];
  bool _loadingTypes = false;
  bool _loadingMaterials = false;

  // Scroll controllers
  final _hReady = ScrollController();
  final _vReady = ScrollController();
  final _hRaw   = ScrollController();
  final _vRaw   = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchFilters();
    _fetchReady();
    _fetchTypes();
    _searchCtl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _hReady.dispose();
    _vReady.dispose();
    _hRaw.dispose();
    _vRaw.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  // ── Load client/season lists ─────────────────────────────────
  Future<void> _fetchFilters() async {
    try {
      final cRes = await http.get(Uri.parse('$_modelsBase/clients'));
      final sRes = await http.get(Uri.parse('$_modelsBase/seasons'));
      if (cRes.statusCode == 200) {
        _clients = List<Map<String, dynamic>>.from(jsonDecode(cRes.body));
      }
      if (sRes.statusCode == 200) {
        _seasons = List<Map<String, dynamic>>.from(jsonDecode(sRes.body));
      }
      setState(() {});
    } catch (_) {}
  }

  // ── Fetch ready inventory ─────────────────────────────────────
  Future<void> _fetchReady() async {
    setState(() {
      _loadingReady = true;
      _errReady = null;
    });
    try {
      final uri = Uri.parse('$_warehouseBase/product-inventory')
          .replace(queryParameters: {
        if (_clientFilter != null) 'client_id': '$_clientFilter',
        if (_seasonFilter != null) 'season_id': '$_seasonFilter',
      });
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        _ready = List<Map<String, dynamic>>.from(jsonDecode(res.body));
      } else {
        _errReady = '(${res.statusCode}) فشل تحميل البيانات';
      }
    } catch (e) {
      _errReady = 'خطأ: $e';
    } finally {
      setState(() => _loadingReady = false);
    }
  }

  List<Map<String, dynamic>> get _filteredReady {
    final q = _searchCtl.text.trim().toLowerCase();
    return _ready.where((r) {
      if (n(r['quantity']) <= 0) return false;
      if (_clientFilter != null && r['client_id'] != _clientFilter) return false;
      if (_seasonFilter != null && r['season_id'] != _seasonFilter) return false;
      if (q.isNotEmpty &&
          !r['model_name'].toString().toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _editReady(int id, double currentQty) async {
    final ctl = TextEditingController(text: currentQty.toString());
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تعديل الكمية'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(labelText: 'الكمية'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final q = double.tryParse(ctl.text) ?? 0;
              final res = await http.put(
                Uri.parse('$_warehouseBase/product-inventory/$id'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'quantity': q}),
              );
              Navigator.pop(context);
              if (res.statusCode == 200) _fetchReady();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
Future<void> _fetchTypes() async {
    setState(() => _loadingTypes = true);
    try {
      final res = await http.get(Uri.parse('$_warehouseBase/material-types'));
      if (res.statusCode == 200) {
        _types = jsonDecode(res.body);
        if (_types.isNotEmpty && _selectedTypeId == null) {
          _selectedTypeId = _types.first['id'];
          await _fetchMaterialsForType(_selectedTypeId!);
        }
      }
    } finally {
      setState(() => _loadingTypes = false);
    }
  }

  Future<void> _fetchMaterialsForType(int tid) async {
    setState(() {
      _loadingMaterials = true;
      _specs = [];
      _materials = [];
    });
    try {
      final res = await http.get(
          Uri.parse('$_warehouseBase/materials?type_id=$tid'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _specs = data['specs'];
        _materials = data['materials'];
      }
    } finally {
      setState(() => _loadingMaterials = false);
    }
  }
  Future<void> _deleteReady(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      final res = await http.delete(
        Uri.parse('$_warehouseBase/product-inventory/$id'),
      );
      if (res.statusCode == 200) _fetchReady();
    }
  }

  void _viewReady(Map<String, dynamic> r) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تفاصيل المخزون #${r['id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _infoRow('الموديل', r['model_name']),
            _infoRow('النوع', r['model_type']),
            _infoRow('التاريخ', formatYMD(r['model_date'])),
            _infoRow('سعر الغرزة', money(r['stitch_price'])),
            _infoRow('عدد الغرز', r['stitch_number'].toString()),
            _infoRow('السعر الإجمالي', money(r['total_price'])),
            _infoRow('الكمية', money(r['quantity'])),
            _infoRow('العميل', s(r['client_name'])),
            _infoRow('الموسم', s(r['season_name'])),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))
        ],
      ),
    );
  }

  // ── Import from models ──────────────────────────────────────
//   Future<void> _addFromModelDialog() async {
//     List<Map<String, dynamic>> models = [];
//     bool loading = true;
//     String? err;
//     int? modelId;
//     double qty = 0;
//     final qtyCtl = TextEditingController();

//     await showDialog(
//       context: context,
//       builder: (_) => StatefulBuilder(builder: (ctx, setD) {
//         if (loading) {
//           http.get(Uri.parse('$_modelsBase')).then((r) {
//             if (r.statusCode == 200) {
//               models = List<Map<String, dynamic>>.from(jsonDecode(r.body));
//             } else {
//               err = '(${r.statusCode})';
//             }
//             setD(() => loading = false);
//           }).catchError((e) => setD(() {
//                 err = 'خطأ $e';
//                 loading = false;
//               }));
//         }

//         bool canSave() => modelId != null && qty > 0;

//         return AlertDialog(
//           title: const Text('إضافة من الموديلات'),
//           content: SizedBox(
//             width: 360,
//             child: loading
//                 ? const Center(child: CircularProgressIndicator())
//                 : err != null
//                     ? Text(err!)
//                     : Column(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           DropdownButtonFormField<int>(
//                             value: modelId,
//                             decoration: const InputDecoration(labelText: 'اختر الموديل'),
//                             items: [
//                               for (var m in models)
//                                 DropdownMenuItem(
//                                   value: m['id'] as int,
//                                   child: Text('${m['model_name']} (#${m['id']})'),
//                                 )
//                             ],
//                             onChanged: (v) => setD(() => modelId = v),
//                           ),
//                           const SizedBox(height: 12),
//                           TextField(
//                             controller: qtyCtl,
//                             decoration: const InputDecoration(labelText: 'الكمية'),
//                             keyboardType: TextInputType.number,
//                             onChanged: (t) {
//                               qty = double.tryParse(t) ?? 0;
//                               setD(() {});
//                             },
//                           ),
//                         ],
//                       ),
//           ),
//           actions: [
//             TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
//             ElevatedButton(
//               onPressed: !canSave()
//                   ? null
//                   : () async {
//                       final body = jsonEncode({
//                         'warehouse_id': 1,
//                         'model_id': modelId,
//                         'quantity': qty,
//                       });
//                       final r = await http.post(
//                         Uri.parse('$_warehouseBase/product-inventory'),
//                         headers: {'Content-Type': 'application/json'},
//                         body: body,
//                       );
//                       if (r.statusCode == 200) {
//                         Navigator.pop(ctx);
//                         _fetchReady();
//                       } else {
//                         ScaffoldMessenger.of(context).showSnackBar(
//                           SnackBar(content: Text('فشل الإضافة (${r.statusCode})')),
//                         );
//                       }
//                     },
//               child: const Text('حفظ'),
//             ),
//           ],
//         );
//       }),
//     );
//   }

  // ── UI for “المخزون الجاهز” ─────────────────────────────────
  Widget _readyTab() {
    if (_loadingReady) return const Center(child: CircularProgressIndicator());
    if (_errReady != null) return Center(child: Text(_errReady!));

    final rows = _filteredReady;

    return Column(
      children: [
        // Filters + import + refresh
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  value: _clientFilter,
                  decoration: const InputDecoration(labelText: 'العميل'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('الكل')),
                    for (var c in _clients)
                      DropdownMenuItem(
                        value: c['id'] as int,
                        child: Text(s(c['full_name'])),
                      )
                  ],
                  onChanged: (v) => setState(() => _clientFilter = v),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  value: _seasonFilter,
                  decoration: const InputDecoration(labelText: 'الموسم'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('الكل')),
                    for (var s0 in _seasons)
                      DropdownMenuItem(
                        value: s0['id'] as int,
                        child: Text(s0['name']),
                      )
                  ],
                  onChanged: (v) => setState(() => _seasonFilter = v),
                ),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchCtl,
                  decoration: const InputDecoration(
                      labelText: 'بحث', prefixIcon: Icon(Icons.search)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addFromModelDialog,
                icon: const Icon(Icons.add),
                label: const Text('إضافة من الموديلات'),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _fetchReady,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),

        // DataTable
        Expanded(
          child: Scrollbar(
            controller: _hReady,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _hReady,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 800),
                child: Scrollbar(
                  controller: _vReady,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _vReady,
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(
                        Theme.of(context).colorScheme.primary,
                      ),
                      headingTextStyle: _wh,
                      columns: const [
                        DataColumn(label: Text('الموديل')),
                        DataColumn(label: Text('النوع')),
                        DataColumn(label: Text('التاريخ')),
                        DataColumn(label: Text('سعر الغرزة')),
                        DataColumn(label: Text('عدد الغرز')),
                        DataColumn(label: Text('السعر الإجمالي')),
                                                DataColumn(label: Text('الكمية')),

                        DataColumn(label: Text('خيارات')),
                      ],
                      rows: rows.map((r) {
                        return DataRow(cells: [
                          DataCell(Text(s(r['model_name']))),
                          DataCell(Text(s(r['model_type']))),
                          DataCell(Text(formatYMD(r['model_date']))),
                          DataCell(Text(money(r['stitch_price']))),
                          DataCell(Text(r['stitch_number'].toString())),
                          DataCell(Text(money(r['total_price']))),
                                                    DataCell(Text(money(r['quantity']))),

                          DataCell(Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.visibility, color: Colors.blue),
                                onPressed: () => _viewReady(r),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.teal),
                                onPressed: () => _editReady(r['id'], n(r['quantity'])),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteReady(r['id']),
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
      ],
    );
  }

  // ── UI for “المواد الخام” ───────────────────────────────────
  Widget _rawTab() {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        // Sidebar: material types
        Container(
          width: 350,
          color: Colors.grey[100],
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('أنواع المواد الخام',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800])),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _addOrEditType(),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text('إضافة نوع', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[600]),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loadingTypes
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _types.length,
                        itemBuilder: (_, i) {
                          final t = _types[i];
                          final sel = t['id'] == _selectedTypeId;
                          return Card(
                            color: sel ? Colors.grey[100] : Colors.white,
                            elevation: sel ? 3 : 1,
                            child: ListTile(
                              title: Text(t['name']),
                              selected: sel,
                              onTap: () {
                                setState(() {
                                  _selectedTypeId = t['id'];
                                });
                                _fetchMaterialsForType(t['id']);
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.teal),
                                      onPressed: () => _addOrEditType(t)),
                                  IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteType(t['id'])),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              )
            ],
          ),
        ),

        const VerticalDivider(width: 1),

        // Main materials table
        Expanded(
          child: _loadingMaterials
              ? const Center(child: CircularProgressIndicator())
              : (_selectedTypeId == null
                  ? Center(child: Text('اختر نوع مادة من القائمة الجانبية'))
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => _addOrEditMaterial(),
                                icon: const Icon(Icons.add),
                                label: const Text('إضافة مادة'),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                  onPressed: () => _fetchMaterialsForType(_selectedTypeId!),
                                  icon: const Icon(Icons.refresh)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Scrollbar(
                            controller: _hRaw,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _hRaw,
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minWidth: 800),
                                child: Scrollbar(
                                  controller: _vRaw,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _vRaw,
                                    child: DataTable(
                                      headingRowColor: MaterialStateProperty.all(
                                        Theme.of(context).colorScheme.primary,
                                      ),
                                      headingTextStyle: _wh,
                                      columns: [
                                        const DataColumn(label: Text('الكود')),
                                        const DataColumn(label: Text('الكمية')),
                                        const DataColumn(label: Text('آخر سعر')),
                                        ..._specs
                                            .map((s0) => DataColumn(label: Text(s0['name'])))
                                            .toList(),
                                        const DataColumn(label: Text('خيارات')),
                                      ],
                                      rows: _materials.map((m) {
                                        final vals = m['specs'] as List;
                                        return DataRow(cells: [
                                          DataCell(Text(m['code'])),
                                          DataCell(Text(money(m['stock_quantity']))),
                                          DataCell(Text(money(m['last_unit_price']))),
                                          ...vals
                                              .map((v) => DataCell(Text(v['value'])))
                                              .toList(),
                                          DataCell(Row(
                                            children: [
                                              IconButton(
                                                  icon: const Icon(Icons.edit, color: Colors.teal),
                                                  onPressed: () => _addOrEditMaterial(m)),
                                              IconButton(
                                                  icon: const Icon(Icons.delete, color: Colors.red),
                                                  onPressed: () => _deleteMaterial(m['id'])),
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
                      ],
                    )),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // Choice chips for tabs
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_tabs.length, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ChoiceChip(
                    label: Text(_tabs[i]),
                    selected: _tab == i,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    labelStyle: TextStyle(
                      color: _tab == i
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) => setState(() => _tab = i),
                  ),
                );
              }),
            ),
          ),
          Expanded(child: _tab == 0 ? _readyTab() : _rawTab()),
        ],
      ),
    );
  }

  // ── Shared helpers ───────────────────────────────────────────
  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
                width: 100,
                child:
                    Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold))),
            Expanded(child: Text(value)),
          ],
        ),
      );

  // ── RAW MATERIALS: type management ───────────────────────────
//   Future<void> _addOrEditType([Map<String, dynamic>? t]) async {
//     final isEdit = t != null;
//     final nameCtl = TextEditingController(text: t?['name'] ?? '');
//     final specsList = t == null
//         ? <Map<String, dynamic>>[]
//         : (t['specs'] as List)
//             .map((e) => {'id': e['id'], 'name': e['name']})
//             .toList();

//     await showDialog(
//       context: context,
//       builder: (_) => StatefulBuilder(builder: (ctx, setD) {
//         return AlertDialog(
//           title: Text(isEdit ? 'تعديل نوع' : 'إضافة نوع'),
//           content: SizedBox(
//             width: 320,
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 TextField(
//                   controller: nameCtl,
//                   decoration: const InputDecoration(labelText: 'اسم النوع'),
//                 ),
//                 const SizedBox(height: 12),
//                 Row(
//                   children: [
//                     const Text('المواصفات', style: TextStyle(fontWeight: FontWeight.bold)),
//                     const Spacer(),
//                     IconButton(
//                         icon: const Icon(Icons.add),
//                         onPressed: () => setD(() => specsList.add({'name': ''}))),
//                   ],
//                 ),
//                 ...specsList.asMap().entries.map((e) {
//                   final i = e.key;
//                   return Row(
//                     children: [
//                       Expanded(
//                         child: TextField(
//                           controller: TextEditingController(text: specsList[i]['name']),
//                           onChanged: (v) => specsList[i]['name'] = v,
//                           decoration: const InputDecoration(labelText: 'اسم المواصفة'),
//                         ),
//                       ),
//                       IconButton(
//                           icon: const Icon(Icons.delete),
//                           onPressed: () => setD(() => specsList.removeAt(i))),
//                     ],
//                   );
//                 }),
//               ],
//             ),
//           ),
//           actions: [
//             TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
//             ElevatedButton(
//               onPressed: () async {
//                 final body = jsonEncode({
//                   'name': nameCtl.text.trim(),
//                   'specs': specsList
//                       .where((s) => (s['name'] as String).trim().isNotEmpty)
//                       .toList(),
//                 });
//                 final url = isEdit
//                     ? '$_warehouseBase/material-types/${t!['id']}'
//                     : '$_warehouseBase/material-types';
//                 final r = isEdit
//                     ? await http.put(Uri.parse(url),
//                         headers: {'Content-Type': 'application/json'}, body: body)
//                     : await http.post(Uri.parse(url),
//                         headers: {'Content-Type': 'application/json'}, body: body);
//                 if (r.statusCode == 200) {
//                   Navigator.pop(ctx);
//                   _fetchTypes();
//                 }
//               },
//               child: const Text('حفظ'),
//             ),
//           ],
//         );
//       }),
//     );
//   }

  Future<void> _deleteType(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      await http.delete(Uri.parse('$_warehouseBase/material-types/$id'));
      _fetchTypes();
    }
  }
// 1) Add/Edit Material Type – requires a non‑empty name and ≥1 spec
Future<void> _addOrEditType([Map<String, dynamic>? t]) async {
  final isEdit = t != null;
  final _formKey = GlobalKey<FormState>();
  final nameCtl = TextEditingController(text: t?['name'] ?? '');
  // start with one empty spec when creating
  final specsList = t == null
      ? <Map<String, String>>[{'name': ''}]
      : List<Map<String, String>>.from(
          (t['specs'] as List).map((e) => {'name': e['name'] as String}));

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setD) {
          return AlertDialog(
            title: Text(isEdit ? 'تعديل نوع مادة' : 'إضافة نوع مادة'),
            content: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1) Name field
                    TextFormField(
                      controller: nameCtl,
                      decoration: const InputDecoration(labelText: 'اسم النوع'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'اسم النوع مطلوب' : null,
                    ),
                    const SizedBox(height: 16),
                    // 2) Specs header + add button
                    Row(
                      children: [
                        const Text('المواصفات',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            setD(() => specsList.add({'name': ''}));
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 3) One TextFormField per spec
                    ...specsList.asMap().entries.map((entry) {
                      final idx = entry.key;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: specsList[idx]['name'],
                                decoration: const InputDecoration(
                                    labelText: 'اسم المواصفة'),
                                onChanged: (v) => specsList[idx]['name'] = v,
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'أدخل اسم مواصفة'
                                    : null,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                setD(() => specsList.removeAt(idx));
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
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
                  // validate form and at least one spec
                  if (!_formKey.currentState!.validate()) return;
                  if (specsList.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('أضف مواصفة واحدة على الأقل'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  // prepare payload
                  final payload = {
                    'name': nameCtl.text.trim(),
                    'specs': specsList
                        .map((s) => {'name': s['name']!.trim()})
                        .toList(),
                  };
                  final url = isEdit
                      ? '$_warehouseBase/material-types/${t!['id']}'
                      : '$_warehouseBase/material-types';
                  final res = isEdit
                      ? await http.put(
                          Uri.parse(url),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(payload),
                        )
                      : await http.post(
                          Uri.parse(url),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(payload),
                        );
                  if (res.statusCode == 200) {
                    Navigator.pop(context);
                    await _fetchTypes();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('فشل الحفظ (#${res.statusCode})'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      );
    },
  );
}


// 2) Import from Models – requires pick + positive qty
Future<void> _addFromModelDialog() async {
  final _formKey = GlobalKey<FormState>();
  List<Map<String, dynamic>> models = [];
  bool loading = true, firstLoad = true;
  String? err;
  int? modelId;
  double qty = 0;
  final qtyCtl = TextEditingController();

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(builder: (ctx, setD) {
      if (firstLoad) {
        firstLoad = false;
        http.get(Uri.parse(_modelsBase)).then((r) {
          if (r.statusCode == 200) {
            models = List<Map<String, dynamic>>.from(jsonDecode(r.body));
          } else {
            err = 'فشل التحميل (#${r.statusCode})';
          }
          loading = false;
          setD(() {});
        }).catchError((e) {
          err = 'خطأ $e';
          loading = false;
          setD(() {});
        });
      }

      return AlertDialog(
        title: const Text('إضافة من الموديلات'),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 360,
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : err != null
                    ? Text(err!, style: const TextStyle(color: Colors.red))
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<int>(
                            value: modelId,
                            decoration: const InputDecoration(labelText: 'اختر الموديل'),
                            items: models
                                .map((m) => DropdownMenuItem<int>(
                                      value: m['id'] as int,
                                      child: Text('${m['model_name']} (#${m['id']})'),
                                    ))
                                .toList(),
                            onChanged: (v) => setD(() => modelId = v),
                            validator: (v) => v == null ? 'اختر الموديل' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: qtyCtl,
                            decoration: const InputDecoration(labelText: 'الكمية'),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => qty = double.tryParse(v) ?? 0,
                            validator: (v) {
                              final n = double.tryParse(v ?? '') ?? 0;
                              return n <= 0 ? 'أدخل قيمة كمية صالحة' : null;
                            },
                          ),
                        ],
                      ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (!_formKey.currentState!.validate()) return;
              final body = jsonEncode({
                'warehouse_id': 1,
                'model_id': modelId,
                'quantity': qty,
              });
              final res = await http.post(
                Uri.parse('$_warehouseBase/product-inventory'),
                headers: {'Content-Type': 'application/json'},
                body: body,
              );
              if (res.statusCode == 200) {
                Navigator.pop(context);
                await _fetchReady();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('فشل الإضافة (#${res.statusCode})'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      );
    }),
  );
}

// 3) Add/Edit Raw Material – requires non‑empty code & each spec
Future<void> _addOrEditMaterial([Map<String, dynamic>? m]) async {
  final isEdit = m != null;
  final _formKey = GlobalKey<FormState>();
  final codeCtl = TextEditingController(text: m?['code'] ?? '');
  final vals = m == null
      ? _specs
          .map((s0) => {'spec_id': s0['id'], 'spec_name': s0['name'], 'value': ''})
          .toList()
      : List<Map<String, dynamic>>.from(m['specs'] as List);

  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(isEdit ? 'تعديل مادة' : 'إضافة مادة'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Code
              TextFormField(
                controller: codeCtl,
                decoration: const InputDecoration(labelText: 'الكود'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'الكود مطلوب' : null,
              ),
              const SizedBox(height: 12),
              // One field per spec
              ...vals.asMap().entries.map((entry) {
                final i = entry.key;
                final spec = vals[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    initialValue: spec['value'] as String?,
                    decoration: InputDecoration(labelText: spec['spec_name']),
                    onChanged: (t) => spec['value'] = t,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'الرجاء إدخال ${spec['spec_name']}' : null,
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final payload = {
              'type_id': _selectedTypeId,
              'code': codeCtl.text.trim(),
              'specs': vals
                  .map((e) => {'spec_id': e['spec_id'], 'value': e['value'].toString().trim()})
                  .toList(),
            };
            final url = isEdit
                ? '$_warehouseBase/materials/${m!['id']}'
                : '$_warehouseBase/materials';
            final res = isEdit
                ? await http.put(Uri.parse(url),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload))
                : await http.post(Uri.parse(url),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload));
            if (res.statusCode == 200) {
              Navigator.pop(context);
              await _fetchMaterialsForType(_selectedTypeId!);
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}

// 4) Add/Edit Ready‑Product – requires model ID + positive qty
Future<void> _addOrEditReady([Map<String, dynamic>? p]) async {
  final isEdit = p != null;
  final _formKey = GlobalKey<FormState>();
  final modelCtl = TextEditingController(text: p?['model_id']?.toString() ?? '');
  final qtyCtl = TextEditingController(text: p?['quantity']?.toString() ?? '');

  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(isEdit ? 'تعديل المنتج' : 'إضافة منتج'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Model ID
            TextFormField(
              controller: modelCtl,
              decoration: const InputDecoration(labelText: 'معرف الموديل'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final id = int.tryParse(v ?? '');
                return id == null ? 'أدخل معرف موديل صالح' : null;
              },
            ),
            const SizedBox(height: 8),
            // Quantity
            TextFormField(
              controller: qtyCtl,
              decoration: const InputDecoration(labelText: 'الكمية'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = double.tryParse(v ?? '') ?? 0;
                return n <= 0 ? 'أدخل كمية صالحة' : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final body = jsonEncode({
              'warehouse_id': 1,
              'model_id': int.parse(modelCtl.text),
              'quantity': double.parse(qtyCtl.text),
            });
            final url = isEdit
                ? '$_warehouseBase/product-inventory/${p!['id']}'
                : '$_warehouseBase/product-inventory';
            final res = isEdit
                ? await http.put(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: body)
                : await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: body);
            if (res.statusCode == 200) {
              Navigator.pop(context);
              await _fetchReady();
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}

  // ── RAW MATERIALS: material management ───────────────────────
//   Future<void> _addOrEditMaterial([Map<String, dynamic>? m]) async {
//     final isEdit = m != null;
//     final codeCtl = TextEditingController(text: m?['code'] ?? '');
//     final stockCtl = TextEditingController(text: s(m?['stock_quantity']));
//     final vals = m == null
//         ? _specs
//             .map((s0) => {'spec_id': s0['id'], 'spec_name': s0['name'], 'value': ''})
//             .toList()
//         : List<Map<String, dynamic>>.from(m['specs'] as List);

//     await showDialog(
//       context: context,
//       builder: (_) => StatefulBuilder(builder: (ctx, setD) {
//         return AlertDialog(
//           title: Text(isEdit ? 'تعديل مادة' : 'إضافة مادة'),
//           content: SingleChildScrollView(
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 TextField(controller: codeCtl, decoration: const InputDecoration(labelText: 'الكود')),
//                 TextField(
//                   controller: stockCtl,
//                   decoration: const InputDecoration(labelText: 'الكمية'),
//                   keyboardType: TextInputType.number,
//                 ),
//                 const SizedBox(height: 12),
//                 ...vals.map((v) => TextField(
//                       controller: TextEditingController(text: v['value']),
//                       decoration: InputDecoration(labelText: v['spec_name']),
//                       onChanged: (t) => v['value'] = t,
//                     )),
//               ],
//             ),
//           ),
//           actions: [
//             TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
//             ElevatedButton(
//               onPressed: () async {
//                 final body = jsonEncode({
//                   'type_id': _selectedTypeId,
//                   'code': codeCtl.text,
//                   'stock_quantity': double.tryParse(stockCtl.text) ?? 0,
//                   'specs': vals
//                       .map((e) => {'spec_id': e['spec_id'], 'value': e['value']})
//                       .toList(),
//                 });
//                 final url = isEdit
//                     ? '$_warehouseBase/materials/${m!['id']}'
//                     : '$_warehouseBase/materials';
//                 final r = isEdit
//                     ? await http.put(Uri.parse(url),
//                         headers: {'Content-Type': 'application/json'}, body: body)
//                     : await http.post(Uri.parse(url),
//                         headers: {'Content-Type': 'application/json'}, body: body);
//                 if (r.statusCode == 200) {
//                   Navigator.pop(ctx);
//                   _fetchMaterialsForType(_selectedTypeId!);
//                 }
//               },
//               child: const Text('حفظ'),
//             ),
//           ],
//         );
//       }),
//     );
//   }

  Future<void> _deleteMaterial(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      await http.delete(Uri.parse('$_warehouseBase/materials/$id'));
      _fetchMaterialsForType(_selectedTypeId!);
    }
  }
}

// White header text style shortcut
const _wh = TextStyle(color: Colors.white, fontWeight: FontWeight.bold);
