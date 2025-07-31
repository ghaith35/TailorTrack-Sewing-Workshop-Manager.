import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

class SewingModelsSection extends StatefulWidget {
  final String userRole;
  const SewingModelsSection({super.key, required this.userRole});

  @override
  State<SewingModelsSection> createState() => _SewingModelsSectionState();
}

class _SewingModelsSectionState extends State<SewingModelsSection> {
  String selectedTab = '';

  int divisionMode = 0;
  int customPieces = 2000;

  List<dynamic> archiveModels = [];
  List<dynamic> materialTypes = [];
  List<dynamic> materials = [];
  List<dynamic> availableMaterials = [];
  List<dynamic> seasons = [];
  int? selectedModelId;
  int? selectedSeasonId;
  bool isLoading = false;

  List<dynamic> inProductionBatches = [];

  final String baseUrl = 'http://localhost:8888';

  List<String> get availableTabs {
    return widget.userRole == "Accountant"
        ? ['موديلات تحت الإنتاج']
        : ['أرشيف الموديلات', 'موديلات تحت الإنتاج'];
  }

  Map<String, dynamic>? get selectedModel {
    if (selectedModelId == null) return null;
    try {
      return archiveModels.firstWhere((m) => m['id'] == selectedModelId);
    } catch (e) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    selectedTab = availableTabs.first;
    fetchModels();
    if (selectedTab == 'موديلات تحت الإنتاج') {
      fetchInProductionBatches();
    }
    fetchAvailableMaterials();
    fetchMaterialTypes();
    fetchSeasonsIfAvailable();
  }

  @override
  void didUpdateWidget(SewingModelsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userRole != oldWidget.userRole) {
      setState(() {
        if (!availableTabs.contains(selectedTab)) {
          selectedTab = availableTabs.first;
        }
      });
    }
  }

  Future<void> fetchSeasonsIfAvailable() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/purchases/seasons'));
      if (res.statusCode == 200) {
        setState(() {
          seasons = jsonDecode(res.body);
        });
      }
    } catch (_) {
      seasons = [];
    }
  }
// 1) Extract a generic “show snackbar” helper if you don’t have one already:
void _showSnackBar(String msg, {Color color = Colors.black}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: color),
  );
}

// 2) Delete a model from the archive with confirmation:
Future<void> _deleteModel(Map<String, dynamic> model) async {
  final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف الموديل "${model['name']}"؟'),
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
      ) ??
      false;
  if (!confirm) return;

  try {
    final resp = await http.delete(
      Uri.parse('$baseUrl/models/${model['id']}'),
    );
    if (resp.statusCode == 200) {
      _showSnackBar('تم حذف الموديل', color: Colors.green);
      await fetchModels();
    } else {
      throw 'فشل الحذف';
    }
  } catch (e) {
    _showSnackBar(e.toString(), color: Colors.red);
  }
}

