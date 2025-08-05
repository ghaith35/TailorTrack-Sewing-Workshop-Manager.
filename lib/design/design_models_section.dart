import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:http_parser/http_parser.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
class DesignModelsSection extends StatefulWidget {
  const DesignModelsSection({Key? key}) : super(key: key);

  @override
  State<DesignModelsSection> createState() => _DesignModelsSectionState();
}

class _DesignModelsSectionState extends State<DesignModelsSection> {
  // ================= CONFIG =================
  static const double _sidebarWidth = 360;
  String get baseUrl => '${globalServerUri.toString()}/design/models/';

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
  File? _pickedImageFile;

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

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      withData: false,
    );
    if (result?.files.single.path != null) {
      setState(() => _pickedImageFile = File(result!.files.single.path!));
    }
  }

  Future<Map<String, dynamic>> _uploadModelWithImage(int? existingId, Map<String, dynamic> data) async {
    final uri = existingId == null
        ? Uri.parse(baseUrl)
        : Uri.parse('$baseUrl$existingId');
    final req = http.MultipartRequest(existingId == null ? 'POST' : 'PUT', uri);

    // Add authentication header
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      req.headers['Authorization'] = 'Bearer $token';
    }

    data.forEach((k, v) => req.fields[k] = v.toString());

    if (_pickedImageFile != null) {
      final ext = p.extension(_pickedImageFile!.path).replaceFirst('.', '');
      req.files.add(await http.MultipartFile.fromPath(
        'image',
        _pickedImageFile!.path,
        contentType: MediaType('image', ext),
      ));
    } else if (existingId != null && data['image_url'] == null) {
      // Explicitly clear image if none is picked and image_url is null
      req.fields['image'] = '';
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == (existingId == null ? 201 : 200)) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['id'] == null) {
        throw Exception('Server response did not include a valid model ID');
      }
      _pickedImageFile = null;
      return body;
    } else {
      throw Exception('Upload failed: ${resp.statusCode} ${resp.body}');
    }
  }

  // ================ NETWORK ================
  Future<void> _loadFiltersAndModels() async {
    setState(() => _loadingFilters = true);
    try {
      final headers = <String, String>{};
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final cRes = await http.get(Uri.parse('${baseUrl}clients'), headers: headers);
      final sRes = await http.get(Uri.parse('${baseUrl}seasons'), headers: headers);
      if (cRes.statusCode == 200 && sRes.statusCode == 200) {
        _clients = List<Map<String, dynamic>>.from(jsonDecode(cRes.body));
        _seasons = List<Map<String, dynamic>>.from(jsonDecode(sRes.body));
      } else {
        throw Exception('Failed to load clients or seasons: ${cRes.statusCode}, ${sRes.statusCode}');
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
      final headers = <String, String>{};
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final res = await http.get(uri, headers: headers);
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
      final headers = <String, String>{};
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final r = await http.delete(Uri.parse('$baseUrl$id'), headers: headers);
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
                                leading: (m['image_url'] ?? '').toString().isNotEmpty
                                    ? Image.network(
                                        '${globalServerUri.toString()}${m['image_url']}',
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.broken_image),
                                      )
                                    : Icon(Icons.image, size: 40, color: Colors.grey),
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
                              GestureDetector(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => Dialog(
                                      backgroundColor: Colors.transparent,
                                      insetPadding: const EdgeInsets.all(16),
                                      child: InteractiveViewer(
                                        child: Image.network(
                                          '${globalServerUri.toString()}${selectedModel['image_url']}',
                                          fit: BoxFit.contain,
                                          loadingBuilder: (ctx, child, progress) {
                                            if (progress == null) return child;
                                            return const Center(
                                                child: CircularProgressIndicator());
                                          },
                                          errorBuilder: (ctx, err, st) =>
                                              const Center(
                                                  child: Icon(Icons.broken_image, size: 64)),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    '${globalServerUri.toString()}${selectedModel['image_url']}',
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

    // Initial values
    int? clientId = m?['client_id'];
    int? seasonId = m?['season_id'];
    DateTime? modelDate = m != null
        ? DateTime.tryParse(m['model_date'] as String)
        : DateTime.now();
    String? imageUrl = m?['image_url'];

    // Controllers for text fields
    final modelNameCtl = TextEditingController(text: m?['model_name'] ?? '');
    final markerCtl = TextEditingController(text: m?['marker_name'] ?? '');
    final lengthCtl = TextEditingController(text: (m?['length'] ?? '').toString());
    final widthCtl = TextEditingController(text: (m?['width'] ?? '').toString());
    final utilCtl = TextEditingController(text: (m?['util_percent'] ?? '').toString());
    final placedCtl = TextEditingController(text: m?['placed'] ?? '');
    final descCtl = TextEditingController(text: m?['description'] ?? '');

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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Image section
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('صورة الموديل',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.image),
                                label: const Text('اختر صورة'),
                                onPressed: () async {
                                  await _pickImage();
                                  setD(() {});
                                },
                              ),
                              if (_pickedImageFile != null ||
                                  (imageUrl?.isNotEmpty == true)) ...[
                                const SizedBox(width: 8),
                                Stack(
                                  alignment: Alignment.topRight,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: _pickedImageFile != null
                                          ? Image.file(
                                              _pickedImageFile!,
                                              width: 60,
                                              height: 60,
                                              fit: BoxFit.cover,
                                            )
                                          : Image.network(
                                              '${globalServerUri.toString()}$imageUrl',
                                              width: 60,
                                              height: 60,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                width: 60,
                                                height: 60,
                                                color: Colors.grey[300],
                                                child: Icon(Icons.image_not_supported,
                                                    color: Colors.grey[600]),
                                              ),
                                            ),
                                    ),
                                    Positioned(
                                      right: -6,
                                      top: -6,
                                      child: InkWell(
                                        onTap: () {
                                          setD(() {
                                            _pickedImageFile = null;
                                            imageUrl = null;
                                          });
                                        },
                                        child: CircleAvatar(
                                          radius: 10,
                                          backgroundColor: Colors.red,
                                          child: Icon(Icons.close,
                                              size: 12, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),

                      // Client selector
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
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'الرجاء اختيار التاريخ',
                            style: TextStyle(color: Colors.red[700], fontSize: 12),
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

                      // Length (no validator)
                      TextFormField(
                        controller: lengthCtl,
                        decoration: const InputDecoration(labelText: 'الطول'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),

                      // Width (no validator)
                      TextFormField(
                        controller: widthCtl,
                        decoration: const InputDecoration(labelText: 'العرض'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),

                      // Util % (no validator)
                      TextFormField(
                        controller: utilCtl,
                        decoration:
                            const InputDecoration(labelText: 'نسبة الإستغلال %'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),

                      // Placed / Unplaced
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
                    ],
                  ),
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
                  // Validate form + date
                  if (!_formKey.currentState!.validate() || modelDate == null) {
                    return;
                  }

                  final payload = {
                    'client_id': clientId,
                    'season_id': seasonId,
                    'model_date': modelDate!.toIso8601String(),
                    'model_name': modelNameCtl.text.trim(),
                    'marker_name': markerCtl.text.trim(),
                    'length': double.tryParse(lengthCtl.text) ?? 0,
                    'width': double.tryParse(widthCtl.text) ?? 0,
                    'util_percent': double.tryParse(utilCtl.text) ?? 0,
                    'placed': placedCtl.text.trim(),
                    'sizes_text': '',
                    'price': 0.0,
                    'description': descCtl.text.trim(),
                    'image_url': imageUrl, // Include current image_url for updates
                  };

                  try {
                    final result = await _uploadModelWithImage(
                      isEdit ? m!['id'] as int : null,
                      payload,
                    );

                    Navigator.pop(ctx);
                    _snack(isEdit ? 'تم التحديث' : 'تم الإضافة');
                    await _fetchModels();
                  } catch (e) {
                    if (e.toString().contains('duplicate_name')) {
                      _snack('اسم الموديل موجود بالفعل', error: true);
                    } else if (e.toString().contains('Server response did not include a valid model ID')) {
                      _snack('خطأ في الخادم: فشل في استرجاع معرف الموديل', error: true);
                    } else {
                      _snack('خطأ في الحفظ: $e', error: true);
                    }
                  }
                },
                child: Text(isEdit ? 'تحديث' : 'حفظ'),
              ),
            ],
          );
        },
      ),
    );

    // Dispose controllers
    modelNameCtl.dispose();
    markerCtl.dispose();
    lengthCtl.dispose();
    widthCtl.dispose();
    utilCtl.dispose();
    placedCtl.dispose();
    descCtl.dispose();
  }
}