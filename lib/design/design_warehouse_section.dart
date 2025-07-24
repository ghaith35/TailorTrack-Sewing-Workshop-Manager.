// lib/design/design_warehouse_section.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DesignWarehouseSection extends StatefulWidget {
  const DesignWarehouseSection({Key? key}) : super(key: key);

  @override
  State<DesignWarehouseSection> createState() => _DesignWarehouseSectionState();
}

class _DesignWarehouseSectionState extends State<DesignWarehouseSection> {
  // Tabs
  int _tab = 0;
  final _tabs = const ['المخزون الجاهز', 'المواد الخام'];

  // ========= CONFIG =========
  final String baseUrl = 'http://localhost:8888/design';
  String s(dynamic v) => v == null ? '—' : v.toString();
  double n(dynamic v) =>
      v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);
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

  // ========= READY PRODUCTS STATE =========
  List<dynamic> _ready = [];
  bool _loadingReady = false;
  String? _errReady;

  // Filters
  List<dynamic> _clients = [];
  List<dynamic> _seasons = [];
  int? _clientFilter;
  int? _seasonFilter;
  final TextEditingController _searchCtl = TextEditingController();

  // ========= RAW MATERIALS STATE =========
  List<dynamic> _types = [];
  int? _selectedTypeId;
  String? _selectedTypeName;
  List<dynamic> _specs = [];
  List<dynamic> _materials = [];
  bool _loadingTypes = false;
  bool _loadingMaterials = false;

  // Scroll controllers
  final _hReady = ScrollController();
  final _vReady = ScrollController();
  final _hRaw = ScrollController();
  final _vRaw = ScrollController();

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

  // ================== NETWORK (READY PRODUCTS) ==================
  Future<void> _fetchFilters() async {
    try {
      final c = await http.get(Uri.parse('$baseUrl/clients'));
      final s0 = await http.get(Uri.parse('$baseUrl/seasons'));
      if (c.statusCode == 200) _clients = jsonDecode(c.body) as List;
      if (s0.statusCode == 200) _seasons = jsonDecode(s0.body) as List;
      setState(() {});
    } catch (_) {}
  }

  Future<void> _fetchReady() async {
    setState(() {
      _loadingReady = true;
      _errReady = null;
    });
    try {
      final uri = Uri.parse('$baseUrl/warehouse/product-inventory');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        _ready = jsonDecode(res.body) as List;
      } else {
        _errReady = '(${res.statusCode}) فشل تحميل البيانات';
      }
    } catch (e) {
      _errReady = 'خطأ: $e';
    } finally {
      setState(() => _loadingReady = false);
    }
  }

  // ============== FILTERED READY LIST =================
  List<dynamic> get _filteredReady {
    final q = _searchCtl.text.trim().toLowerCase();
    return _ready.where((r) {
      if (n(r['quantity']) <= 0) return false;
      if (_clientFilter != null && r['client_id'] != _clientFilter) return false;
      if (_seasonFilter != null && r['season_id'] != _seasonFilter) return false;
      if (q.isNotEmpty) {
        final hay = [
          r['client_name'],
          r['season_name'],
          r['model_name'],
          r['marker_name'],
        ].map((e) => s(e).toLowerCase()).join(' ');
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _editReadyProduct(Map<String, dynamic> row) async {
    final qtyCtl = TextEditingController(text: s(row['quantity']));
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تعديل الكمية'),
        content: TextField(
          controller: qtyCtl,
          decoration: const InputDecoration(labelText: 'الكمية'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final body = jsonEncode({
                'warehouse_id': 1,
                'model_id': row['model_id'],
                'quantity': double.tryParse(qtyCtl.text) ?? 0,
              });
              final r = await http.put(
                Uri.parse('$baseUrl/warehouse/product-inventory/${row['id']}'),
                headers: {'Content-Type': 'application/json'},
                body: body,
              );
              Navigator.pop(context);
              if (r.statusCode == 200) await _fetchReady();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteReadyProduct(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      final r = await http.delete(Uri.parse('$baseUrl/warehouse/product-inventory/$id'));
      if (r.statusCode == 200) _fetchReady();
    }
  }

  void _showReadyDetails(Map<String, dynamic> p) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تفاصيل المنتج #${p['id']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('العميل', s(p['client_name'])),
              _infoRow('الموسم', s(p['season_name'])),
              _infoRow('الموديل', s(p['model_name'])),
              _infoRow('الماركر', s(p['marker_name'])),
              _infoRow('تاريخ', formatYMD(p['model_date'])),
              _infoRow('الطول', money(p['length'])),
              _infoRow('العرض', money(p['width'])),
              _infoRow('نسبة الإستغلال', '${money(p['util_percent'])}%'),
              _infoRow('Placed', s(p['placed'])),
              _infoRow('المقاسات/الكميات', s(p['sizes_text'])),
              _infoRow('السعر', '${money(p['price'])} دج'),
              _infoRow('الوصف', s(p['description'])),
              _infoRow('الكمية بالمخزن', money(p['quantity'])),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
      ),
    );
  }

  // ================== READY UI ==================
  Widget _readyTab() {
    if (_loadingReady) return const Center(child: CircularProgressIndicator());
    if (_errReady != null) return Center(child: Text(_errReady!));

    final rows = _filteredReady;

    return Column(
      children: [
        // Filters row
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                value: _clientFilter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'العميل'),
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('الكل')),
                  ..._clients.map((c) => DropdownMenuItem<int>(
                        value: c['id'] as int,
                        child: Text(s(c['full_name'])),
                      )),
                ],
                onChanged: (v) => setState(() => _clientFilter = v),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                value: _seasonFilter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الموسم'),
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('الكل')),
                  ..._seasons.map((s0) => DropdownMenuItem<int>(
                        value: s0['id'] as int,
                        child: Text(s(s0['name'])),
                      )),
                ],
                onChanged: (v) => setState(() => _seasonFilter = v),
              ),
            ),
            SizedBox(
              width: 240,
              child: TextField(
                controller: _searchCtl,
                decoration: const InputDecoration(
                  labelText: 'بحث',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _addFromModelDialog,
              icon: const Icon(Icons.add),
              label: const Text('إضافة من الموديلات'),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _fetchReady,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // TABLE with both scrollbars
        Expanded(
          child: Scrollbar(
            controller: _hReady,
            thumbVisibility: true,
            notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _hReady,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 600),
                child: Scrollbar(
                  controller: _vReady,
                  thumbVisibility: true,
                  notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
                  child: SingleChildScrollView(
                    controller: _vReady,
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                      headingTextStyle: _wh,
                      columns: const [
                        DataColumn(label: Text('العميل', style: _wh)),
                        DataColumn(label: Text('الموسم', style: _wh)),
                        DataColumn(label: Text('التاريخ', style: _wh)),
                        DataColumn(label: Text('الموديل', style: _wh)),
                        DataColumn(label: Text('الكمية', style: _wh)),
                        DataColumn(label: Text('خيارات', style: _wh)),
                      ],
                      rows: rows.map((p) {
                        return DataRow(cells: [
                          DataCell(Text(s(p['client_name']))),
                          DataCell(Text(s(p['season_name']))),
                          DataCell(Text(formatYMD(p['model_date']))),
                          DataCell(Text(s(p['model_name']))),
                          DataCell(Text(money(p['quantity']))),
                          DataCell(Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.visibility, color: Colors.blue),
                                onPressed: () => _showReadyDetails(p),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.teal),
                                onPressed: () => _editReadyProduct(p),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteReadyProduct(p['id'] as int),
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

  // ================== RAW MATERIALS NETWORK ==================
  Future<void> _addFromModelDialog() async {
    int? modelId;
    double qty = 0;
    List<dynamic> models = [];
    bool loading = true;
    String? err;
    final qtyCtl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> loadModels() async {
          setD(() {
            loading = true;
            err = null;
          });
          try {
            final r = await http.get(Uri.parse('$baseUrl/models'));
            if (r.statusCode == 200) {
              models = jsonDecode(r.body) as List;
            } else {
              err = '(${r.statusCode})';
            }
          } catch (e) {
            err = 'خطأ $e';
          } finally {
            setD(() => loading = false);
          }
        }

        if (loading) loadModels();

        bool canSave() => modelId != null && qty > 0;

        return AlertDialog(
          title: const Text('إضافة من الموديلات'),
          content: SizedBox(
            width: 420,
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : err != null
                    ? Text(err!)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<int>(
                            value: modelId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'اختر الموديل'),
                            items: models
                                .map((m) => DropdownMenuItem<int>(
                                      value: m['id'] as int,
                                      child: Text(
                                        '${s(m["model_name"])} (#${m["id"]})',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              modelId = v;
                              setD(() {});
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: qtyCtl,
                            decoration: const InputDecoration(labelText: 'الكمية'),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              qty = double.tryParse(v) ?? 0;
                              setD(() {});
                            },
                          ),
                        ],
                      ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: !canSave()
                  ? null
                  : () async {
                      final body = jsonEncode({
                        'warehouse_id': 1,
                        'model_id': modelId,
                        'quantity': qty,
                      });
                      final r = await http.post(
                        Uri.parse('$baseUrl/warehouse/product-inventory'),
                        headers: {'Content-Type': 'application/json'},
                        body: body,
                      );
                      if (r.statusCode == 200) {
                        Navigator.pop(ctx);
                        await _fetchReady();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('فشل الإضافة (${r.statusCode})')),
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

  Future<void> _fetchTypes() async {
    setState(() => _loadingTypes = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/warehouse/material-types'));
      if (res.statusCode == 200) {
        _types = jsonDecode(res.body) as List;
        if (_types.isNotEmpty && _selectedTypeId == null) {
          _selectedTypeId = _types.first['id'];
          _selectedTypeName = _types.first['name'];
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
      final res = await http.get(Uri.parse('$baseUrl/warehouse/materials?type_id=$tid'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _specs = data['specs'];
        _materials = data['materials'];
      }
    } finally {
      setState(() => _loadingMaterials = false);
    }
  }

  Future<void> _addOrEditType([Map<String, dynamic>? t]) async {
    final isEdit = t != null;
    final nameCtl = TextEditingController(text: t?['name'] ?? '');
    final specsList = t == null
        ? <Map<String, dynamic>>[]
        : (t['specs'] as List)
            .map((e) => {'id': e['id'], 'name': e['name']})
            .toList();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: Text(isEdit ? 'تعديل نوع' : 'إضافة نوع'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: 'اسم النوع'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('المواصفات', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => setD(() => specsList.add({'name': ''})),
                    )
                  ],
                ),
                ...specsList.asMap().entries.map((e) {
                  final i = e.key;
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: specsList[i]['name']),
                          onChanged: (v) => specsList[i]['name'] = v,
                          decoration: const InputDecoration(labelText: 'اسم المواصفة'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => setD(() => specsList.removeAt(i)),
                      ),
                    ],
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final body = jsonEncode({
                  'name': nameCtl.text.trim(),
                  'specs': specsList.where((s) => (s['name'] as String).trim().isNotEmpty).toList(),
                });
                if (isEdit) {
                  await http.put(
                    Uri.parse('$baseUrl/warehouse/material-types/${t!['id']}'),
                    headers: {'Content-Type': 'application/json'},
                    body: body,
                  );
                } else {
                  await http.post(
                    Uri.parse('$baseUrl/warehouse/material-types'),
                    headers: {'Content-Type': 'application/json'},
                    body: body,
                  );
                }
                Navigator.pop(ctx);
                await _fetchTypes();
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _deleteType(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      await http.delete(Uri.parse('$baseUrl/warehouse/material-types/$id'));
      await _fetchTypes();
      if (_selectedTypeId == id) {
        setState(() {
          _selectedTypeId = null;
          _selectedTypeName = null;
          _specs = [];
          _materials = [];
        });
      }
    }
  }

  Future<void> _addOrEditMaterial([Map<String, dynamic>? m]) async {
    final isEdit = m != null;
    final codeCtl = TextEditingController(text: m?['code'] ?? '');
    final stockCtl = TextEditingController(text: s(m?['stock_quantity']));
    final vals = m == null
        ? _specs.map((s0) => {'spec_id': s0['id'], 'spec_name': s0['name'], 'value': ''}).toList()
        : List<Map<String, dynamic>>.from(m['specs'] as List);

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: Text(isEdit ? 'تعديل مادة' : 'إضافة مادة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: codeCtl, decoration: const InputDecoration(labelText: 'الكود')),
                TextField(
                  controller: stockCtl,
                  decoration: const InputDecoration(labelText: 'الكمية'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                ...vals.map((v) => TextField(
                      controller: TextEditingController(text: v['value']),
                      decoration: InputDecoration(labelText: v['spec_name']),
                      onChanged: (t) => v['value'] = t,
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final body = jsonEncode({
                  'type_id': _selectedTypeId,
                  'code': codeCtl.text,
                  'stock_quantity': double.tryParse(stockCtl.text) ?? 0,
                  'specs': vals.map((e) => {'spec_id': e['spec_id'], 'value': e['value']}).toList(),
                });
                final url = isEdit
                    ? '$baseUrl/warehouse/materials/${m!['id']}'
                    : '$baseUrl/warehouse/materials';
                final r = isEdit
                    ? await http.put(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: body)
                    : await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: body);
                if (r.statusCode == 200) {
                  Navigator.pop(ctx);
                  await _fetchMaterialsForType(_selectedTypeId!);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ ${r.statusCode}')));
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _deleteMaterial(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      await http.delete(Uri.parse('$baseUrl/warehouse/materials/$id'));
      await _fetchMaterialsForType(_selectedTypeId!);
    }
  }

  // ================== RAW MATERIALS UI ==================
  Widget _rawTab() {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        // Sidebar (like purchases)
        Container(
          width: 400,
          decoration: BoxDecoration(color: Colors.grey[100]),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'أنواع المواد الخام',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('نوع جديد', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[600],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _addOrEditType(),
                      ),
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
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            elevation: sel ? 4 : 1,
                            color: sel ? Colors.grey[100] : Colors.white,
                            child: ListTile(
                              selected: sel,
                              title: Text(
                                s(t['name']),
                                style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal),
                              ),
                              onTap: () async {
                                setState(() {
                                  _selectedTypeId = t['id'];
                                  _selectedTypeName = t['name'];
                                });
                                await _fetchMaterialsForType(_selectedTypeId!);
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: const Icon(Icons.edit, color: Colors.teal), onPressed: () => _addOrEditType(t)),
                                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteType(t['id'] as int)),
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

        // Main materials table
        Expanded(
          child: _loadingMaterials
              ? const Center(child: CircularProgressIndicator())
              : (_selectedTypeId == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.category, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text('اختر نوع مادة من القائمة الجانبية', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.add),
                                label: Text('إضافة مادة (${s(_selectedTypeName)})'),
                                onPressed: _selectedTypeId != null ? () => _addOrEditMaterial() : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _specs.isEmpty
                              ? const Center(child: Text('لا توجد مواصفات لهذا النوع'))
                              : Scrollbar(
                                  controller: _hRaw,
                                  thumbVisibility: true,
                                  notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                                  child: SingleChildScrollView(
                                    controller: _hRaw,
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(minWidth: 900),
                                      child: Scrollbar(
                                        controller: _vRaw,
                                        thumbVisibility: true,
                                        notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                                        child: SingleChildScrollView(
                                          controller: _vRaw,
                                          child: DataTable(
                                            headingRowColor: MaterialStateProperty.all(
                                                Theme.of(context).colorScheme.primary),
                                            headingTextStyle: _wh,
                                            columns: [
                                              const DataColumn(label: Text('الكود', style: _wh)),
                                              const DataColumn(label: Text('الكمية', style: _wh)),
                                              const DataColumn(label: Text('آخر سعر', style: _wh)),
                                              ..._specs.map((s0) =>
                                                  DataColumn(label: Text(s(s0['name']), style: _wh))),
                                              const DataColumn(label: Text('خيارات', style: _wh)),
                                            ],
                                            rows: _materials.map((m) {
                                              final vals = m['specs'] as List;
                                              return DataRow(cells: [
                                                DataCell(Text(s(m['code']))),
                                                DataCell(Text(money(m['stock_quantity']))),
                                                DataCell(Text(money(m['last_unit_price']))),
                                                ...vals.map((v) => DataCell(Text(s(v['value'])))),
                                                DataCell(Row(
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.edit, color: Colors.teal),
                                                      onPressed: () => _addOrEditMaterial(m),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.delete, color: Colors.red),
                                                      onPressed: () => _deleteMaterial(m['id'] as int),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _tabs.length,
              (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ChoiceChip(
                  label: Text(_tabs[i]),
                  selected: _tab == i,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  labelStyle: TextStyle(
                    color: _tab == i ? Colors.white : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (_) => setState(() => _tab = i),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _tab == 0 ? _readyTab() : _rawTab()),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

// White header text style shortcut
const _wh = TextStyle(color: Colors.white, fontWeight: FontWeight.bold);