// 3) Delete a production batch with confirmation:
Future<void> _deleteProductionBatch(Map<String, dynamic> batch) async {
  final name = '${batch['model_name']} - ${batch['color']} (${batch['size']})';
  final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف دفعة الإنتاج "$name"؟'),
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
      ) ??
      false;
  if (!confirm) return;

  try {
    final resp = await http.delete(
      Uri.parse('$baseUrl/models/production-batch/${batch['id']}'),
    );
    if (resp.statusCode == 200) {
      _showSnackBar('تم حذف دفعة الإنتاج', color: Colors.green);
      await fetchInProductionBatches();
    } else {
      throw 'فشل الحذف';
    }
  } catch (e) {
    _showSnackBar(e.toString(), color: Colors.red);
  }
}

  Future<void> fetchModels() async {
    setState(() => isLoading = true);
    try {
      String url = '$baseUrl/models/';
      if (selectedSeasonId != null && seasons.isNotEmpty) {
        try {
          url = '$baseUrl/models/by_season/$selectedSeasonId';
          final testRes = await http.get(Uri.parse(url));
          if (testRes.statusCode != 200) {
            url = '$baseUrl/models/';
          }
        } catch (_) {
          url = '$baseUrl/models/';
        }
      }
      final archiveResponse = await http.get(Uri.parse(url));
      if (archiveResponse.statusCode == 200) {
        archiveModels = jsonDecode(archiveResponse.body);
      }
      if (selectedModelId == null && archiveModels.isNotEmpty) {
        selectedModelId = archiveModels.first['id'];
        await fetchMaterials(selectedModelId!);
      } else if (!archiveModels.any((m) => m['id'] == selectedModelId)) {
        selectedModelId = archiveModels.isNotEmpty ? archiveModels.first['id'] : null;
        if (selectedModelId != null) {
          await fetchMaterials(selectedModelId!);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching models: $e')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchMaterialTypes() async {
    final response = await http.get(Uri.parse('$baseUrl/purchases/material_types'));
    if (response.statusCode == 200) {
      setState(() {
        materialTypes = jsonDecode(response.body);
      });
    }
  }

  Future<List<dynamic>> fetchMaterialsByType(int typeId) async {
    final res = await http.get(Uri.parse('$baseUrl/purchases/materials/by_type/$typeId'));
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return [];
  }

  Future<void> fetchAvailableMaterials() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/models/materials/'));
      if (response.statusCode == 200) {
        availableMaterials = jsonDecode(response.body);
      } else {
        throw Exception('Failed to load materials');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching materials: $e')));
    }
  }

  Future<void> fetchMaterials(int modelId) async {
    final response = await http.get(Uri.parse('$baseUrl/models/$modelId/materials'));
    if (response.statusCode == 200) {
      setState(() {
        materials = jsonDecode(response.body);
      });
    } else {
      throw Exception('Failed to load materials');
    }
  }

  Future<void> deleteProductionBatch(int batchId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/models/production-batch/$batchId'));
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف دفعة الإنتاج بنجاح.')),
        );
        await fetchInProductionBatches();
      } else {
        final errorBody = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حذف الدفعة: ${errorBody['error'] ?? response.reasonPhrase}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الاتصال بحذف الدفعة: $e')),
      );
    }
  }

  Future<void> showEditProductionBatchDialog(Map<String, dynamic> batch) async {
    TextEditingController colorCtrl = TextEditingController(text: batch['color']);
    TextEditingController sizeCtrl = TextEditingController(text: batch['size']);
    TextEditingController quantityCtrl = TextEditingController(text: batch['quantity'].toString());

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تعديل دفعة إنتاج'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: colorCtrl,
              decoration: const InputDecoration(labelText: 'اللون'),
            ),
            TextField(
              controller: sizeCtrl,
              decoration: const InputDecoration(labelText: 'المقاس'),
            ),
            TextField(
              controller: quantityCtrl,
              decoration: const InputDecoration(labelText: 'الكمية'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await editProductionBatch(
                batch['id'], colorCtrl.text, sizeCtrl.text, int.tryParse(quantityCtrl.text) ?? batch['quantity']
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> editProductionBatch(int batchId, String color, String size, int quantity) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/models/production-batch/$batchId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'color': color, 'size': size, 'quantity': quantity}),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث دفعة الإنتاج بنجاح.')),
        );
        await fetchInProductionBatches();
      } else {
        final errorBody = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحديث الدفعة: ${errorBody['error'] ?? response.reasonPhrase}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الاتصال بتحديث الدفعة: $e')),
      );
    }
  }

  String formatDate(String date) {
    if (date.isEmpty) return '';
    try {
      final d = DateTime.parse(date);
      return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    } catch (_) {
      return date.split('T').first;
    }
  }

  Future<Map<String, dynamic>> fetchModelCost(int modelId) async {
    String url = '$baseUrl/models/$modelId/cost?division_mode=$divisionMode';
    if (divisionMode == 2) {
      url += '&division_pieces=$customPieces';
    }
    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('fetchModelCost ${res.statusCode}: ${res.reasonPhrase}\n${res.body}');
  }

  void showDivisionMethodDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('طريقة توزيع التكاليف الشهرية'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile(
                value: 0,
                groupValue: divisionMode,
                title: const Text('حسب عدد القطع المنتجة هذا الشهر'),
                onChanged: (v) => setDialogState(() => divisionMode = v as int),
              ),
              RadioListTile(
                value: 1,
                groupValue: divisionMode,
                title: const Text('متوسط سنوي ثابت (2000 قطعة)'),
                onChanged: (v) => setDialogState(() => divisionMode = v as int),
              ),
              RadioListTile(
                value: 2,
                groupValue: divisionMode,
                title: const Text('تخصيص عدد القطع'),
                onChanged: (v) => setDialogState(() => divisionMode = v as int),
              ),
              if (divisionMode == 2)
                TextField(
                  decoration: const InputDecoration(labelText: "عدد القطع"),
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(text: customPieces.toString()),
                  onChanged: (val) {
                    setDialogState(() {
                      customPieces = int.tryParse(val) ?? customPieces;
                    });
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text("إلغاء"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: const Text("تأكيد"),
            onPressed: () {
              setState(() {});
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> addOrEditModel({Map<String, dynamic>? initial}) async {
    final _formKey = GlobalKey<FormState>();

    String? name = initial?['name'];
    DateTime startDate = initial?['start_date'] != null
        ? DateTime.parse(initial!['start_date'])
        : DateTime.now();
    String? imageUrl = initial?['image_url'];

    TextEditingController nameCtrl = TextEditingController(text: name ?? '');
    TextEditingController imageCtrl = TextEditingController(text: imageUrl ?? '');
    TextEditingController cutPriceCtrl = TextEditingController(text: (initial?['cut_price'] ?? '').toString());
    TextEditingController sewingManualCtrl = TextEditingController(text: (initial?['sewing_manual'] ?? (initial?['sewing_price'] ?? '')).toString());
    TextEditingController pressPriceCtrl = TextEditingController(text: (initial?['press_price'] ?? '').toString());
    TextEditingController washingCtrl = TextEditingController(text: (initial?['washing'] ?? '').toString());
    TextEditingController embroideryCtrl = TextEditingController(text: (initial?['embroidery'] ?? '').toString());
    TextEditingController laserCtrl = TextEditingController(text: (initial?['laser'] ?? '').toString());
    TextEditingController printingCtrl = TextEditingController(text: (initial?['printing'] ?? '').toString());
    TextEditingController crochetCtrl = TextEditingController(text: (initial?['crochet'] ?? '').toString());
    TextEditingController sellingPriceCtrl = TextEditingController();
    TextEditingController sizesCtrl = TextEditingController(text: (initial?['sizes'] ?? ''));
    TextEditingController nbrSizesCtrl = TextEditingController(
        text: (initial?['nbr_of_sizes']?.toString() ??
            (initial?['sizes'] != null && (initial!['sizes'] as String).isNotEmpty
                ? (initial!['sizes'] as String).split('-').length.toString()
                : '0')));

    List<Map<String, dynamic>> selectedMaterials = [];
    List<TextEditingController> materialQuantityControllers = [];
    double totalMaterialCost = 0.0;
    double totalCost = 0.0;
    double profit = 0.0;

    if (initial != null) {
      try {
        final response = await http.get(Uri.parse('$baseUrl/models/${initial['id']}/materials'));
        if (response.statusCode == 200) {
          final existingMaterials = jsonDecode(response.body);
          selectedMaterials = existingMaterials.map<Map<String, dynamic>>((material) {
            final availableMaterial = availableMaterials.firstWhere(
                (m) => m['id'] == material['material_id'],
                orElse: () => {'code': material['material_code'], 'name': 'غير معروف', 'price': 0.0}
            );
            return {
              'material_id': material['material_id'],
              'quantity_needed': material['quantity_needed'],
              'material_code': material['material_code'],
              'material_name': availableMaterial['name'],
              'price': material['price'] ?? 0.0,
              'total_cost': material['total_cost'] ?? 0.0,
            };
          }).toList();
          materialQuantityControllers = selectedMaterials
              .map((mat) => TextEditingController(text: (mat['quantity_needed'] ?? '').toString()))
              .toList();
        }
      } catch (e) {
        print('Error loading existing materials: $e');
      }
    }

    void calculateCosts() {
      totalMaterialCost = selectedMaterials.fold(0.0, (sum, material) => sum + (material['total_cost'] ?? 0.0));
      double laborCost = (double.tryParse(cutPriceCtrl.text) ?? 0.0) +
          (double.tryParse(sewingManualCtrl.text) ?? 0.0) +
          (double.tryParse(pressPriceCtrl.text) ?? 0.0);
      double additionalCost = (double.tryParse(washingCtrl.text) ?? 0.0) +
          (double.tryParse(embroideryCtrl.text) ?? 0.0) +
          (double.tryParse(laserCtrl.text) ?? 0.0) +
          (double.tryParse(printingCtrl.text) ?? 0.0) +
          (double.tryParse(crochetCtrl.text) ?? 0.0);
      totalCost = totalMaterialCost + laborCost + additionalCost;
      double sellingPrice = double.tryParse(sellingPriceCtrl.text) ?? 0.0;
      profit = sellingPrice - totalCost;
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          calculateCosts();

          void addMaterial() {
            selectedMaterials.add({
              'material_id': null,
              'quantity_needed': 0.0,
              'material_code': '',
              'material_name': '',
              'price': 0.0,
              'total_cost': 0.0
            });
            materialQuantityControllers.add(TextEditingController(text: '0'));
          }

          void removeMaterial(int index) {
            selectedMaterials.removeAt(index);
            materialQuantityControllers[index].dispose();
            materialQuantityControllers.removeAt(index);
          }

          void selectMaterial(int index, int selectedMaterialId) {
            final selectedMat = availableMaterials.firstWhere((m) => m['id'] == selectedMaterialId);
            selectedMaterials[index]['material_id'] = selectedMaterialId;
            selectedMaterials[index]['material_code'] = selectedMat['code'];
            selectedMaterials[index]['material_name'] = selectedMat['name'];
            selectedMaterials[index]['price'] = selectedMat['price'] ?? 0.0;
            selectedMaterials[index]['quantity_needed'] = 1.0;
            selectedMaterials[index]['total_cost'] = (selectedMat['price'] ?? 0.0) * 1.0;
            materialQuantityControllers[index].text = '1';
          }

          return AlertDialog(
            title: Text(initial == null ? 'إضافة موديل جديد' : 'تعديل موديل'),
            content: Form(
              key: _formKey,
              child: SizedBox(
                width: 500,
                height: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('المعلومات الأساسية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              SizedBox(height: 8),
                              TextFormField(
                                controller: nameCtrl,
                                decoration: const InputDecoration(labelText: 'اسم الموديل'),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'يرجى إدخال اسم الموديل';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 8),
                              TextFormField(
                                controller: imageCtrl,
                                decoration: const InputDecoration(labelText: 'رابط الصورة'),
                              ),
                              SizedBox(height: 8),
                              TextFormField(
                                controller: sizesCtrl,
                                decoration: const InputDecoration(labelText: 'المقاسات (مثال: S-M-L-XL)'),
                                onChanged: (val) {
                                  nbrSizesCtrl.text = val.trim().isEmpty ? '0' : val.trim().split('-').length.toString();
                                },
                              ),
                              SizedBox(height: 8),
                              TextFormField(
                                controller: nbrSizesCtrl,
                                decoration: const InputDecoration(labelText: 'عدد المقاسات'),
                                readOnly: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('تكاليف العمالة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: cutPriceCtrl,
                                      decoration: const InputDecoration(labelText: 'سعر القص'),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'يرجى إدخال سعر القص';
                                        }
                                        final numValue = double.tryParse(value);
                                        if (numValue == null || numValue <= 0) {
                                          return 'يجب أن يكون سعر القص رقمًا موجبًا';
                                        }
                                        return null;
                                      },
                                      onChanged: (_) => setDialogState(() {}),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      controller: sewingManualCtrl,
                                      decoration: const InputDecoration(labelText: 'سعر الخياطة بالقطعة'),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'يرجى إدخال سعر الخياطة';
                                        }
                                        final numValue = double.tryParse(value);
                                        if (numValue == null || numValue <= 0) {
                                          return 'يجب أن يكون سعر الخياطة رقمًا موجبًا';
                                        }
                                        return null;
                                      },
                                      onChanged: (_) => setDialogState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: pressPriceCtrl,
                                      decoration: const InputDecoration(labelText: 'سعر الكي'),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'يرجى إدخال سعر الكي';
                                        }
                                        final numValue = double.tryParse(value);
                                        if (numValue == null || numValue <= 0) {
                                          return 'يجب أن يكون سعر الكي رقمًا موجبًا';
                                        }
                                        return null;
                                      },
                                      onChanged: (_) => setDialogState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('خدمات إضافية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: washingCtrl,
                                      decoration: const InputDecoration(labelText: 'الغسيل'),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value != null && value.isNotEmpty) {
                                          final numValue = double.tryParse(value);
                                          if (numValue == null || numValue < 0) {
                                            return 'يرجى إدخال رقم صالح';
                                          }
                                        }
                                        return null;
                                      },
                                      onChanged: (_) => setDialogState(() {}),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      controller: embroideryCtrl,
                                      decoration: const InputDecoration(labelText: 'التطريز'),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value != null && value.isNotEmpty) {
                                          final numValue = double.tryParse(value);
                                          if (numValue == null || numValue < 0) {
                                            return 'يرجى إدخ  صالح';
                                          }
                                        }
                                        return null;
                                      },
                                      onChanged: (_) => setDialogState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: laserCtrl,
                                      decoration: const InputDecoration(labelText: 'ليزر'),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value != null && value.isNotEmpty) {
                                          final numValue = double.tryParse(value);
                                          if (numValue == null || numValue < 0) {
                                            return 'يرجى إدخال رقم صالح';
                                          }
                                        }
                                        return null;
                                      },
                                      onChanged: (_) => setDialogState(() {}),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      controller: printingCtrl,
                                      decoration: const InputDecoration(labelText: 'الطباعة'),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value != null && value.isNotEmpty) {
                                          final numValue = double.tryParse(value);
                                          if (numValue == null || numValue < 0) {
                                            return 'يرجى إدخال رقم صالح';
                                          }
                                        }
                                        return null;
                                      },
                                      onChanged: (_) => setDialogState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              TextFormField(
                                controller: crochetCtrl,
                                decoration: const InputDecoration(labelText: 'كروشيه'),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value != null && value.isNotEmpty) {
                                    final numValue = double.tryParse(value);
                                    if (numValue == null || numValue < 0) {
                                      return 'يرجى إدخال رقم صالح';
                                    }
                                  }
                                  return null;
                                },
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('المواد الخام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  // Text('التكلفة الإجمالية: ${totalMaterialCost.toStringAsFixed(2)}دج',
                                  //     style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                ],
                              ),
                              SizedBox(height: 8),
                              ...selectedMaterials.asMap().entries.map((entry) {
                                int index = entry.key;
                                Map<String, dynamic> material = entry.value;
                                var materialInfo = availableMaterials.firstWhere(
                                  (m) => m['id'] == material['material_id'],
                                  orElse: () => null,
                                );
                                double availableStock = materialInfo?['stock_quantity'] != null
                                    ? (materialInfo!['stock_quantity'] as num).toDouble()
                                    : 0.0;

                                return Card(
                                  color: Colors.grey[50],
                                  child: ListTile(
                                    title: Text('${material['material_code']} - ${material['material_name']}'),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (material['material_id'] != null)
                                          Row(
                                            children: [
                                              Text('الرصيد المتاح: ', style: TextStyle(color: Colors.teal[900])),
                                              Text('${availableStock.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                      color: availableStock > 0 ? Colors.green : Colors.red,
                                                      fontWeight: FontWeight.bold)),
                                              SizedBox(width: 16),
                                              // Text('السعر: ', style: TextStyle(color: Colors.teal[900])),
                                              // Text(material['price'] != null
                                              //     ? '${(material['price'] as num).toStringAsFixed(2)}دج'
                                              //     : 'غير محدد',
                                              //     style: TextStyle(
                                              //         color: material['price'] != null ? Colors.indigo[800] : Colors.red,
                                              //         fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        Row(
                                          children: [
                                            Text('الكمية: '),
                                            SizedBox(
                                              width: 80,
                                              child: TextFormField(
                                                decoration: InputDecoration(
                                                  isDense: true,
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                ),
                                                keyboardType: TextInputType.number,
                                                controller: materialQuantityControllers[index],
                                                validator: (value) {
                                                  if (material['material_id'] != null && (value == null || value.isEmpty)) {
                                                    return 'الكمية مطلوبة';
                                                  }
                                                  final numValue = double.tryParse(value ?? '');
                                                  if (material['material_id'] != null && (numValue == null || numValue <= 0)) {
                                                    return 'يجب أن تكون الكمية موجبة';
                                                  }
                                                  return null;
                                                },
                                                onChanged: (value) {
                                                  double quantity = double.tryParse(value) ?? 0.0;
                                                  selectedMaterials[index]['quantity_needed'] = quantity;
                                                  selectedMaterials[index]['total_cost'] =
                                                      quantity * (material['price'] as num? ?? 0.0);
                                                  setDialogState(() {});
                                                },
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            // Text('التكلفة: ${(material['total_cost'] as num? ?? 0.0).toStringAsFixed(2)}دج'),
                                          ],
                                        ),
                                        if (material['price'] == null)
                                          Text('تحذير: هذه المادة ليس لها سعر محدد', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () async {
                                        if (initial != null && material['material_id'] != null) {
                                          await deleteMaterialFromModel(initial['id'], material['material_id']);
                                        }
                                        setDialogState(() {
                                          removeMaterial(index);
                                        });
                                      },
                                    ),
                                  ),
                                );
                              }).toList(),
                              SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('إضافة مادة'),
                                  onPressed: () {
                                    setDialogState(() {
                                      _showAddMaterialDialog(selectedMaterials, materialQuantityControllers, setDialogState);
                                    });
                                  },
                                ),
                              ),
                              ...selectedMaterials.asMap().entries.map((entry) {
                                int index = entry.key;
                                Map<String, dynamic> material = entry.value;
                                if (material['material_id'] == null) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: DropdownButtonFormField<int>(
                                      decoration: const InputDecoration(
                                        labelText: 'اختر مادة خام',
                                        border: OutlineInputBorder(),
                                      ),
                                      value: null,
                                      items: availableMaterials
                                          .where((m) => !selectedMaterials.any((sm) => sm['material_id'] == m['id']))
                                          .map((m) {
                                        String label = '${m['code']} - ${m['name']} '
                                            '(${(m['price'] as num? ?? 0.0).toStringAsFixed(2)}دج '
                                            '| رصيد: ${(m['stock_quantity'] as num? ?? 0.0).toStringAsFixed(2)})';
                                        return DropdownMenuItem<int>(
                                          value: m['id'],
                                          child: Text(label),
                                        );
                                      }).toList(),
                                      onChanged: (int? selectedMaterialId) {
                                        if (selectedMaterialId != null) {
                                          setDialogState(() {
                                            selectMaterial(index, selectedMaterialId);
                                          });
                                        }
                                      },
                                    ),
                                  );
                                } else {
                                  return const SizedBox.shrink();
                                }
                              }).toList(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  materialQuantityControllers.forEach((ctrl) => ctrl.dispose());
                  Navigator.pop(context);
                },
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    bool hasInvalidMaterial = selectedMaterials.any((m) =>
                        m['material_id'] != null && (m['quantity_needed'] == null || m['quantity_needed'] <= 0));
                    if (hasInvalidMaterial) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('يرجى إدخال كمية صالحة لجميع المواد المختارة')),
                      );
                      return;
                    }
                    selectedMaterials.removeWhere((material) => material['material_id'] == null);

                    final data = {
                      'name': nameCtrl.text,
                      'start_date': startDate.toIso8601String(),
                      'image_url': imageCtrl.text,
                      'cut_price': double.tryParse(cutPriceCtrl.text) ?? 0,
                      'sewing_price': double.tryParse(sewingManualCtrl.text) ?? 0,
                      'press_price': double.tryParse(pressPriceCtrl.text) ?? 0,
                      'assembly_price': 0,
                      'electricity': 0,
                      'rent': 0,
                      'maintenance': 0,
                      'water': 0,
                      'washing': double.tryParse(washingCtrl.text) ?? 0,
                      'embroidery': double.tryParse(embroideryCtrl.text) ?? 0,
                      'laser': double.tryParse(laserCtrl.text) ?? 0,
                      'printing': double.tryParse(printingCtrl.text) ?? 0,
                      'crochet': double.tryParse(crochetCtrl.text) ?? 0,
                      'sizes': sizesCtrl.text,
                      'nbr_of_sizes': int.tryParse(nbrSizesCtrl.text) ?? 0,
                    };

                    try {
                      int modelId;
                      if (initial == null) {
                        final result = await addModel(data);
                        modelId = result['id'];
                      } else {
                        await updateModel(initial['id'], data);
                        modelId = initial['id'];
                        await http.delete(Uri.parse('$baseUrl/models/$modelId/materials/all'));
                      }

                      for (var material in selectedMaterials) {
                        await addMaterialToModel(modelId, material['material_id'], material['quantity_needed']);
                      }

                      materialQuantityControllers.forEach((ctrl) => ctrl.dispose());
                      Navigator.pop(context);
                      await fetchModels();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(initial == null ? 'تم إضافة الموديل بنجاح' : 'تم تحديث الموديل بنجاح')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ: $e')),
                      );
                    }
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> addModel(Map<String, dynamic> modelData) async {
    final response = await http.post(
      Uri.parse('$baseUrl/models/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(modelData),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to add model');
    }
  }

  Future<void> updateModel(int id, Map<String, dynamic> modelData) async {
    final response = await http.put(
      Uri.parse('$baseUrl/models/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(modelData),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update model');
    }
  }

  Future<void> deleteModel(int id) async {
    await http.delete(Uri.parse('$baseUrl/models/$id'));
    await fetchModels();
  }

  Future<void> addMaterialToModel(int modelId, int materialId, double quantity) async {
    final response = await http.post(
      Uri.parse('$baseUrl/models/$modelId/materials'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'material_id': materialId, 'quantity_needed': quantity}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to add material to model');
    }
  }

  Future<void> deleteMaterialFromModel(int modelId, int materialId) async {
    await http.delete(Uri.parse('$baseUrl/models/$modelId/materials/$materialId'));
    await fetchMaterials(modelId);
  }

  void _showAddMaterialDialog(
    List<Map<String, dynamic>> selectedMaterials,
    List<TextEditingController> materialQuantityControllers,
    void Function(void Function()) setDialogState,
  ) {
    int? selectedMaterialTypeId;
    int? selectedMaterialId;
    List<dynamic> filteredMaterials = [];
    double quantity = 1.0;
    final quantityController = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('إضافة مادة للموديل'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: selectedMaterialTypeId,
                  decoration: const InputDecoration(labelText: 'اختر نوع المادة'),
                  items: materialTypes.map((type) {
                    return DropdownMenuItem(
                      value: type['id'] as int,
                      child: Text(type['name']),
                    );
                  }).toList(),
                  onChanged: (val) async {
                    selectedMaterialTypeId = val;
                    filteredMaterials = await fetchMaterialsByType(val!);
                    setState(() {
                      selectedMaterialId = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: selectedMaterialId,
                  decoration: const InputDecoration(labelText: 'اختر المادة'),
                  items: filteredMaterials.map((m) {
                    return DropdownMenuItem(
                      value: m['id'] as int,
                      child: Text(m['code']),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => selectedMaterialId = val),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: quantityController,
                  decoration: const InputDecoration(labelText: 'الكمية المطلوبة'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'يرجى إدخال الكمية';
                    }
                    final numValue = double.tryParse(value);
                    if (numValue == null || numValue <= 0) {
                      return 'يجب أن تكون الكمية موجبة';
                    }
                    return null;
                  },
                  onChanged: (v) => quantity = double.tryParse(v) ?? 1.0,
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
              onPressed: () {
                if (selectedMaterialId != null && quantity > 0) {
                  setDialogState(() {
                    selectedMaterials.add({
                      'material_id': selectedMaterialId,
                      'quantity_needed': quantity,
                      'material_code': filteredMaterials.firstWhere((m) => m['id'] == selectedMaterialId)['code'],
                      'material_name': filteredMaterials.firstWhere((m) => m['id'] == selectedMaterialId)['type_name'],
                      'price': filteredMaterials.firstWhere((m) => m['id'] == selectedMaterialId)['price'] ?? 0.0,
                      'total_cost': (filteredMaterials.firstWhere((m) => m['id'] == selectedMaterialId)['price'] ?? 0.0) * quantity,
                    });
                    materialQuantityControllers.add(TextEditingController(text: quantity.toString()));
                  });
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى اختيار نوع ومادة وكمية صحيحة')),
                  );
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> fetchInProductionBatches() async {
    setState(() => isLoading = true);
    try {
      final url = '$baseUrl/models/in-production';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final responseBody = response.body;
        if (responseBody.isEmpty) {
          setState(() {
            inProductionBatches = [];
          });
          return;
        }
        try {
          final List<dynamic> data = jsonDecode(responseBody);
          setState(() {
            inProductionBatches = data;
          });
        } catch (jsonError) {
          throw Exception('Failed to parse JSON response: $jsonError');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching in-production models: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> showInitiateProductionDialog() async {
    int? selectedModelForProductionId;
    int manualQuantity = 0;
    int automaticQuantity = 0;
    TextEditingController manualQuantityCtrl = TextEditingController();
    TextEditingController automaticQuantityCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('إنتاج موديل جديد'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'اختر الموديل',
                      border: OutlineInputBorder(),
                    ),
                    value: selectedModelForProductionId,
                    items: archiveModels.map<DropdownMenuItem<int>>((model) {
                      return DropdownMenuItem<int>(
                        value: model['id'],
                        child: Text(model['name']),
                      );
                    }).toList(),
                    onChanged: (int? newValue) {
                      setDialogState(() {
                        selectedModelForProductionId = newValue;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: manualQuantityCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'كمية الإنتاج بالقطعة'),
                    onChanged: (val) {
                      setDialogState(() {
                        manualQuantity = int.tryParse(val) ?? 0;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: automaticQuantityCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'كمية الإنتاج ب خط الإنتاج'),
                    onChanged: (val) {
                      setDialogState(() {
                        automaticQuantity = int.tryParse(val) ?? 0;
                      });
                    },
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
                onPressed: (selectedModelForProductionId != null &&
                        (manualQuantity > 0 || automaticQuantity > 0))
                    ? () async {
                        Navigator.pop(context);
                        await _initiateProductionAdvanced(
                          selectedModelForProductionId!,
                          manualQuantity,
                          automaticQuantity,
                        );
                      }
                    : null,
                child: const Text('بدء الإنتاج'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _initiateProductionAdvanced(int modelId, int manualQuantity, int automaticQuantity) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/models/initiate-production'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model_id': modelId,
          'manual_quantity': manualQuantity,
          'automatic_quantity': automaticQuantity,
        }),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم بدء الإنتاج بنجاح.')),
        );
        await fetchInProductionBatches();
      } else {
        final errorBody = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في بدء الإنتاج: ${errorBody['error'] ?? response.reasonPhrase}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الاتصال ببدء الإنتاج: $e')),
      );
    }
  }

  Future<void> _initiateProductionSimple(int modelId, int quantity) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/models/initiate-production'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model_id': modelId,
          'production_details': [
            {
              'color': '',
              'quantity': quantity,
              'sizes': [],
            }
          ]
        }),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم بدء الإنتاج بنجاح.')),
        );
        await fetchInProductionBatches();
      } else {
        final errorBody = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في بدء الإنتاج: ${errorBody['error'] ?? response.reasonPhrase}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الاتصال ببدء الإنتاج: $e')),
      );
    }
  }

  void _recalculateSizeQuantities(Map<String, dynamic> detail) {
    int totalQuantity = detail['quantity'];
    int numberOfSizes = detail['sizes'].length;
    if (numberOfSizes == 0) return;
    int baseQuantityPerSize = totalQuantity ~/ numberOfSizes;
    int remainder = totalQuantity % numberOfSizes;
    for (int i = 0; i < numberOfSizes; i++) {
      detail['sizes'][i]['quantity'] = baseQuantityPerSize + (i < remainder ? 1 : 0);
    }
  }

  Future<void> _initiateProduction(int modelId, List<Map<String, dynamic>> productionDetails) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/models/initiate-production'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model_id': modelId,
          'production_details': productionDetails,
        }),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم بدء الإنتاج بنجاح. تم خصم المواد وإضافة دفعات الإنتاج.')),
        );
        await fetchInProductionBatches();
      } else {
        final errorBody = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في بدء الإنتاج: ${errorBody['error'] ?? response.reasonPhrase}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الاتصال ببدء الإنتاج: $e')),
      );
    }
  }

  Future<void> _completeProductionBatch(int batchId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/models/complete-production/$batchId'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إكمال دفعة الإنتاج وإضافتها إلى المخزون الجاهز.')),
        );
        final recalcResponse = await http.post(
          Uri.parse('$baseUrl/sewing/recalc-global-prices'),
          headers: {'Content-Type': 'application/json'},
        );
        if (recalcResponse.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تحديث الأسعار العالمية بنجاح.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل في تحديث الأسعار: ${recalcResponse.reasonPhrase}')),
          );
        }
        await fetchInProductionBatches();
      } else {
        final errorBody = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إكمال دفعة الإنتاج: ${errorBody['error'] ?? response.reasonPhrase}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الاتصال بإكمال دفعة الإنتاج: $e')),
      );
    }
  }

  Widget _buildArchiveModels() {
    return Row(
      children: [
        Container(
          width: 400,
          decoration: BoxDecoration(
            color: Colors.grey[100],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'أرشيف الموديلات',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (seasons.isNotEmpty)
                      Column(
                        children: [
                          DropdownButtonFormField<int?>(
                            value: selectedSeasonId,
                            decoration: const InputDecoration(
                              labelText: 'تصفية حسب الموسم',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('جميع المواسم'),
                              ),
                              ...seasons.map<DropdownMenuItem<int?>>((season) {
                                return DropdownMenuItem<int?>(
                                  value: season['id'] as int,
                                  child: Text(season['name'] as String),
                                );
                              }).toList(),
                            ],
                            onChanged: (val) {
                              setState(() {
                                selectedSeasonId = val;
                              });
                              fetchModels();
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('إنشاء موديل جديد', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[600],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => addOrEditModel(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.calculate, color: Colors.white),
                        label: const Text('تعديل طريقة توزيع التكاليف الشهرية', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[600],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => showDivisionMethodDialog(),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: archiveModels.length,
                        itemBuilder: (_, i) => Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          elevation: selectedModelId == archiveModels[i]['id'] ? 4 : 1,
                          color: selectedModelId == archiveModels[i]['id'] ? Colors.grey[100] : Colors.white,
                          child: ListTile(
                            title: Text(
                              archiveModels[i]['name'],
                              style: TextStyle(
                                fontWeight: selectedModelId == archiveModels[i]['id']
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text('تاريخ البدء: ${formatDate(archiveModels[i]['start_date'] ?? "")}'),
                            onTap: () {
                              setState(() {
                                selectedModelId = archiveModels[i]['id'];
                                fetchMaterials(selectedModelId!);
                              });
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.teal),
                                  onPressed: () => addOrEditModel(initial: archiveModels[i]),
                                ),
                                // IconButton(
                                //   icon: const Icon(Icons.delete, color: Colors.red),
                                //   onPressed: () => deleteModel(archiveModels[i]['id']),
                                // ),
                                IconButton(
  icon: const Icon(Icons.delete, color: Colors.red),
  onPressed: () => _deleteModel(archiveModels[i]),
),

                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selectedModel == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.checkroom, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'اختر موديل من القائمة الجانبية',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (selectedModel!['image_url'] != null && selectedModel!['image_url'].isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                selectedModel!['image_url'],
                                height: 100,
                                width: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  height: 100,
                                  width: 100,
                                  color: Colors.grey[300],
                                  child: Icon(Icons.image_not_supported, color: Colors.grey[600]),
                                ),
                              ),
                            ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedModel!['name'],
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold, color: Colors.indigo[800]),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'تاريخ البدء: ${formatDate(selectedModel!['start_date'] ?? "")}',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                                ),
                                if (selectedModel!['sizes'] != null && selectedModel!['sizes'].toString().trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      'المقاسات: ${selectedModel!['sizes']}',
                                      style: TextStyle(color: Colors.teal[700], fontSize: 15, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      FutureBuilder<Map<String, dynamic>?>(
                        future: fetchModelCost(selectedModelId!),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data != null) {
                            final costData = snapshot.data!;
                            return Column(
                              children: [
                                Card(
                                  color: Colors.blue[50],
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'تكلفة الإنتاج بالقطعة',
                                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[800]),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _costItem('تكلفة المواد', costData['material_cost'], Colors.green[700]!),
                                            ),
                                            Expanded(
                                              child: _costItem('تكلفة العمالة', costData['manual_labor_cost'], Colors.orange[700]!),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _costItem('خدمات إضافية', costData['additional_services'], Colors.purple[700]!),
                                            ),
                                            Expanded(
                                              child: _costItem('التكاليف العامة', costData['overhead_share'], Colors.teal[700]!),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _costItem('تكلفة الأمبالاج', costData['emballage_cost'] ?? 0, Colors.brown[700]!),
                                            ),
                                          ],
                                        ),
                                        const Divider(),
                                        _costItem('إجمالي التكلفة', costData['manual_total_cost'], Colors.blue[700]!, isTotal: true),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Card(
                                  color: Colors.orange[50],
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'تكلفة الإنتاج ب خط الإنتاج',
                                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange[800]),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _costItem('تكلفة المواد', costData['material_cost'], Colors.green[700]!),
                                            ),
                                            Expanded(
                                              child: _costItem('تكلفة العمالة', costData['automatic_labor_cost'], Colors.orange[700]!),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _costItem('خدمات إضافية', costData['additional_services'], Colors.purple[700]!),
                                            ),
                                            Expanded(
                                              child: _costItem('التكاليف العامة', costData['overhead_share'], Colors.teal[700]!),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _costItem('تكلفة الخياطة ب خط الإنتاج', costData['sewing_cost'] ?? 0, Colors.cyan[700]!),
                                            ),
                                            Expanded(
                                              child: _costItem('تكلفة الأمبالاج', costData['emballage_cost'] ?? 0, Colors.brown[700]!),
                                            ),
                                          ],
                                        ),
                                        const Divider(),
                                        _costItem('إجمالي التكلفة', costData['automatic_total_cost'], Colors.orange[700]!, isTotal: true),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Card(
                                  color: Colors.grey[50],
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'تفاصيل التكاليف',
                                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey[900]),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _costItem('سعر القص', selectedModel!['cut_price'], Colors.orange[700]!),
                                            ),
                                            Expanded(
                                              child: _costItem('سعر الخياطة بالقطعة', selectedModel!['sewing_price'], Colors.orange[900]!),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _costItem('سعر الكي', selectedModel!['press_price'], Colors.brown[700]!),
                                            ),
                                            Expanded(
                                              child: _costItem('تكلفة الأمبالاج', costData['emballage_cost'] ?? 0, Colors.brown[800]!),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _costItem('تكلفة الخياطة ب خط الإنتاج', costData['sewing_cost'] ?? 0, Colors.cyan[700]!),
                                            ),
                                            Expanded(
                                              child: _costItem('الغسيل', selectedModel!['washing'], Colors.teal[800]!),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _costItem('التطريز', selectedModel!['embroidery'], Colors.purple[700]!),
                                            ),
                                            Expanded(
                                              child: _costItem('ليزر', selectedModel!['laser'], Colors.grey[700]!),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _costItem('الطباعة', selectedModel!['printing'], Colors.blue[700]!),
                                            ),
                                            Expanded(
                                              child: _costItem('كروشيه', selectedModel!['crochet'], Colors.pink[700]!),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Card(
                                  color: Colors.teal[50],
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('تفاصيل التكاليف الشهرية',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal[900])),
                                        const Divider(height: 24),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          children: [
                                            Expanded(
                                              child: _costItem('الكهرباء', costData['electricity_share'], Colors.amber[700]!),
                                            ),
                                            Expanded(child: _costItem('الإيجار', costData['rent_share'], Colors.brown[700]!)),
                                            Expanded(
                                              child: _costItem('الصيانة', costData['maintenance_share'], Colors.grey[700]!),
                                            ),
                                            Expanded(child: _costItem('الماء', costData['water_share'], Colors.blue[700]!)),
                                            Expanded(
                                              child: _costItem('النقل', costData['transport_share'], Colors.indigo[700]!),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Text('عدد القطع المنتجة هذا الشهر: ${costData['pieces']}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                                        const SizedBox(height: 8),
                                        Text(_getDivisionModeText(),
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal[800])),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            );
                          }
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          );
                        },
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('المواد المستخدمة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 8),
                              if (materials.isEmpty)
                                Text('لا توجد مواد مضافة لهذا الموديل', style: TextStyle(color: Colors.grey[600]))
                              else
                                ...materials.map((material) {
                                  return Card(
                                    color: Colors.grey[50],
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.indigo[100],
                                        child: Text(
                                          material['material_code'].substring(0, 2).toUpperCase(),
                                          style: TextStyle(color: Colors.indigo[800], fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      title: Text('${material['material_code']}'),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('الكمية المطلوبة: ${material['quantity_needed']}'),
                                          if (material['price'] != null)
                                            Text('السعر: ${(material['price'] as num? ?? 0.0).toStringAsFixed(2)}دج'),
                                          if (material['total_cost'] != null)
                                            Text('التكلفة الإجمالية: ${(material['total_cost'] as num? ?? 0.0).toStringAsFixed(2)}دج',
                                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[700])),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  String _getDivisionModeText() {
    switch (divisionMode) {
      case 0:
        return 'طريقة التوزيع: حسب عدد القطع المنتجة هذا الشهر';
      case 1:
        return 'طريقة التوزيع: متوسط سنوي ثابت (2000 قطعة)';
      case 2:
        return 'طريقة التوزيع: تخصيص عدد القطع ($customPieces قطعة)';
      default:
        return '';
    }
  }

  Widget _buildProductionModels() {
    return Row(
      children: [
        Container(
          width: 400,
          decoration: BoxDecoration(
            color: Colors.green[50],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'موديلات تحت الإنتاج',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green[800]),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('إنتاج موديل جديد', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => showInitiateProductionDialog(),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : inProductionBatches.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.factory_outlined, size: 48, color: Colors.green[300]),
                                const SizedBox(height: 16),
                                Text(
                                  'لا توجد موديلات تحت الإنتاج حالياً',
                                  style: TextStyle(color: Colors.green[600]),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'اضغط على "إنتاج موديل جديد" للبدء',
                                  style: TextStyle(color: Colors.green[400], fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: inProductionBatches.length,
                            itemBuilder: (_, i) {
                              final batch = inProductionBatches[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                elevation: 1,
                                color: Colors.white,
                                child: ListTile(
                                  title: Text('${batch['model_name']} - ${batch['color']} (${batch['size']})'),
                                  subtitle: Text(
                                      'الكمية: ${batch['quantity']} | تاريخ: ${formatDate(batch['production_date'] ?? "")}'),
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.green[200],
                                    child: Icon(Icons.work, color: Colors.green[800]),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.teal),
                                        tooltip: 'تعديل الدفعة',
                                        onPressed: () => showEditProductionBatchDialog(batch),
                                      ),
                                      // IconButton(
                                      //   icon: const Icon(Icons.delete, color: Colors.red),
                                      //   tooltip: 'حذف الدفعة',
                                      //   onPressed: () => deleteProductionBatch(batch['id']),
                                      // ),
                                      IconButton(
  icon: const Icon(Icons.delete, color: Colors.red),
  tooltip: 'حذف الدفعة',
  onPressed: () => _deleteProductionBatch(inProductionBatches[i]),
),
                                      IconButton(
                                        icon: const Icon(Icons.check_circle, color: Colors.blue),
                                        tooltip: 'إكمال الإنتاج',
                                        onPressed: () => _completeProductionBatch(batch['id']),
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
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'هنا ستظهر تفاصيل دفعات الإنتاج عند اختيارها (ميزة مستقبلية)',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _costItem(String label, dynamic value, Color color, {bool isTotal = false}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14 : 12,
              color: color,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '${(value ?? 0.0).toStringAsFixed(2)}دج',
            style: TextStyle(
              fontSize: isTotal ? 18 : 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _spec(String label, dynamic value) {
    if (value == null || value.toString().isEmpty || value == 0) return SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text('$label: ${value.toString()}دج', style: const TextStyle(fontSize: 14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: availableTabs.map((tab) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ChoiceChip(
              label: Text(tab),
              selected: selectedTab == tab,
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                color: selectedTab == tab ? Colors.white : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    selectedTab = tab;
                    if (tab == 'موديلات تحت الإنتاج') {
                      fetchInProductionBatches();
                    } else {
                      fetchModels();
                    }
                  });
                }
              },
            ),
          )).toList(),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: selectedTab == 'أرشيف الموديلات' ? _buildArchiveModels() : _buildProductionModels(),
        ),
      ],
    );
  }
}