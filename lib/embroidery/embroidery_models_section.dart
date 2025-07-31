import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart';

class EmbroideryModelsSection extends StatefulWidget {
  const EmbroideryModelsSection({Key? key}) : super(key: key);

  @override
  State<EmbroideryModelsSection> createState() => _EmbroideryModelsSectionState();
}

class _EmbroideryModelsSectionState extends State<EmbroideryModelsSection> {
  static const double _sidebarWidth = 360;
String get baseUrl => '${globalServerUri.toString()}/embrodry/models/';

  // state
  List<Map<String, dynamic>> _models   = [];
  List<Map<String, dynamic>> _clients  = [];
  List<Map<String, dynamic>> _seasons  = [];
  List<Map<String, dynamic>> _filtered = [];

  int?    _filterClientId;
  int?    _filterSeasonId;
  String  _searchText   = '';

  bool _loading        = false;
  bool _loadingFilters = false;

  int? _selectedModelId;
  final _searchCtl     = TextEditingController();

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

  void _applyFilter() {
    setState(() {
      _filtered = _models.where((m) {
        final name = (m['model_name'] ?? '').toString().toLowerCase();
        return name.contains(_searchText);
      }).toList();
    });
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso) ?? DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  Future<void> _loadFiltersAndModels() async {
    setState(() => _loadingFilters = true);
    try {
      final cRes = await http.get(Uri.parse('${baseUrl}clients'));
      final sRes = await http.get(Uri.parse('${baseUrl}seasons'));
      if (cRes.statusCode == 200)
        _clients  = List<Map<String, dynamic>>.from(jsonDecode(cRes.body));
      if (sRes.statusCode == 200)
        _seasons  = List<Map<String, dynamic>>.from(jsonDecode(sRes.body));
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
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('لا')),
          ElevatedButton(
            onPressed: ()=>Navigator.pop(context,true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('نعم'),
          ),
        ],
      ),
    ) ?? false;
    if (!ok) return;
    try {
      final r = await http.delete(Uri.parse('$baseUrl$id'));
      if (r.statusCode != 200) throw Exception(r.body);
      _snack('تم الحذف');
      await _fetchModels();
    } catch (e) {
      _snack('فشل الحذف: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _models.firstWhere(
      (m) => m['id'] == _selectedModelId,
      orElse: () => <String, dynamic>{},
    );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          // ── Sidebar ─────────────────────────────
          Container(
            width: _sidebarWidth,
            color: Colors.grey[100],
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text('موديلات التطريز',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800])),
                  const SizedBox(height: 12),
                  // client filter
                  DropdownButtonFormField<int?>(
                    value: _filterClientId,
                    decoration: const InputDecoration(
                        labelText: 'العميل',
                        filled: true,
                        fillColor: Colors.white),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('الكل')),
                      const DropdownMenuItem(value: -1, child: Text('بدون عميل')),
                      ..._clients.map((c) => DropdownMenuItem<int?>(
                          value: c['id'] as int,
                          child: Text(c['full_name'] as String))),
                    ],
                    onChanged: (v) {
                      setState(() => _filterClientId = v == -1 ? null : v);
                      _fetchModels();
                    },
                  ),
                  const SizedBox(height: 8),
                  // season filter
                  DropdownButtonFormField<int?>(
                    value: _filterSeasonId,
                    decoration: const InputDecoration(
                        labelText: 'الموسم',
                        filled: true,
                        fillColor: Colors.white),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('الكل')),
                      ..._seasons.map((s) => DropdownMenuItem<int?>(
                          value: s['id'] as int, child: Text(s['name'] as String))),
                    ],
                    onChanged: (v) {
                      setState(() => _filterSeasonId = v);
                      _fetchModels();
                    },
                  ),
                  const SizedBox(height: 8),
                  // search
                  TextField(
                    controller: _searchCtl,
                    decoration: const InputDecoration(
                        labelText: 'بحث',
                        prefixIcon: Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _addOrEdit(),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('إضافة موديل',
                            style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[600]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchModels),
                  ]),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final m  = _filtered[i];
                          final sel = m['id'] == _selectedModelId;
                          final cli = (m['client_name'] as String?)?.isNotEmpty == true
                              ? m['client_name']
                              : 'بدون عميل';
                          return Card(
                            color: sel ? Colors.white : Colors.grey[50],
                            elevation: sel ? 3 : 1,
                            child: ListTile(
                              title: Text(m['model_name'] ?? '-',
                                  style: TextStyle(
                                      fontWeight:
                                          sel ? FontWeight.bold : FontWeight.normal)),
                              subtitle: Text(
                                'تاريخ: ${_fmtDate(m['model_date'] as String?)}'
                                '  · النوع: ${m['model_type']}'
                                '  · العميل: $cli',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              ),
                              onTap: () => setState(() => _selectedModelId = m['id'] as int),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _addOrEdit(m: m),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteModel(m['id'] as int),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),

          const VerticalDivider(width: 1),

          // ── Detail pane ─────────────────────────
          Expanded(
            child: selected.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.checkroom, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('اختر موديل من الشريط الجانبي',
                            style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // header with type Chip
                        Row(children: [
                          if ((selected['image_url'] ?? '').toString().isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                selected['image_url'],
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 100,
                                  height: 100,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.image_not_supported),
                                ),
                              ),
                            ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text(selected['model_name'] ?? '',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.indigo[800])),
                                  const SizedBox(width: 8),
                                  Chip(
                                    label: Text(selected['model_type']),
                                    backgroundColor: Colors.orange[100],
                                  ),
                                ]),
                                const SizedBox(height: 4),
                                Text(
                                  'تاريخ: ${_fmtDate(selected['model_date'])}',
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 24),

                        // Basic Info
                        Card(
                          color: Colors.indigo[50],
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
                                _infoRow(
                                    'العميل',
                                    (selected['client_name'] as String?)?.isNotEmpty ==
                                            true
                                        ? selected['client_name']
                                        : 'بدون عميل'),
                                _infoRow(
                                    'الموسم',
                                    (selected['season_name'] as String?)
                                            ?.isNotEmpty ==
                                        true
                                        ? selected['season_name']
                                        : 'بدون موسم'),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Specs
                        Card(
                          color: Colors.teal[50],
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
                                    _specCard(
                                        'سعر الغرزة',
                                        (selected['stitch_price'] as num)
                                            .toStringAsFixed(2)),
                                    _specCard('عدد الغرز',
                                        '${selected['stitch_number']}'),
                                    _specCard(
                                        'السعر الإجمالي',
                                        (selected['total_price'] as num)
                                            .toStringAsFixed(2)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Description
                        if ((selected['description'] ?? '').toString().isNotEmpty)
                          Card(
                            color: Colors.grey[50],
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
                                  Text(selected['description']),
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

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(
              width: 120,
              child:
                  Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ]),
      );

  Widget _specCard(String label, String value) => Container(
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
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.teal)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );

  // ─── Add/Edit Dialog ────────────────────────────────
  Future<void> _addOrEdit({Map<String, dynamic>? m}) async {
    final isEdit = m != null;
    final _formKey = GlobalKey<FormState>();

    // initial values
    int? clientId  = m?['client_id'] as int?;
    int? seasonId  = m?['season_id'] as int?;
    String modelType = (m?['model_type'] as String?) ?? 'حطة';
    DateTime modelDate = m != null
        ? DateTime.parse(m!['model_date'] as String)
        : DateTime.now();

    // controllers
    final nameCtl        = TextEditingController(text: m?['model_name'] ?? '');
    final stitchPriceCtl = TextEditingController(text: m?['stitch_price']?.toString() ?? '');
    final stitchNumCtl   = TextEditingController(text: m?['stitch_number']?.toString() ?? '');
    final descCtl        = TextEditingController(text: m?['description'] ?? '');

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> pickDate() async {
          final p = await showDatePicker(
            context: ctx,
            initialDate: modelDate,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (p != null) setD(() => modelDate = p);
        }

        return AlertDialog(
          title: Text(isEdit ? 'تعديل موديل' : 'إضافة موديل'),
          content: Form(
            key: _formKey,
            child: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // date picker
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('تاريخ: ${_fmtDate(modelDate.toIso8601String())}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: pickDate,
                    ),
                    const SizedBox(height: 8),

                    // client dropdown
                    DropdownButtonFormField<int?>(
                      decoration: const InputDecoration(labelText: 'العميل'),
                      value: clientId,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('بدون عميل')),
                        ..._clients.map((c) => DropdownMenuItem<int?>(
                          value: c['id'] as int,
                          child: Text(c['full_name'] as String),
                        )),
                      ],
                      onChanged: (v) => setD(() => clientId = v),
                    ),
                    const SizedBox(height: 8),

                    // season dropdown
                    DropdownButtonFormField<int?>(
                      decoration: const InputDecoration(labelText: 'الموسم'),
                      value: seasonId,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('بدون موسم')),
                        ..._seasons.map((s) => DropdownMenuItem<int?>(
                          value: s['id'] as int,
                          child: Text(s['name'] as String),
                        )),
                      ],
                      onChanged: (v) => setD(() => seasonId = v),
                    ),
                    const SizedBox(height: 8),

                    // model name
                    TextFormField(
                      controller: nameCtl,
                      decoration: const InputDecoration(labelText: 'اسم الموديل'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'اسم الموديل مطلوب' : null,
                    ),
                    const SizedBox(height: 8),

                    // stitch price
                    TextFormField(
                      controller: stitchPriceCtl,
                      decoration: const InputDecoration(labelText: 'سعر الغرزة'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final n = double.tryParse(v ?? '');
                        if (n == null || n <= 0) return 'أدخل سعراً صالحاً';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),

                    // stitch number
                    TextFormField(
                      controller: stitchNumCtl,
                      decoration: const InputDecoration(labelText: 'عدد الغرز'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final i = int.tryParse(v ?? '');
                        if (i == null || i <= 0) return 'أدخل عدداً صالحاً';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),

                    // model type
                    Row(children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('سحبة'),
                          value: 'سحبة',
                          groupValue: modelType,
                          onChanged: (v) => setD(() => modelType = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('حطة'),
                          value: 'حطة',
                          groupValue: modelType,
                          onChanged: (v) => setD(() => modelType = v!),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),

                    // description
                    TextFormField(
                      controller: descCtl,
                      decoration: const InputDecoration(labelText: 'الوصف'),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;

                final payload = {
                  'client_id':    clientId,
                  'season_id':    seasonId,
                  'model_date':   modelDate.toIso8601String(),
                  'model_name':   nameCtl.text.trim(),
                  'stitch_price': double.parse(stitchPriceCtl.text),
                  'stitch_number':int.parse(stitchNumCtl.text),
                  'description':  descCtl.text.trim(),
                  'model_type':   modelType,
                };

                try {
                  final uri = isEdit
                      ? Uri.parse('$baseUrl${m!['id']}')
                      : Uri.parse(baseUrl);
                  final res = isEdit
                      ? await http.put(uri,
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(payload))
                      : await http.post(uri,
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(payload));

                  final ok = isEdit ? res.statusCode == 200 : res.statusCode == 201;
                  if (!ok) throw Exception(res.body);

                  Navigator.pop(ctx);
                  _snack('تم الحفظ');
                  await _fetchModels();
                } catch (e) {
                  _snack('خطأ: $e', error: true);
                }
              },
              child: Text(isEdit ? 'تحديث' : 'إضافة'),
            ),
          ],
        );
      }),
    );
  }
}