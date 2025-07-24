import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
      final res = await http.get(Uri.parse('http://localhost:8888/sewing/product-inventory'));
      if (res.statusCode == 200) {
        readyProducts = jsonDecode(res.body) as List;
      } else {
        throw Exception('فشل في جلب البضاعة الجاهزة');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      setState(() => isReadyProductsLoading = false);
    }
  }

  // ================= Raw Materials ================
  Future<void> fetchTypes() async {
    setState(() => isTypesLoading = true);
    final res = await http.get(Uri.parse('http://localhost:8888/sewing/material-types'));
    if (res.statusCode == 200) {
      types = jsonDecode(res.body) as List;
      if (types.isNotEmpty && selectedTypeId == null) {
        selectedTypeId = types.first['id'];
        selectedTypeName = types.first['name'];
        await fetchMaterialsForType(selectedTypeId!);
      }
    }
    setState(() => isTypesLoading = false);
  }

  // Future<void> fetchMaterialsForType(int typeId) async {
  //   setState(() {
  //     isMaterialsLoading = true;
  //     specs = [];
  //     materials = [];
  //   });
  //   final res = await http.get(Uri.parse('http://localhost:8888/sewing/materials?type_id=$typeId'));
  //   if (res.statusCode == 200) {
  //     final data = jsonDecode(res.body);
  //     specs = data['specs'];
  //     materials = data['materials'];
  //   }
  //   setState(() => isMaterialsLoading = false);
  // }

  Future<void> fetchMaterialsForType(int typeId) async {
    setState(() {
      isMaterialsLoading = true;
      specs = [];
      materials = [];
    });
    final res = await http.get(Uri.parse('http://localhost:8888/sewing/materials?type_id=$typeId'));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      specs = data['specs'];
      materials = data['materials'];
    }
    setState(() => isMaterialsLoading = false);
  }

  Future<void> addOrEditType({Map<String, dynamic>? current}) async {
    final isEdit = current != null;
    final nameCtrl = TextEditingController(text: current?['name'] ?? '');
    final specsList = current == null
        ? <Map<String,dynamic>>[]
        : (current['specs'] as List).map((e) => {'id': e['id'], 'name': e['name']}).toList();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(isEdit ? 'تعديل نوع المادة' : 'إضافة نوع مادة'),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم النوع')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('المواصفات', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.add), onPressed: () => setDialog(() => specsList.add({'name': ''}))),
                  ],
                ),
                ...specsList.asMap().entries.map((entry) {
                  final i = entry.key;
                  final spec = entry.value;
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: spec['name']),
                          onChanged: (v) => spec['name'] = v,
                          decoration: const InputDecoration(labelText: 'اسم المواصفة'),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.delete), onPressed: () => setDialog(() => specsList.removeAt(i))),
                    ],
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            TextButton(
              onPressed: () async {
                final body = jsonEncode({
                  'name': nameCtrl.text,
                  'specs': specsList.where((s) => (s['name'] as String).trim().isNotEmpty).toList(),
                });
                if (isEdit) {
                  await http.put(
                    Uri.parse('http://localhost:8888/sewing/material-types/${current!['id']}'),
                    headers: {'Content-Type': 'application/json'},
                    body: body,
                  );
                } else {
                  await http.post(
                    Uri.parse('http://localhost:8888/sewing/material-types'),
                    headers: {'Content-Type': 'application/json'},
                    body: body,
                  );
                }
                Navigator.pop(context);
                await fetchTypes();
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> deleteType(int id) async {
    await http.delete(Uri.parse('http://localhost:8888/sewing/material-types/$id'));
    await fetchTypes();
    setState(() {
      selectedTypeId = null;
      selectedTypeName = null;
      specs = [];
      materials = [];
    });
  }

  Future<void> addOrEditMaterial({Map<String, dynamic>? material}) async {
    final isEdit = material != null;
    final codeCtrl = TextEditingController(text: material?['code'] ?? '');
    final stockCtrl = TextEditingController(text: material?['stock_quantity']?.toString() ?? '');
    final specValues = material == null
        ? specs.map((s) => {'spec_id': s['id'], 'spec_name': s['name'], 'value': ''}).toList()
        : List<Map<String, dynamic>>.from(material['specs'] as List);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? 'تعديل المادة' : 'إضافة مادة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'الكود')),
              // TextField(controller: stockCtrl, decoration: const InputDecoration(labelText: 'الكمية (اختياري)'), keyboardType: TextInputType.number),
              ...specValues.map((s) => TextField(
                    controller: TextEditingController(text: s['value']),
                    decoration: InputDecoration(labelText: s['spec_name']),
                    onChanged: (v) => s['value'] = v,
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              final body = jsonEncode({
                'type_id': selectedTypeId,
                'code': codeCtrl.text,
                'stock_quantity': double.tryParse(stockCtrl.text) ?? 0,
                'specs': specValues.map((s) => {'spec_id': s['spec_id'], 'value': s['value']}).toList(),
              });
              if (isEdit) {
                await http.put(
                  Uri.parse('http://localhost:8888/sewing/materials/${material!['id']}'),
                  headers: {'Content-Type': 'application/json'},
                  body: body,
                );
              } else {
                await http.post(
                  Uri.parse('http://localhost:8888/sewing/materials'),
                  headers: {'Content-Type': 'application/json'},
                  body: body,
                );
              }
              Navigator.pop(context);
              await fetchMaterialsForType(selectedTypeId!);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
Future<void> _addOrEditReadyProduct([Map<String, dynamic>? product]) async {
    final isEdit = product != null;
    final modelIdCtrl = TextEditingController(text: product?['model_id']?.toString() ?? '');
    final qtyCtrl = TextEditingController(text: product?['quantity']?.toString() ?? '');
    // Display only (not editable)
    final sizesDisplay = product?['sizes'] ?? '';
    final nbrSizesDisplay = product?['nbr_of_sizes']?.toString() ?? '';

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? 'تعديل منتج' : 'إضافة منتج'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: modelIdCtrl,
              decoration: const InputDecoration(labelText: 'معرف الموديل'),
              keyboardType: TextInputType.number,
            ),
            if (isEdit)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('المقاسات: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(sizesDisplay),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('عدد المقاسات: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(nbrSizesDisplay),
                      ],
                    ),
                  ],
                ),
              ),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: 'الكمية'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              final body = jsonEncode({
                'warehouse_id': 1, // or from your dynamic state if needed
                'model_id': int.tryParse(modelIdCtrl.text),
                'quantity': double.tryParse(qtyCtrl.text) ?? 0,
              });
              final url = isEdit
                  ? 'http://localhost:8888/sewing/product-inventory/${product!['id']}'
                  : 'http://localhost:8888/sewing/product-inventory';
              final req = isEdit
                  ? http.put(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: body)
                  : http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: body);
              await req;
              Navigator.pop(context);
              await _fetchReadyProducts();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteReadyProduct(int id) async {
    await http.delete(Uri.parse('http://localhost:8888/sewing/product-inventory/$id'));
    await _fetchReadyProducts();
  }

  Widget _buildReadyProducts() {
    if (isReadyProductsLoading) return const Center(child: CircularProgressIndicator());
    if (readyProducts.isEmpty) return const Center(child: Text('لا توجد بيانات لعرضها'));

    return Scrollbar(
      controller: _readyProductsH,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _readyProductsH,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1050, // Increased width for the new column
          child: Scrollbar(
            controller: _readyProductsV,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _readyProductsV,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                columns: const [
                  DataColumn(label: Text('الموديل', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('المقاسات', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('عدد المقاسات', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('الكمية', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('السعر للوحدة', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('خيارات', style: TextStyle(color: Colors.white))),
                ],
                rows: readyProducts.map((p) {
                  return DataRow(cells: [
                    DataCell(Text(p['model_name'] ?? '')),
                    DataCell(Text(p['sizes'] ?? '')),
                    DataCell(Text('${p['nbr_of_sizes'] ?? 0}')),
                    DataCell(Text('${p['quantity'] ?? ''}')),
                    DataCell(Text('${(p['global_price'] ?? 0).toStringAsFixed(2)} دج')), // NEW
                    DataCell(Row(
                      children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.teal), onPressed: () => _addOrEditReadyProduct(p)),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteReadyProduct(p['id'] as int)),
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
  Future<void> deleteMaterial(int id) async {
    await http.delete(Uri.parse('http://localhost:8888/sewing/materials/$id'));
    await fetchMaterialsForType(selectedTypeId!);
  }

  Widget _buildRawMaterials() {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        // Sidebar: Types
        Container(
          width: 400, // Adjusted width to match SeasonReportSection
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
                                IconButton(icon: const Icon(Icons.edit, color: Colors.teal), onPressed: () => addOrEditType(current: t)),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('تأكيد الحذف'),
                                        content: const Text('هل أنت متأكد من حذف هذا النوع؟'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) await deleteType(t['id'] as int);
                                  },
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

        // Main: Materials table
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
                                  width: 900,
                                  child: Scrollbar(
                                    controller: _rawMaterialsV,
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      controller: _rawMaterialsV,
                                      child: DataTable(
                                        headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                                        columns: [
                                          const DataColumn(label: Text('الكود', style: TextStyle(color: Colors.white))),
                                          const DataColumn(label: Text('الكمية', style: TextStyle(color: Colors.white))),
                                          const DataColumn(label: Text('السعر', style: TextStyle(color: Colors.white))),
                                          ...specs.map((s) => DataColumn(label: Text(s['name'], style: const TextStyle(color: Colors.white)))),
                                          const DataColumn(label: Text('خيارات', style: TextStyle(color: Colors.white))),
                                        ],
                                        rows: materials.map((m) {
                                          final specVals = m['specs'] as List;
                                          return DataRow(cells: [
                                            DataCell(Text(m['code'] ?? '')),
                                            DataCell(Text(m['stock_quantity']?.toString() ?? '')),
                                            DataCell(Text(
                                              (m['last_unit_price'] != null && m['last_unit_price'] > 0)
                                                  ? m['last_unit_price'].toString()
                                                  : '—',
                                            )),
                                            ...specVals.map((s) => DataCell(Text(s['value'] ?? ''))),
                                            DataCell(Row(
                                              children: [
                                                IconButton(icon: const Icon(Icons.edit, color: Colors.teal), onPressed: () => addOrEditMaterial(material: m)),
                                                IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => deleteMaterial(m['id'] as int)),
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
// Widget _buildReadyProducts() {
//     if (isReadyProductsLoading) return const Center(child: CircularProgressIndicator());
//     if (readyProducts.isEmpty) return const Center(child: Text('لا توجد بيانات لعرضها'));

//     return Scrollbar(
//       controller: _readyProductsH,
//       thumbVisibility: true,
//       child: SingleChildScrollView(
//         controller: _readyProductsH,
//         scrollDirection: Axis.horizontal,
//         child: SizedBox(
//           width: 1050, // Increased width for the new column
//           child: Scrollbar(
//             controller: _readyProductsV,
//             thumbVisibility: true,
//             child: SingleChildScrollView(
//               controller: _readyProductsV,
//               child: DataTable(
//                 headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
//                 columns: const [
//                   DataColumn(label: Text('الموديل', style: TextStyle(color: Colors.white))),
//                   DataColumn(label: Text('المقاسات', style: TextStyle(color: Colors.white))),
//                   DataColumn(label: Text('عدد المقاسات', style: TextStyle(color: Colors.white))),
//                   DataColumn(label: Text('الكمية', style: TextStyle(color: Colors.white))),
//                   DataColumn(label: Text('السعر للوحدة', style: TextStyle(color: Colors.white))),
//                   DataColumn(label: Text('خيارات', style: TextStyle(color: Colors.white))),
//                 ],
//                 rows: readyProducts.map((p) {
//                   return DataRow(cells: [
//                     DataCell(Text(p['model_name'] ?? '')),
//                     DataCell(Text(p['sizes'] ?? '')),
//                     DataCell(Text('${p['nbr_of_sizes'] ?? 0}')),
//                     DataCell(Text('${p['quantity'] ?? ''}')),
//                     DataCell(Text('${(p['global_price'] ?? 0).toStringAsFixed(2)} دج')), // NEW
//                     DataCell(Row(
//                       children: [
//                         IconButton(icon: const Icon(Icons.edit, color: Colors.teal), onPressed: () => _addOrEditReadyProduct(p)),
//                         IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteReadyProduct(p['id'] as int)),
//                       ],
//                     )),
//                   ]);
//                 }).toList(),
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tabs
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
        // Content
        Expanded(child: selectedTab == 0 ? _buildReadyProducts() : _buildRawMaterials()),
      ],
    );
  }
}
