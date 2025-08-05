import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import '../main.dart';

class SewingWarehouseSection extends StatefulWidget {
  const SewingWarehouseSection({Key? key}) : super(key: key);

  @override
  State<SewingWarehouseSection> createState() => _SewingWarehouseSectionState();
}

class _SewingWarehouseSectionState extends State<SewingWarehouseSection> {
  int selectedTab = 0;
  final tabs = ['البضاعة الجاهزة', 'المواد الخام'];

  // Ready products state
  List<dynamic> readyProducts = [];
  bool isReadyProductsLoading = false;
  String get _apiUrl => '${globalServerUri.toString()}';

  // Raw materials state
  List<dynamic> types = [];
  int? selectedTypeId;
  String? selectedTypeName;
  List<dynamic> specs = [];
  List<dynamic> materials = [];
  bool isTypesLoading = false;
  bool isMaterialsLoading = false;

  // Scroll controllers
  final _readyProductsH = ScrollController();
  final _readyProductsV = ScrollController();
  final _rawMaterialsH = ScrollController();
  final _rawMaterialsV = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchReadyProducts();
    fetchTypes();
  }

  @override
  void dispose() {
    _readyProductsH.dispose();
    _readyProductsV.dispose();
    _rawMaterialsH.dispose();
    _rawMaterialsV.dispose();
    super.dispose();
  }

  // ================= Ready Products =================
  Future<void> _fetchReadyProducts() async {
    setState(() => isReadyProductsLoading = true);
    try {
      final res = await http.get(Uri.parse('${_apiUrl}/sewing/product-inventory'));
      if (res.statusCode == 200) {
        readyProducts = jsonDecode(res.body) as List;
      } else {
        _showSnackBar('فشل في جلب البضاعة الجاهزة', color: Colors.red);
      }
    } catch (e) {
      _showSnackBar('خطأ: $e', color: Colors.red);
    } finally {
      setState(() => isReadyProductsLoading = false);
    }
  }

  // Fetch model details for dialog
  Future<Map<String, dynamic>?> _fetchModelDetails(int modelId) async {
    try {
      final res = await http.get(Uri.parse('$_apiUrl/models/$modelId'));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        _showSnackBar('فشل في جلب تفاصيل الموديل', color: Colors.red);
        return null;
      }
    } catch (e) {
      _showSnackBar('خطأ: $e', color: Colors.red);
      return null;
    }
  }

  // Show model details dialog
  Future<void> _showModelDetailsDialog(int modelId) async {
    final model = await _fetchModelDetails(modelId);
    if (model == null) return;

    await showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                model['image_url'] != null && model['image_url'].isNotEmpty
                    ? '$_apiUrl${model['image_url']}'
                    : '',
                fit: BoxFit.contain,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (ctx, err, st) => const Center(
                  child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show material image dialog
  Future<void> _showMaterialImageDialog(String imagePath, {bool isLocal = false}) async {
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: isLocal
                  ? Image.file(
                      File(imagePath),
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, err, st) => const Center(
                        child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
                      ),
                    )
                  : Image.network(
                      '$_apiUrl$imagePath',
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (ctx, err, st) => const Center(
                        child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
                      ),
                    ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String msg, {Color color = Colors.black}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
      ),
    );
  }

  // ================= Raw Materials ================
  Future<void> fetchTypes() async {
    setState(() => isTypesLoading = true);
    try {
      final res = await http.get(Uri.parse('${_apiUrl}/sewing/material-types'));
      if (res.statusCode == 200) {
        types = jsonDecode(res.body) as List;
        if (types.isNotEmpty && selectedTypeId == null) {
          selectedTypeId = types.first['id'];
          selectedTypeName = types.first['name'];
          await fetchMaterialsForType(selectedTypeId!);
        }
      } else {
        _showSnackBar('فشل في جلب أنواع المواد', color: Colors.red);
      }
    } catch (e) {
      _showSnackBar('خطأ: $e', color: Colors.red);
    } finally {
      setState(() => isTypesLoading = false);
    }
  }

  Future<void> fetchMaterialsForType(int typeId) async {
    setState(() {
      isMaterialsLoading = true;
      specs = [];
      materials = [];
    });
    try {
      final res = await http.get(Uri.parse('${_apiUrl}/sewing/materials?type_id=$typeId'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        specs = data['specs'];
        materials = data['materials'];
      } else {
        _showSnackBar('فشل في جلب المواد', color: Colors.red);
      }
    } catch (e) {
      _showSnackBar('خطأ: $e', color: Colors.red);
    } finally {
      setState(() => isMaterialsLoading = false);
    }
  }

  Future<void> addOrEditType([Map<String, dynamic>? t]) async {
    final isEdit = t != null;
    final _formKey = GlobalKey<FormState>();
    final nameCtl = TextEditingController(text: t?['name'] ?? '');
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
              title: Text(isEdit ? 'تعديل نوع المادة' : 'إضافة نوع مادة'),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtl,
                        decoration: const InputDecoration(labelText: 'اسم النوع'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'اسم النوع مطلوب' : null,
                      ),
                      const SizedBox(height: 16),
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
                      ...specsList.asMap().entries.map((entry) {
                        final idx = entry.key;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: specsList[idx]['name'],
                                  decoration:
                                      const InputDecoration(labelText: 'اسم المواصفة'),
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
                    if (!_formKey.currentState!.validate()) return;
                    if (specsList.isEmpty) {
                      _showSnackBar('أضف مواصفة واحدة على الأقل', color: Colors.red);
                      return;
                    }
                    final payload = {
                      'name': nameCtl.text.trim(),
                      'specs': specsList
                          .map((s) => {'name': s['name']!.trim()})
                          .toList(),
                    };
                    try {
                      final url = isEdit
                          ? '$_apiUrl/sewing/material-types/${t!['id']}'
                          : '$_apiUrl/sewing/material-types';
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
                        await fetchTypes();
                        _showSnackBar('تم الحفظ', color: Colors.green);
                      } else {
                        _showSnackBar('فشل الحفظ (#${res.statusCode})', color: Colors.red);
                      }
                    } catch (e) {
                      _showSnackBar('خطأ: $e', color: Colors.red);
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

  Future<void> _addOrEditReadyProduct([Map<String, dynamic>? product]) async {
    final isEdit = product != null;
    final _formKey = GlobalKey<FormState>();
    final modelIdCtl = TextEditingController(
        text: product?['model_id']?.toString() ?? '');
    final qtyCtl = TextEditingController(
        text: product?['quantity']?.toString() ?? '');
    final sizesDisplay = product?['sizes'] ?? '';
    final nbrSizesDisplay = product?['nbr_of_sizes']?.toString() ?? '';

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(isEdit ? 'تعديل منتج' : 'إضافة منتج'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: modelIdCtl,
                  decoration: const InputDecoration(labelText: 'معرّف الموديل'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return (n == null || n <= 0) ? 'أدخل معرف موديل صالح' : null;
                  },
                ),
                if (isEdit) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('المقاسات: ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(sizesDisplay),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('عدد المقاسات: ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(nbrSizesDisplay),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  controller: qtyCtl,
                  decoration: const InputDecoration(labelText: 'الكمية'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = double.tryParse(v ?? '') ?? 0;
                    return n <= 0 ? 'أدخل قيمة كمية صالحة' : null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final payload = {
                  'warehouse_id': 1,
                  'model_id': int.parse(modelIdCtl.text.trim()),
                  'quantity': double.parse(qtyCtl.text.trim()),
                };
                try {
                  final uri = isEdit
                      ? '${_apiUrl}/sewing/product-inventory/${product!['id']}'
                      : '${_apiUrl}/sewing/product-inventory';
                  final resp = isEdit
                      ? await http.put(
                          Uri.parse(uri),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(payload))
                      : await http.post(
                          Uri.parse(uri),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(payload));
                  if (resp.statusCode == 200) {
                    Navigator.pop(ctx);
                    await _fetchReadyProducts();
                    _showSnackBar('تم الحفظ', color: Colors.green);
                  } else {
                    _showSnackBar('فشل الحفظ (#${resp.statusCode})', color: Colors.red);
                  }
                } catch (e) {
                  _showSnackBar('خطأ: $e', color: Colors.red);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> addOrEditMaterial({Map<String, dynamic>? material}) async {
    final isEdit = material != null;
    final _formKey = GlobalKey<FormState>();
    final codeCtl = TextEditingController(text: material?['code'] ?? '');
    final specValues = material == null
        ? specs
            .map((s0) => {
                  'spec_id': s0['id'],
                  'spec_name': s0['name'],
                  'value': ''
                })
            .toList()
        : List<Map<String, dynamic>>.from(material['specs'] as List);
    File? _pickedImageFile;
    String? _imageUrl = material?['image_url'];

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(isEdit ? 'تعديل المادة' : 'إضافة مادة'),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: codeCtl,
                    decoration: const InputDecoration(labelText: 'الكود'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'الكود مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.image),
                        label: const Text('اختر صورة'),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['png', 'jpg', 'jpeg'],
                            withData: false,
                          );
                          if (result?.files.single.path != null) {
                            setD(() {
                              _pickedImageFile = File(result!.files.single.path!);
                              _imageUrl = null; // Clear network image when new file is picked
                            });
                          }
                        },
                      ),
                      if (_pickedImageFile != null || (_imageUrl != null && _imageUrl!.isNotEmpty)) ...[
                        const SizedBox(width: 8),
                        Stack(
                          alignment: Alignment.topRight,
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (_pickedImageFile != null) {
                                  _showMaterialImageDialog(_pickedImageFile!.path, isLocal: true);
                                } else if (_imageUrl != null && _imageUrl!.isNotEmpty) {
                                  _showMaterialImageDialog(_imageUrl!);
                                }
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _pickedImageFile != null
                                    ? Image.file(
                                        _pickedImageFile!,
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 60,
                                          height: 60,
                                          color: Colors.grey[300],
                                          child: const Icon(Icons.image_not_supported, color: Colors.grey),
                                        ),
                                      )
                                    : Image.network(
                                        '$_apiUrl$_imageUrl',
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 60,
                                          height: 60,
                                          color: Colors.grey[300],
                                          child: const Icon(Icons.image_not_supported, color: Colors.grey),
                                        ),
                                      ),
                              ),
                            ),
                            Positioned(
                              right: -6,
                              top: -6,
                              child: InkWell(
                                onTap: () => setD(() {
                                  _pickedImageFile = null;
                                  _imageUrl = null; // Clear both local and network image
                                }),
                                child: const CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.red,
                                  child: Icon(Icons.close, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...specValues.asMap().entries.map((e) {
                    final i = e.key;
                    final spec = specValues[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        initialValue: spec['value'] as String?,
                        decoration: InputDecoration(labelText: spec['spec_name']),
                        onChanged: (v) => specValues[i]['value'] = v,
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final data = {
                  'type_id': selectedTypeId,
                  'code': codeCtl.text.trim(),
                  'specs': specValues
                      .map((s) => {
                            'spec_id': s['spec_id'],
                            'value': (s['value'] as String).trim(),
                          })
                      .toList(),
                };
                try {
                  final result = await _uploadMaterialWithImage(
                    isEdit ? material!['id'] : null,
                    data,
                    _pickedImageFile,
                    _pickedImageFile == null && _imageUrl == null && isEdit,
                  );
                  Navigator.pop(ctx);
                  await fetchMaterialsForType(selectedTypeId!);
                  _showSnackBar('تم الحفظ', color: Colors.green);
                } catch (e) {
                  _showSnackBar('خطأ: $e', color: Colors.red);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _uploadMaterialWithImage(
      int? existingId, Map<String, dynamic> data, File? imageFile, bool clearImage) async {
    final uri = existingId == null
        ? Uri.parse('$_apiUrl/sewing/materials')
        : Uri.parse('$_apiUrl/sewing/materials/$existingId');
    final req = http.MultipartRequest(existingId == null ? 'POST' : 'PUT', uri);

    req.fields['type_id'] = data['type_id'].toString();
    req.fields['code'] = data['code'];
    req.fields['specs'] = jsonEncode(data['specs']);

    if (imageFile != null) {
      final ext = p.extension(imageFile.path).replaceFirst('.', '');
      req.files.add(await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
        contentType: MediaType('image', ext),
      ));
    } else if (clearImage) {
      req.fields['image'] = '';
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body);
    } else {
      throw Exception('Upload failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<void> _deleteReadyProduct(int? id) async {
    if (id == null) {
      _showSnackBar('معرف المنتج غير صالح', color: Colors.red);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل تريد حذف هذا المنتج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      final resp = await http.delete(
        Uri.parse('${_apiUrl}/sewing/product-inventory/$id'),
      );
      if (resp.statusCode == 200) {
        _showSnackBar('تم حذف المنتج', color: Colors.green);
        await _fetchReadyProducts();
      } else {
        _showSnackBar('فشل الحذف (#${resp.statusCode})', color: Colors.red);
      }
    } catch (e) {
      _showSnackBar('خطأ: $e', color: Colors.red);
    }
  }

  Future<void> _deleteType(int id, String name) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('تأكيد الحذف'),
      content: Text('هل تريد حذف نوع المادة "$name"؟'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('حذف'),
        ),
      ],
    ),
  ) ?? false;
  if (!confirm) return;

  try {
    final resp = await http.delete(
      Uri.parse('${_apiUrl}/sewing/material-types/$id'),
    );
    if (resp.statusCode == 200) {
      _showSnackBar('تم حذف نوع المادة', color: Colors.green);
      await fetchTypes();
      setState(() {
        selectedTypeId = null;
        selectedTypeName = null;
        specs = [];
        materials = [];
      });
    } else {
      _showSnackBar('فشل الحذف (#${resp.statusCode})', color: Colors.red);
    }
  } catch (e) {
    _showSnackBar('خطأ: $e', color: Colors.red);
  }
}

  Future<void> _deleteMaterial(int id, String code) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف المادة "$code"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    ) ?? false;
    if (!confirm) return;

    try {
      final resp = await http.delete(
        Uri.parse('${_apiUrl}/sewing/materials/$id'),
      );
      if (resp.statusCode == 200) {
        _showSnackBar('تم حذف المادة', color: Colors.green);
        await fetchMaterialsForType(selectedTypeId!);
      } else {
        _showSnackBar('فشل الحذف (#${resp.statusCode})', color: Colors.red);
      }
    } catch (e) {
      _showSnackBar('خطأ: $e', color: Colors.red);
    }
  }

  Widget _buildReadyProducts() {
    if (isReadyProductsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (readyProducts.isEmpty) {
      return const Center(child: Text('لا توجد بيانات لعرضها'));
    }

    return Scrollbar(
      controller: _readyProductsH,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _readyProductsH,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1150,
          child: Scrollbar(
            controller: _readyProductsV,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _readyProductsV,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(
                  Theme.of(context).colorScheme.primary,
                ),
                columns: const [
                  DataColumn(label: Text('الصورة', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('الموديل', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('المقاسات', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('عدد المقاسات', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('الكمية', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('السعر للوحدة', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('خيارات', style: TextStyle(color: Colors.white))),
                ],
                rows: readyProducts.map((p) {
                  final int? id = p['id'] is int ? p['id'] as int : null;
                  return DataRow(cells: [
                    DataCell(
                      GestureDetector(
                        onTap: () => _showModelDetailsDialog(p['model_id']),
                        child: p['image_url'] != null && p['image_url'].isNotEmpty
                            ? Image.network(
                                '$_apiUrl${p['image_url']}',
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50),
                              )
                            : const Icon(Icons.image_not_supported, size: 50),
                      ),
                    ),
                    DataCell(Text(p['model_name'] ?? '')),
                    DataCell(Text(p['sizes'] ?? '')),
                    DataCell(Text('${p['nbr_of_sizes'] ?? 0}')),
                    DataCell(Text('${p['quantity'] ?? ''}')),
                    DataCell(Text('${(p['global_price'] ?? 0).toStringAsFixed(2)} دج')),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.teal),
                          onPressed: () => _addOrEditReadyProduct(p),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteReadyProduct(id),
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
    );
  }

  Widget _buildRawMaterials() {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Container(
          width: 400,
          color: Colors.grey[100],
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
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'بحث باسم النوع',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('إضافة نوع مادة', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[600],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => addOrEditType(),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: isTypesLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: types.length,
                        itemBuilder: (_, i) {
                          final t = types[i];
                          return ListTile(
                            title: Text(t['name']),
                            selected: selectedTypeId == t['id'],
                            onTap: () async {
                              setState(() {
                                selectedTypeId = t['id'];
                                selectedTypeName = t['name'];
                              });
                              await fetchMaterialsForType(selectedTypeId!);
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.teal),
                                  onPressed: () => addOrEditType(t),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteType(t['id'] as int, t['name'] as String),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: isMaterialsLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: Text('إضافة مادة (${selectedTypeName ?? ''})'),
                          onPressed: selectedTypeId != null ? () => addOrEditMaterial() : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: specs.isEmpty
                          ? const Center(child: Text('لا توجد مواصفات لهذا النوع'))
                          : Scrollbar(
                              controller: _rawMaterialsH,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _rawMaterialsH,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: 950,
                                  child: Scrollbar(
                                    controller: _rawMaterialsV,
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      controller: _rawMaterialsV,
                                      child: DataTable(
                                        headingRowColor: MaterialStateProperty.all(
                                          Theme.of(context).colorScheme.primary,
                                        ),
                                        columns: [
                                          const DataColumn(
                                            label: Text('الصورة', style: TextStyle(color: Colors.white)),
                                          ),
                                          const DataColumn(
                                            label: Text('الكود', style: TextStyle(color: Colors.white)),
                                          ),
                                          const DataColumn(
                                            label: Text('الكمية', style: TextStyle(color: Colors.white)),
                                          ),
                                          const DataColumn(
                                            label: Text('السعر', style: TextStyle(color: Colors.white)),
                                          ),
                                          ...specs.map((s) => DataColumn(
                                                label: Text(s['name'], style: const TextStyle(color: Colors.white)),
                                              )),
                                          const DataColumn(
                                            label: Text('خيارات', style: TextStyle(color: Colors.white)),
                                          ),
                                        ],
                                        rows: materials.map((material) {
                                          final specVals = material['specs'] as List;
                                          return DataRow(cells: [
                                            DataCell(
                                              GestureDetector(
                                                onTap: () {
                                                  if (material['image_url'] != null &&
                                                      material['image_url'].isNotEmpty) {
                                                    _showMaterialImageDialog(material['image_url']);
                                                  }
                                                },
                                                child: material['image_url'] != null &&
                                                        material['image_url'].isNotEmpty
                                                    ? Image.network(
                                                        '$_apiUrl${material['image_url']}',
                                                        width: 50,
                                                        height: 50,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (_, __, ___) =>
                                                            const Icon(Icons.broken_image, size: 50),
                                                      )
                                                    : const Icon(Icons.image_not_supported, size: 50),
                                              ),
                                            ),
                                            DataCell(Text(material['code'] ?? '')),
                                            DataCell(Text(material['stock_quantity']?.toString() ?? '')),
                                            DataCell(Text(
                                              (material['last_unit_price'] != null &&
                                                      material['last_unit_price'] > 0)
                                                  ? material['last_unit_price'].toString()
                                                  : '—',
                                            )),
                                            ...specVals.map((s) => DataCell(Text(s['value'] ?? ''))),
                                            DataCell(Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.edit, color: Colors.teal),
                                                  onPressed: () => addOrEditMaterial(material: material),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete, color: Colors.red),
                                                  onPressed: () => _deleteMaterial(
                                                    material['id'] as int,
                                                    material['code'] as String,
                                                  ),
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
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            tabs.length,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ChoiceChip(
                label: Text(tabs[i]),
                selected: selectedTab == i,
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(
                  color: selectedTab == i ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (_) => setState(() => selectedTab = i),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: selectedTab == 0 ? _buildReadyProducts() : _buildRawMaterials()),
      ],
    );
  }
}