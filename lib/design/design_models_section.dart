// lib/design/design_models_section.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DesignModelsSection extends StatefulWidget {
  const DesignModelsSection({Key? key}) : super(key: key);

  @override
  State<DesignModelsSection> createState() => _DesignModelsSectionState();
}

class _DesignModelsSectionState extends State<DesignModelsSection> {
  // ================= CONFIG =================
  static const double _sidebarWidth = 360;
  final String baseUrl = 'http://127.0.0.1:8888/design/models/';

  // ================= STATE ==================
  List<Map<String, dynamic>> _models = [];
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _seasons = [];
  List<Map<String, dynamic>> _filtered = [];

  int? _filterClientId;
  int? _filterSeasonId;
  String _searchText = '';

  bool _loading = false;
  bool _loadingFilters = false;

  int? _selectedModelId;

  final TextEditingController _searchCtl = TextEditingController();

  // ================= INIT ===================
  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(() {
      setState(() => _searchText = _searchCtl.text.trim().toLowerCase());
      _applyFilter();
    });
    _loadFiltersAndModels();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  // ================ HELPERS ================
  void _applyFilter() {
    setState(() {
      _filtered = _models.where((m) {
        final name = (m['model_name'] ?? '').toString().toLowerCase();
        final marker = (m['marker_name'] ?? '').toString().toLowerCase();
        return name.contains(_searchText) || marker.contains(_searchText);
      }).toList();
    });
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso.split('T').first;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  // ================ NETWORK ================
  Future<void> _loadFiltersAndModels() async {
    setState(() => _loadingFilters = true);
    try {
      final cRes = await http.get(Uri.parse('${baseUrl}clients'));
      final sRes = await http.get(Uri.parse('${baseUrl}seasons'));
      if (cRes.statusCode == 200 && sRes.statusCode == 200) {
        _clients = List<Map<String, dynamic>>.from(jsonDecode(cRes.body));
        _seasons = List<Map<String, dynamic>>.from(jsonDecode(sRes.body));
      }
      await _fetchModels();
    } catch (e) {
      _snack('فشل في تحميل القوائم: $e', error: true);
    } finally {
      setState(() => _loadingFilters = false);
    }
  }

  Future<void> _fetchModels() async {
    setState(() => _loading = true);
    try {
      final qp = <String, String>{};
      if (_filterClientId != null) qp['client_id'] = '$_filterClientId';
      if (_filterSeasonId != null) qp['season_id'] = '$_filterSeasonId';
      final uri = Uri.parse(baseUrl).replace(queryParameters: qp.isEmpty ? null : qp);
      final res = await http.get(uri);
      if (res.statusCode != 200) throw Exception(res.body);
      _models = List<Map<String, dynamic>>.from(jsonDecode(res.body));
      _selectedModelId = _models.isNotEmpty ? _models.first['id'] as int : null;
      _applyFilter();
    } catch (e) {
      _snack('فشل في جلب الموديلات: $e', error: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteModel(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف موديل'),
        content: const Text('هل أنت متأكد من الحذف؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await http.delete(Uri.parse('$baseUrl$id'));
      if (r.statusCode != 200) throw Exception(r.body);
      _snack('تم الحذف');
      await _fetchModels();
    } catch (e) {
      _snack('فشل الحذف: $e', error: true);
    }
  }

  // ============== UI BUILD ================
  @override
  Widget build(BuildContext context) {
    final selectedModel = _models.firstWhere(
      (m) => m['id'] == _selectedModelId,
      orElse: () => {},
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          // Sidebar
          Container(
            width: _sidebarWidth,
            color: Colors.grey[100],
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text('موديلات التصميم',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800])),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        value: _filterClientId,
                        decoration: const InputDecoration(
                          labelText: 'العميل',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('الكل')),
                          ..._clients.map((c) => DropdownMenuItem(
                              value: c['id'] as int,
                              child: Text(c['full_name'])))
                        ],
                        onChanged: (v) {
                          setState(() => _filterClientId = v);
                          _fetchModels();
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int?>(
                        value: _filterSeasonId,
                        decoration: const InputDecoration(
                          labelText: 'الموسم',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('الكل')),
                          ..._seasons.map((s) => DropdownMenuItem(
                              value: s['id'] as int,
                              child: Text(s['name'])))
                        ],
                        onChanged: (v) {
                          setState(() => _filterSeasonId = v);
                          _fetchModels();
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _searchCtl,
                        decoration: const InputDecoration(
                          labelText: 'بحث',
                          prefixIcon: Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _addOrEdit(),
                              icon: const Icon(Icons.add, color: Colors.white),
                              label: const Text('إضافة موديل',
                                  style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal[600]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _fetchModels,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final m = _filtered[i];
                            final sel = m['id'] == _selectedModelId;
                            return Card(
                              color: sel ? Colors.white : Colors.grey[50],
                              elevation: sel ? 3 : 1,
                              child: ListTile(
                                title: Text(m['model_name'] ?? '-',
                                    style: TextStyle(
                                        fontWeight: sel
                                            ? FontWeight.bold
                                            : FontWeight.normal)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ماركر: ${m['marker_name'] ?? '-'}',
                                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'تاريخ: ${_fmtDate(m['model_date'])}',
                                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setState(
                                      () => _selectedModelId = m['id'] as int);
                                },
                                trailing: IconButton(
                                  icon:
                                      const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () =>
                                      _deleteModel(m['id'] as int),
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

          // Main detail
          Expanded(
            child: selectedModel.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.checkroom,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('اختر موديل من الشريط الجانبي',
                            style: TextStyle(
                                fontSize: 18, color: Colors.grey[600])),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            if ((selectedModel['image_url'] ?? '')
                                .toString()
                                .isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  selectedModel['image_url'],
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 100,
                                    height: 100,
                                    color: Colors.grey[300],
                                    child:
                                        const Icon(Icons.image_not_supported),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedModel['model_name'] ?? '',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.indigo[800]),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ماركر: ${selectedModel['marker_name'] ?? '-'}',
                                    style: TextStyle(
                                        color: Colors.grey[700], fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Basic Info Card
                        Card(
                          color: Colors.indigo[50],
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('المعلومات الأساسية',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo[800])),
                                const SizedBox(height: 12),
                                _infoRow('العميل',
                                    selectedModel['client_name'] ?? '-'),
                                _infoRow('الموسم',
                                    selectedModel['season_name'] ?? '-'),
                                _infoRow('الماركر',
                                    selectedModel['marker_name'] ?? '-'),
                                _infoRow('تاريخ الموديل',
                                    _fmtDate(selectedModel['model_date'])),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Specs Card
                        Card(
                          color: Colors.teal[50],
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('المواصفات',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal[800])),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 8,
                                  children: [
                                    _specCard('الطول',
                                        '${selectedModel['length'] ?? 0}'),
                                    _specCard('العرض',
                                        '${selectedModel['width'] ?? 0}'),
                                    _specCard(
                                        'نسبة الإستغلال',
                                        '${(selectedModel['util_percent'] ?? 0).toStringAsFixed(2)}%'),
                                    _specCard('Placed',
                                        selectedModel['placed'] ?? '-'),
                                    _specCard('المقاسات/الكميات',
                                        selectedModel['sizes_text'] ?? '-'),
                                    // _specCard('السعر',
                                    //     '${(selectedModel['price'] as num?)?.toStringAsFixed(2) ?? '0.00'} دج'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Description Card
                        if ((selectedModel['description'] ?? '').toString().isNotEmpty)
                          Card(
                            color: Colors.grey[50],
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('الوصف',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[800])),
                                  const SizedBox(height: 8),
                                  Text(selectedModel['description']),
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
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 120,
              child: Text('$label:',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _specCard(String label, String value) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.teal[100]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.teal)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

Future<void> _addOrEdit({Map<String, dynamic>? m}) async {
  final isEdit = m != null;

  int? clientId  = m?['client_id'];
  int? seasonId  = m?['season_id'];
  DateTime? modelDate = m != null
      ? DateTime.tryParse(m['model_date'] ?? '')
      : DateTime.now();

  // Controllers for text fields
  final modelNameCtl = TextEditingController(text: m?['model_name'] ?? '');
  final markerCtl    = TextEditingController(text: m?['marker_name'] ?? '');
  final lengthCtl    = TextEditingController(text: (m?['length'] ?? '').toString());
  final widthCtl     = TextEditingController(text: (m?['width'] ?? '').toString());
  final utilCtl      = TextEditingController(text: (m?['util_percent'] ?? '').toString());
  final placedCtl    = TextEditingController(text: m?['placed'] ?? '');
  final descCtl      = TextEditingController(text: m?['description'] ?? '');

  final _formKey = GlobalKey<FormState>();

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setD) {
        Future<void> pickDate() async {
          final p = await showDatePicker(
            context: ctx,
            initialDate: modelDate ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            locale: const Locale('ar'),
          );
          if (p != null) setD(() => modelDate = p);
        }

        return AlertDialog(
          title: Text(isEdit ? 'تعديل موديل' : 'إضافة موديل'),
          content: SizedBox(
            width: 520,
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Client
                  DropdownButtonFormField<int>(
                    value: clientId,
                    decoration: const InputDecoration(labelText: 'العميل'),
                    items: _clients.map((c) {
                      return DropdownMenuItem(
                        value: c['id'] as int,
                        child: Text(c['full_name']),
                      );
                    }).toList(),
                    onChanged: (v) => setD(() => clientId = v),
                    validator: (_) =>
                        clientId == null ? 'الرجاء اختيار العميل' : null,
                  ),
                  const SizedBox(height: 8),

                  // Season (optional)
                  DropdownButtonFormField<int>(
                    value: seasonId,
                    decoration: const InputDecoration(labelText: 'الموسم'),
                    items: _seasons.map((s) {
                      return DropdownMenuItem(
                        value: s['id'] as int,
                        child: Text(s['name']),
                      );
                    }).toList(),
                    onChanged: (v) => setD(() => seasonId = v),
                  ),
                  const SizedBox(height: 8),

                  // Date picker
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(modelDate == null
                        ? 'اختر تاريخ الموديل'
                        : 'تاريخ: ${_fmtDate(modelDate!.toIso8601String())}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: pickDate,
                  ),
                  if (modelDate == null)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'الرجاء اختيار التاريخ',
                          style: TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Model name
                  TextFormField(
                    controller: modelNameCtl,
                    decoration: const InputDecoration(labelText: 'اسم الموديل'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'اسم الموديل مطلوب'
                        : null,
                  ),
                  const SizedBox(height: 8),

                  // Marker name
                  TextFormField(
                    controller: markerCtl,
                    decoration: const InputDecoration(labelText: 'اسم الماركر'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'اسم الماركر مطلوب'
                        : null,
                  ),
                  const SizedBox(height: 8),

                  // الطول (no validator)
                  TextFormField(
                    controller: lengthCtl,
                    decoration: const InputDecoration(labelText: 'الطول'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),

                  // العرض (no validator)
                  TextFormField(
                    controller: widthCtl,
                    decoration: const InputDecoration(labelText: 'العرض'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),

                  // نسبة الإستغلال % (no validator)
                  TextFormField(
                    controller: utilCtl,
                    decoration:
                        const InputDecoration(labelText: 'نسبة الإستغلال %'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),

                  // Placed/Unplaced (no validator)
                  TextFormField(
                    controller: placedCtl,
                    decoration:
                        const InputDecoration(labelText: 'Placed / Unplaced'),
                  ),
                  const SizedBox(height: 8),

                  // Description
                  TextFormField(
                    controller: descCtl,
                    decoration: const InputDecoration(labelText: 'الوصف'),
                    maxLines: 2,
                  ),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                // require form + date
                if (_formKey.currentState!.validate() == false ||
                    modelDate == null) {
                  return;
                }

                final payload = {
                  'client_id'   : clientId,
                  'season_id'   : seasonId,
                  'model_date'  : modelDate!.toIso8601String(),
                  'model_name'  : modelNameCtl.text.trim(),
                  'marker_name' : markerCtl.text.trim(),
                  'length'      : double.tryParse(lengthCtl.text) ?? 0,
                  'width'       : double.tryParse(widthCtl.text) ?? 0,
                  'util_percent': double.tryParse(utilCtl.text) ?? 0,
                  'placed'      : placedCtl.text.trim(),
                  'description' : descCtl.text.trim(),
                };

                try {
                  late http.Response res;
                  if (isEdit) {
                    res = await http.put(
                      Uri.parse('$baseUrl${m!['id']}'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(payload),
                    );
                    if (res.statusCode != 200) throw Exception(res.body);
                  } else {
                    res = await http.post(
                      Uri.parse(baseUrl),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(payload),
                    );
                    if (res.statusCode != 201) throw Exception(res.body);
                  }
                  Navigator.pop(ctx);
                  _snack('تم الحفظ');
                  await _fetchModels();
                } catch (e) {
                  _snack('خطأ في الحفظ: $e', error: true);
                }
              },
              child: Text(isEdit ? 'تحديث' : 'حفظ'),
            ),
          ],
        );
      },
    ),
  );
}
}
