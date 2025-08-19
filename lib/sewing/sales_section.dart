import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'dart:io' as io;

/// =============================================================
/// Shared / Common Widgets & Helpers
/// =============================================================
class TabHeader extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;
  const TabHeader({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(tabs.length, (i) {
          final sel = selected == i;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ChoiceChip(
              label: Text(tabs[i]),
              selected: sel,
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                color: sel ? Colors.white : null,
                fontWeight: FontWeight.bold,
              ),
              onSelected: (_) => onChanged(i),
            ),
          );
        }),
      ),
    );
  }
}

class SidePanel extends StatelessWidget {
  final String title;
  final Widget? topFilters;
  final Widget list;
  const SidePanel({
    super.key,
    required this.title,
    this.topFilters,
    required this.list,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      color: Colors.grey[100],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 16),
                if (topFilters != null) topFilters!,
              ],
            ),
          ),
          Expanded(child: list),
        ],
      ),
    );
  }
}

Widget summaryCard(Map<String, Map<String, dynamic>> labels, String key, String value) {
  final cfg = labels[key]!;
  return Expanded(
    child: Card(
      color: cfg['lightColor'] as Color,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              cfg['label'] as String,
              style: TextStyle(
                color: cfg['darkColor'] as Color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: cfg['darkerColor'] as Color,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget costItem(String label, dynamic value, Color color, {bool isTotal = false}) {
  final numVal = (value ?? 0.0) is num ? (value ?? 0.0) as num : 0.0;
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
          '${numVal.toStringAsFixed(2)} دج',
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

String fmtDate(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '';
  try {
    final date = DateTime.parse(dateStr);
    return "${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}";
  } catch (e) {
    return dateStr.split('T').first;
  }
}

/// =============================================================
/// Main Section
/// =============================================================
class SewingSalesSection extends StatefulWidget {
  final String role;
  const SewingSalesSection({super.key, required this.role});

  @override
  State<SewingSalesSection> createState() => _SewingSalesSectionState();
}

class _SewingSalesSectionState extends State<SewingSalesSection> {
  int selectedTab = 2;

  String get baseUrl => '${globalServerUri.toString()}/sales';

  List<dynamic> allModels = [];
  List<dynamic> allClients = [];
  List<dynamic> allFactures = [];
  List<dynamic> allSeasons = [];
  Map<String, dynamic>? facturesSummary;

  int? selectedFactureId;
  int? selectedClientId;
  int? selectedModelId;
  int? selectedSeasonId;
  bool isLoading = false;

  final Map<String, Map<String, dynamic>> typeLabels = {
    'factures': {
      'label': 'اجمالي عدد الفواتير',
      'lightColor': Colors.blue[50],
      'darkColor': Colors.blue[800],
      'darkerColor': Colors.blue[900],
    },
    'income': {
      'label': 'اجمالي المدخول',
      'lightColor': Colors.green[50],
      'darkColor': Colors.green[800],
      'darkerColor': Colors.green[900],
    },
    'remaining': {
      'label': 'اجمالي المتبقي',
      'lightColor': Colors.orange[50],
      'darkColor': Colors.orange[800],
      'darkerColor': Colors.orange[900],
    },
    'profit': {
      'label': 'اجمالي الربح',
      'lightColor': Colors.purple[50],
      'darkColor': Colors.purple[800],
      'darkerColor': Colors.purple[900],
    },
  };

  late final String role;

  @override
  void initState() {
    super.initState();
    role = widget.role;
    _fetchAllData();
  }

  void _showSnackBar(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _fetchAllData() async {
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _fetchSeasons(),
        _fetchClients(),
        _fetchModels(),
        _fetchFactures(),
        _fetchFacturesSummary(),
      ]);
    } catch (e) {
      _showSnackBar('خطأ في تحميل البيانات: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }
// Excel-like cell builder (with optional right alignment & header styling)
pw.Widget _cell(String text, pw.TextStyle style, {bool header = false, bool alignRight = false}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    alignment: alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
    child: pw.Text(text, style: style),
  );
}

// Key–value row box used in totals
pw.Widget _kvr(String key, String value, pw.Font latinFont) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey700, width: 0.6)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(key, style: pw.TextStyle(font: latinFont, fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text(value, style: pw.TextStyle(font: latinFont, fontSize: 11)),
      ],
    ),
  );
}

// Capitalize first letter of a sentence in French text
String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

/// French amount in words: "… dinar(s) algérien(s) et … centime(s)"
String _toFrenchAmountWords(num amount) {
  final dinars = amount.floor();
  final cents = ((amount - dinars) * 100).round();

  String words = _intToFrenchWords(dinars);
  if (words.isEmpty) words = 'zéro';

  String res = '$words dinar${dinars > 1 ? 's' : ''} algérien${dinars > 1 ? 's' : ''}';
  if (cents > 0) {
    res += ' et ${_intToFrenchWords(cents)} centime${cents > 1 ? 's' : ''}';
  }
  return res;
}

/// Integer → French words (0..999,999,999)
String _intToFrenchWords(int n) {
  if (n == 0) return 'zéro';
  if (n < 0) return 'moins ${_intToFrenchWords(-n)}';

  final units = [
    'zéro','un','deux','trois','quatre','cinq','six','sept','huit','neuf',
    'dix','onze','douze','treize','quatorze','quinze','seize'
  ];

  String below100(int x) {
    if (x < 17) return units[x];
    if (x < 20) return 'dix-${units[x - 10]}';
    final tens = {20:'vingt', 30:'trente', 40:'quarante', 50:'cinquante', 60:'soixante'};
    if (x < 70) {
      final t = (x ~/ 10) * 10;
      final r = x % 10;
      if (r == 0) return tens[t]!;
      if (r == 1) return '${tens[t]} et un';
      return '${tens[t]}-${units[r]}';
    }
    if (x < 80) {
      final r = x - 60; // 70..79 => 60 + 10..19
      if (r == 11) return 'soixante et onze';
      return 'soixante-${below100(r)}'.replaceAll('dix-un', 'onze');
    }
    // 80..99
    final r = x - 80;
    if (r == 0) return 'quatre-vingts';
    final base = 'quatre-vingt';
    if (r == 1) return '$base-un'; // no "et"
    return '$base-${below100(r)}';
  }

  String below1000(int x) {
    if (x < 100) return below100(x);
    final h = x ~/ 100;
    final r = x % 100;
    if (h == 1) {
      if (r == 0) return 'cent';
      return 'cent ${below100(r)}';
    } else {
      // plural 'cents' only if nothing follows
      final centWord = r == 0 ? 'cents' : 'cent';
      if (r == 0) return '${units[h]} $centWord';
      return '${units[h]} $centWord ${below100(r)}';
    }
  }

  final parts = <String>[];
  final millions = n ~/ 1000000;
  final thousands = (n % 1000000) ~/ 1000;
  final rest = n % 1000;

  if (millions > 0) {
    parts.add(millions == 1 ? 'un million' : '${_intToFrenchWords(millions)} millions');
  }
  if (thousands > 0) {
    if (thousands == 1) {
      parts.add('mille');
    } else {
      parts.add('${below1000(thousands)} mille');
    }
  }
  if (rest > 0) {
    parts.add(below1000(rest));
  }

  return parts.join(' ');
}

  Future<void> _fetchSeasons() async {
    try {
      final resp = await http.get(Uri.parse('$baseUrl/seasons'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => allSeasons = data is List ? data : []);
      }
    } catch (_) {
      allSeasons = [];
    }
  }

  Future<void> _fetchFacturesSummary() async {
    try {
      final resp = await http.get(Uri.parse('$baseUrl/factures/summary'));
      if (resp.statusCode == 200) {
        setState(() => facturesSummary = jsonDecode(resp.body));
      }
    } catch (_) {
      facturesSummary = null;
    }
  }

  Future<void> _fetchFactures() async {
    String url = '$baseUrl/factures';
    if (selectedSeasonId != null && allSeasons.isNotEmpty) {
      url = '$baseUrl/factures/by_season/$selectedSeasonId';
    }
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as List;
      setState(() {
        allFactures = data;
        if (allFactures.isNotEmpty && selectedFactureId == null) {
          selectedFactureId = allFactures.first['id'] as int;
        } else if (selectedFactureId != null &&
            !allFactures.any((f) => f['id'] == selectedFactureId)) {
          selectedFactureId =
              allFactures.isNotEmpty ? allFactures.first['id'] as int : null;
        }
      });
    } else {
      throw Exception('Failed to load factures: ${resp.statusCode} - ${resp.body}');
    }
  }

  Future<void> _fetchClients() async {
    String url = '$baseUrl/clients';
    if (selectedSeasonId != null && allSeasons.isNotEmpty) {
      url = '$baseUrl/clients/by_season/$selectedSeasonId';
    }
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      setState(() => allClients = data is List ? data : []);
    } else {
      throw Exception('Failed to load clients: ${resp.statusCode}');
    }
  }

  Future<void> _fetchModels() async {
    String url = '$baseUrl/models';
    if (selectedSeasonId != null && allSeasons.isNotEmpty) {
      url = '$baseUrl/models/by_season/$selectedSeasonId';
    }
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      setState(() => allModels = data is List ? data : []);
    } else {
      throw Exception('Failed to load models: ${resp.statusCode}');
    }
  }

  dynamic get selectedFacture {
    if (selectedFactureId == null || allFactures.isEmpty) return null;
    return allFactures
        .firstWhere((f) => f['id'] == selectedFactureId, orElse: () => null);
  }

  Future<Map<String, dynamic>> _loadFactureDetail(int id) async {
    final resp = await http.get(Uri.parse('$baseUrl/factures/$id'));
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body);
    } else {
      throw Exception('Failed to load facture details: ${resp.statusCode} - ${resp.body}');
    }
  }

  Future<void> _onSeasonChanged(int? val) async {
    setState(() => selectedSeasonId = val);
    await Future.wait([
      _fetchFactures(),
      _fetchClients(),
      _fetchModels(),
      _fetchFacturesSummary(),
    ]);
  }

  void _showModelImagePopup(String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.network(
            '${globalServerUri.toString()}$imageUrl',
            fit: BoxFit.contain,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (ctx, err, st) => const Center(
              child: Icon(Icons.broken_image, size: 64),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addNewFacture() async {
  int? clientId;
  String payType = 'debt';
  double paidOnCreation = 0.0;
  final amountCtrl = TextEditingController();
  final List<Map<String, dynamic>> items = [];
  DateTime factureDate = DateTime.now();

  double getTotal() => items.fold<double>(
        0.0,
        (s, it) => s + (it['quantity'] as int) * (it['unit_price'] as double),
      );

  double getTotalProfit() => items.fold<double>(
        0.0,
        (s, it) =>
            s +
            (it['quantity'] as int) *
                ((it['unit_price'] as double) - (it['cost_price'] as double)),
      );

  Future<void> _addLineItem(StateSetter outerSetState) async {
    int? modelId;
    final qtyCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String? searchQuery;

    final List<Map<String, dynamic>> inStockModels = allModels
        .where((m) {
          final q = m['available_quantity'];
          final qty = q is num ? q.toInt() : int.tryParse(q.toString()) ?? 0;
          return qty > 0;
        })
        .cast<Map<String, dynamic>>()
        .toList();

    if (inStockModels.isEmpty) {
      _showSnackBar('لا توجد منتجات متاحة في المخزن حالياً', color: Colors.orange);
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, st) => AlertDialog(
          title: const Text('إضافة منتج للفاتورة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Autocomplete<Map<String, dynamic>>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    searchQuery = textEditingValue.text.toLowerCase();
                    return inStockModels.where((m) {
                      final name = m['name'].toString().toLowerCase();
                      return name.contains(searchQuery!);
                    });
                  },
                  displayStringForOption: (option) =>
                      '${option['name']} (متاح: ${option['available_quantity']}${role == "Admin" || role == "SuperAdmin" ? ", تكلفة: ${option['cost_price']}" : ""})',
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController textEditingController,
                    FocusNode focusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    return TextField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'اختر المنتج',
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (textEditingController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  textEditingController.clear();
                                  st(() => modelId = null);
                                },
                              ),
                            if (modelId != null)
                              IconButton(
                                icon: const Icon(Icons.image, color: Colors.blue),
                                onPressed: () {
                                  final selectedModel = inStockModels
                                      .firstWhere((m) => m['id'] == modelId);
                                  final imageUrl = selectedModel['image_url'] as String?;
                                  if (imageUrl != null && imageUrl.isNotEmpty) {
                                    _showModelImagePopup(imageUrl);
                                  } else {
                                    _showSnackBar('لا توجد صورة لهذا الموديل');
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                  onSelected: (Map<String, dynamic> option) {
                    st(() => modelId = option['id'] as int);
                    // Auto-fill the price with a suggested selling price (cost + margin)
                    if (role == "Admin" || role == "SuperAdmin") {
                      final costPrice = option['cost_price'] as double;
                      final suggestedPrice = (costPrice * 1.5).roundToDouble(); // 50% margin
                      priceCtrl.text = suggestedPrice.toString();
                    }
                  },
                  optionsViewBuilder: (
                    BuildContext context,
                    AutocompleteOnSelected<Map<String, dynamic>> onSelected,
                    Iterable<Map<String, dynamic>> options,
                  ) {
                    return Align(
                      alignment: Alignment.topRight,
                      child: Material(
                        elevation: 4.0,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final option = options.elementAt(index);
                              final imageUrl = option['image_url'] as String?;
                              return GestureDetector(
                                onTap: () => onSelected(option),
                                child: ListTile(
                                  leading: (imageUrl != null && imageUrl.isNotEmpty)
                                      ? GestureDetector(
                                          onTap: () => _showModelImagePopup(imageUrl),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: Image.network(
                                              '${globalServerUri.toString()}$imageUrl',
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
                                            ),
                                          ),
                                        )
                                      : const Icon(Icons.image, size: 40, color: Colors.grey),
                                  title: Text(
                                    '${option['name']} (متاح: ${option['available_quantity']}${role == "Admin" || role == "SuperAdmin" ? ", تكلفة: ${option['cost_price']}" : ""})',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الكمية',
                    helperText: 'أدخل الكمية المطلوبة',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    // Real-time validation
                    final qty = int.tryParse(value) ?? 0;
                    if (modelId != null && qty > 0) {
                      final selectedModel = inStockModels.firstWhere((m) => m['id'] == modelId);
                      final availableQty = selectedModel['available_quantity'] is int
                          ? selectedModel['available_quantity'] as int
                          : int.tryParse(selectedModel['available_quantity'].toString()) ?? 0;
                      
                      if (qty > availableQty) {
                        st(() {}); // Trigger rebuild to show error
                      }
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'سعر البيع',
                    helperText: 'سعر البيع للقطعة الواحدة',
                    suffixText: 'دج',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                // Show available quantity warning
                if (modelId != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'الكمية المتاحة: ${inStockModels.firstWhere((m) => m['id'] == modelId)['available_quantity']}',
                          style: const TextStyle(color: Colors.blue, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final q = int.tryParse(qtyCtrl.text) ?? 0;
                final p = double.tryParse(priceCtrl.text) ?? 0.0;

                if (modelId == null) {
                  _showSnackBar('يرجى اختيار المنتج');
                  return;
                }
                if (q <= 0) {
                  _showSnackBar('يرجى إدخال كمية صحيحة');
                  return;
                }
                if (p <= 0) {
                  _showSnackBar('يرجى إدخال سعر صحيح');
                  return;
                }

                final prod = inStockModels.firstWhere((m) => m['id'] == modelId);
                final availableQty = prod['available_quantity'] is int
                    ? prod['available_quantity'] as int
                    : int.tryParse(prod['available_quantity'].toString()) ?? 0;

                if (q > availableQty) {
                  _showSnackBar(
                      'الكمية أكبر من الموجود في المخزن (متاح: $availableQty)');
                  return;
                }

                final existingIndex =
                    items.indexWhere((item) => item['model_id'] == modelId);
                if (existingIndex != -1) {
                  // Update existing item
                  items[existingIndex]['quantity'] = q;
                  items[existingIndex]['unit_price'] = p;
                  _showSnackBar('تم تحديث المنتج في الفاتورة', color: Colors.blue);
                } else {
                  // Add new item
                  items.add({
                    'model_id': modelId,
                    'model_name': prod['name'],
                    'quantity': q,
                    'unit_price': p,
                    'available_quantity': availableQty,
                    'cost_price': prod['cost_price'],
                    'image_url': prod['image_url'],
                  });
                  _showSnackBar('تم إضافة المنتج للفاتورة', color: Colors.green);
                }

                outerSetState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editLineItem(int index, StateSetter outerSetState) async {
    final item = items[index];
    final qtyCtrl = TextEditingController(text: item['quantity'].toString());
    final priceCtrl = TextEditingController(text: item['unit_price'].toString());

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تعديل ${item['model_name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              decoration: InputDecoration(
                labelText: 'الكمية',
                helperText: 'الحد الأقصى: ${item['available_quantity']}',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(
                labelText: 'سعر البيع',
                suffixText: 'دج',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final newQty = int.tryParse(qtyCtrl.text) ?? 0;
              final newPrice = double.tryParse(priceCtrl.text) ?? 0.0;

              if (newQty <= 0 || newPrice <= 0) {
                _showSnackBar('يرجى إدخال قيم صحيحة');
                return;
              }

              if (newQty > item['available_quantity']) {
                _showSnackBar('الكمية أكبر من المتاح');
                return;
              }

              items[index]['quantity'] = newQty;
              items[index]['unit_price'] = newPrice;
              outerSetState(() {});
              Navigator.pop(context);
              _showSnackBar('تم تحديث المنتج', color: Colors.green);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, dialogSetState) {
        String? clientError;
        String? productsError;
        return AlertDialog(
          title: const Text('إضافة فاتورة جديدة'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 600,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Date selection card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Text(
                            'تاريخ الفاتورة: ${factureDate.toLocal().toString().split(' ')[0]}',
                          ),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: factureDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                dialogSetState(() => factureDate = picked);
                              }
                            },
                            child: const Text('تغيير التاريخ'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Client selection
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'اختر العميل',
                      border: OutlineInputBorder(),
                    ),
                    value: clientId,
                    items: allClients.map((c) {
                      return DropdownMenuItem(
                        value: c['id'] as int,
                        child: Text('${c['full_name']} - ${c['phone'] ?? ''}'),
                      );
                    }).toList(),
                    onChanged: (v) => dialogSetState(() => clientId = v),
                  ),
                  if (clientError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        clientError,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 16),
                  
                  // Products section
                  Card(
                    color: Colors.grey[50],
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'المنتجات (${items.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('إضافة منتج'),
                                onPressed: () => _addLineItem(dialogSetState),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          if (productsError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                productsError,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 8),
                          
                          if (items.isNotEmpty) ...[
                            const Divider(),
                            // Summary row
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'إجمالي المنتجات: ${items.fold<int>(0, (sum, item) => sum + (item['quantity'] as int))}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'الإجمالي: ${getTotal().toStringAsFixed(2)} دج',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (role == "Admin" || role == "SuperAdmin")
                                        Text(
                                          'إجمالي الربح: ${getTotalProfit().toStringAsFixed(2)} دج',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.purple,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            
                            // Products list
                            ...items.asMap().entries.map((e) {
                              final idx = e.key;
                              final it = e.value;
                              final profit = (it['unit_price'] - it['cost_price']) * it['quantity'];
                              final imageUrl = it['image_url'] as String?;
                              final lineTotal = (it['quantity'] * it['unit_price']);
                              
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: (imageUrl != null && imageUrl.isNotEmpty)
                                      ? GestureDetector(
                                          onTap: () => _showModelImagePopup(imageUrl),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: Image.network(
                                              '${globalServerUri.toString()}$imageUrl',
                                              width: 50,
                                              height: 50,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
                                            ),
                                          ),
                                        )
                                      : const Icon(Icons.image, size: 50, color: Colors.grey),
                                  title: Text(
                                    it['model_name'],
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('الكمية: ${it['quantity']} × ${it['unit_price']} دج'),
                                      Text(
                                        'الإجمالي: ${lineTotal.toStringAsFixed(2)} دج',
                                        style: TextStyle(
                                          color: Colors.green[700],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (role == "Admin" || role == "SuperAdmin")
                                        Text(
                                          'الربح: ${profit.toStringAsFixed(2)} دج',
                                          style: TextStyle(color: Colors.purple[700]),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.blue),
                                        onPressed: () => _editLineItem(idx, dialogSetState),
                                        tooltip: 'تعديل',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () {
                                          dialogSetState(() => items.removeAt(idx));
                                          _showSnackBar('تم حذف المنتج', color: Colors.orange);
                                        },
                                        tooltip: 'حذف',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  Icon(Icons.shopping_cart_outlined, 
                                       size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 8),
                                  Text(
                                    'لم يتم إضافة أي منتجات بعد',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('إضافة المنتج الأول'),
                                    onPressed: () => _addLineItem(dialogSetState),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Payment type selection
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'نوع الدفع',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          ListTile(
                            title: const Text('بيع بالدين'),
                            leading: Radio<String>(
                              value: 'debt',
                              groupValue: payType,
                              onChanged: (v) => dialogSetState(() => payType = v!),
                            ),
                          ),
                          ListTile(
                            title: const Text('بيع نقدي (دفع جزئي أو كامل)'),
                            leading: Radio<String>(
                              value: 'cash',
                              groupValue: payType,
                              onChanged: (v) => dialogSetState(() => payType = v!),
                            ),
                          ),
                          if (payType == 'cash') ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: amountCtrl,
                              decoration: InputDecoration(
                                labelText: 'المبلغ المدفوع',
                                helperText: 'الحد الأقصى: ${getTotal().toStringAsFixed(2)} دج',
                                suffixText: 'دج',
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (v) {
                                final amount = double.tryParse(v) ?? 0.0;
                                final total = getTotal();
                                if (amount > total) {
                                  amountCtrl.text = total.toStringAsFixed(2);
                                  paidOnCreation = total;
                                } else {
                                  paidOnCreation = amount;
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
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
                bool hasError = false;
                dialogSetState(() {
                  clientError = clientId == null ? 'يرجى اختيار العميل' : null;
                  productsError = items.isEmpty ? 'يرجى إضافة منتج واحد على الأقل' : null;
                  if (clientError != null || productsError != null) {
                    hasError = true;
                  }
                });
                if (hasError) return;

                final total = getTotal();
                if (total <= 0) {
                  _showSnackBar('إجمالي الفاتورة يجب أن يكون أكبر من صفر');
                  return;
                }
                if (payType == 'cash' && paidOnCreation > total) {
                  _showSnackBar('الدفعة الأولى لا يمكن أن تكون أكبر من إجمالي الفاتورة');
                  return;
                }

                final payload = {
                  'client_id': clientId,
                  'total_amount': total,
                  'amount_paid_on_creation': payType == 'cash' ? paidOnCreation : 0.0,
                  'facture_date': factureDate.toIso8601String().split('T')[0],
                  'items': items
                      .map((it) => {
                            'model_id': it['model_id'],
                            'color': null,
                            'quantity': it['quantity'],
                            'unit_price': it['unit_price'],
                          })
                      .toList(),
                };

                try {
                  final resp = await http.post(
                    Uri.parse('$baseUrl/factures'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  );
                  if (resp.statusCode == 201) {
                    _showSnackBar('تم إضافة الفاتورة بنجاح!', color: Colors.green);
                    Navigator.pop(ctx);
                    await _fetchFactures();
                    await _fetchFacturesSummary();
                  } else {
                    final error = jsonDecode(resp.body);
                    _showSnackBar('فشل إضافة الفاتورة: ${error['error'] ?? 'خطأ غير معروف'}');
                  }
                } catch (e) {
                  _showSnackBar('خطأ في الاتصال: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text(
                'حفظ الفاتورة (${getTotal().toStringAsFixed(2)} دج)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    ),
  );
}


  Future<void> _deleteFacture(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الفاتورة'),
        content: Text('هل أنت متأكد من حذف الفاتورة رقم "${f['id']}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        final resp = await http.delete(Uri.parse('$baseUrl/factures/${f['id']}'));
        if (resp.statusCode == 200) {
          _showSnackBar('تم حذف الفاتورة بنجاح', color: Colors.green);
          await _fetchFactures();
          await _fetchFacturesSummary();
        } else {
          final error = jsonDecode(resp.body);
          _showSnackBar('فشل حذف الفاتورة: ${error['error'] ?? 'خطأ غير معروف'}');
        }
      } catch (e) {
        _showSnackBar('خطأ في الاتصال: $e');
      }
    }
  }

  Future<void> _addPayment(Map<String, dynamic> facture) async {
    final amountCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('إضافة دفعة لفاتورة رقم ${facture['id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              decoration: InputDecoration(
                labelText:
                    'المبلغ (الحد الأقصى: ${facture['remaining_amount'].toStringAsFixed(2)} دج)',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              final amount = double.tryParse(amountCtrl.text) ?? 0.0;
              if (amount <= 0) {
                _showSnackBar('يرجى إدخال مبلغ صحيح');
                return;
              }
              if (amount > facture['remaining_amount']) {
                _showSnackBar('المبلغ أكبر من المتبقي');
                return;
              }

              try {
                final resp = await http.post(
                  Uri.parse('$baseUrl/factures/${facture['id']}/pay'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'amount': amount}),
                );
                if (resp.statusCode == 200) {
                  _showSnackBar('تم إضافة الدفعة بنجاح', color: Colors.green);
                  Navigator.pop(context);
                  await _fetchFactures();
                  await _fetchFacturesSummary();
                  setState(() {});
                } else {
                  final error = jsonDecode(resp.body);
                  _showSnackBar(
                      'فشل إضافة الدفعة: ${error['error'] ?? 'خطأ غير معروف'}');
                }
              } catch (e) {
                _showSnackBar('خطأ في الاتصال: $e');
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
Future<void> _printFacture(Map<String, dynamic> facture) async {
  // ========= Fonts =========
  final arabicData = await rootBundle.load('assets/fonts/NotoSansArabic_Condensed-Black.ttf');
  final latinData  = await rootBundle.load('assets/fonts/Roboto_Condensed-Black.ttf');
  final arabicFont = pw.Font.ttf(arabicData);
  final latinFont  = pw.Font.ttf(latinData);

  // ========= Helpers =========
  String _s(dynamic v) => v == null ? '' : v.toString();

  num _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  // Western digits, show 0 decimals if integer, else 2 decimals
  String _dz(num v) {
    final hasFraction = (v % 1) != 0;
    final s = hasFraction ? v.toStringAsFixed(2) : v.toStringAsFixed(0);
    return '$s دج';
  }

  List<List<T>> _chunk<T>(List<T> list, int size) {
    if (list.isEmpty) return const [];
    final out = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      out.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return out;
  }

  // Simple integer→Arabic words (enough for invoice text line)
  String _intToArabicWords(int n) {
    if (n == 0) return 'صفر';
    if (n < 0) return 'سالب ${_intToArabicWords(-n)}';

    const units = [
      'صفر','واحد','اثنان','ثلاثة','أربعة','خمسة','ستة','سبعة','ثمانية','تسعة',
      'عشرة','أحد عشر','اثنا عشر','ثلاثة عشر','أربعة عشر','خمسة عشر','ستة عشر',
      'سبعة عشر','ثمانية عشر','تسعة عشر'
    ];
    const tensMap = {20:'عشرون',30:'ثلاثون',40:'أربعون',50:'خمسون',60:'ستون',70:'سبعون',80:'ثمانون',90:'تسعون'};
    const hundredsMap = {
      1:'مائة',2:'مائتان',3:'ثلاثمائة',4:'أربعمائة',5:'خمسمائة',
      6:'ستمائة',7:'سبعمائة',8:'ثمانمائة',9:'تسعمائة'
    };

    String below100(int x) {
      if (x < 20) return units[x];
      final t = (x ~/ 10) * 10;
      final r = x % 10;
      if (r == 0) return tensMap[t]!;
      return '${units[r]} و ${tensMap[t]}';
    }

    String below1000(int x) {
      final h = x ~/ 100;
      final r = x % 100;
      String res = '';
      if (h > 0) res = hundredsMap[h]!;
      if (r > 0) {
        if (res.isNotEmpty) res += ' و ';
        res += below100(r);
      }
      return res.isNotEmpty ? res : 'صفر';
    }

    final millions = n ~/ 1000000;
    final thousands = (n % 1000000) ~/ 1000;
    final rest = n % 1000;

    final parts = <String>[];

    if (millions > 0) {
      if (millions == 1) parts.add('مليون');
      else if (millions == 2) parts.add('مليونان');
      else if (millions <= 10) parts.add('${below1000(millions)} ملايين');
      else parts.add('${below1000(millions)} مليون');
    }
    if (thousands > 0) {
      if (thousands == 1) parts.add('ألف');
      else if (thousands == 2) parts.add('ألفان');
      else if (thousands <= 10) parts.add('${below1000(thousands)} آلاف');
      else parts.add('${below1000(thousands)} ألف');
    }
    if (rest > 0) parts.add(below1000(rest));

    return parts.join(' و ');
  }

  String _currencyForm(int n, String singular, String dual, String plural) {
    if (n == 1) return singular;
    if (n == 2) return dual;
    return plural;
  }

  String _toArabicAmountWords(num amount) {
    final dinars = amount.floor();
    final cents  = ((amount - dinars) * 100).round();

    final wordsDinars = _intToArabicWords(dinars);
    final formDinars  = _currencyForm(dinars, 'دينار جزائري', 'ديناران جزائريان', 'دنانير جزائرية');

    String res = '$wordsDinars $formDinars';
    if (cents > 0) {
      final wordsCents = _intToArabicWords(cents);
      final formCents  = _currencyForm(cents, 'سنتيم', 'سنتيمان', 'سنتيمات');
      res += ' و $wordsCents $formCents';
    }
    return res;
  }

  pw.Widget _kvRowAr(pw.Font ar, pw.Font lat, String key, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey700, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(key, style: pw.TextStyle(font: ar, fontSize: 11, fontFallback: [lat])),
          pw.Text(value, style: pw.TextStyle(font: ar, fontSize: 11, fontFallback: [lat])),
        ],
      ),
    );
  }

  // ========= Facture data =========
  final items      = (facture['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final total      = _num(facture['total_amount']);     // this invoice total
  final totalPaid  = _num(facture['total_paid']);       // paid on this invoice
  final remaining  = _num(facture['remaining_amount']); // remaining on this invoice

  final clientName    = _s(facture['client_name']);
  final clientAddress = _s(facture['client_address']);
  final clientPhone   = _s(facture['client_phone']);
  final fDateStr      = facture['facture_date']?.toString();

  // ========= clientId detection =========
  int? clientId;
  if (facture.containsKey('client_id')) {
    clientId = _num(facture['client_id']).toInt();
  }
  clientId ??= (() {
    try {
      final base = allFactures.firstWhere(
        (f) => _num(f['id']).toInt() == _num(facture['id']).toInt(),
        orElse: () => null,
      );
      return base == null ? null : _num(base['client_id']).toInt();
    } catch (_) { return null; }
  })();

  // ========= Global remaining (for the client) =========
  num globalRemaining = remaining; // fallback
  try {
    if (clientId != null) {
      final resp = await http.get(Uri.parse('${globalServerUri.toString()}/sales/clients/$clientId/account'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final summary = (data['summary'] as Map?) ?? {};
        globalRemaining = _num(summary['remaining']);
      }
    }
  } catch (_) {/* keep fallback */}

  final oldDebtNow = (globalRemaining - remaining) > 0 ? (globalRemaining - remaining) : 0;
  final grandTotal = oldDebtNow + total;
  final totalWordsAr  = _toArabicAmountWords(total);

  // ========= Styles =========
  final headerTitle   = pw.TextStyle(font: arabicFont, fontSize: 18, fontWeight: pw.FontWeight.bold, fontFallback: [latinFont]);
  final headerBrand   = pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold, fontFallback: [latinFont]);
  final headerAddr    = pw.TextStyle(font: arabicFont, fontSize: 10, fontFallback: [latinFont]);
  final h1            = pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold, fontFallback: [latinFont]);
  final label         = pw.TextStyle(font: arabicFont, fontSize: 11, fontFallback: [latinFont]);
  final labelB        = pw.TextStyle(font: arabicFont, fontSize: 11, fontWeight: pw.FontWeight.bold, fontFallback: [latinFont]);
  final thStyle       = pw.TextStyle(font: arabicFont, fontSize: 11, fontWeight: pw.FontWeight.bold, fontFallback: [latinFont]);
  final tdStyle       = pw.TextStyle(font: arabicFont, fontSize: 10, fontFallback: [latinFont]);

  final pdf = pw.Document();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,   // edge-to-edge header
      build: (ctx) {
        final body = <pw.Widget>[];

        // ======= Company header (RTL, full width) =======
        body.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1)),
            ),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('الإنتاج الصناعي للملابس', style: headerTitle),
                  pw.SizedBox(height: 2),
                  pw.Text('HALA MOD', style: headerBrand),
                  pw.SizedBox(height: 4),
                  pw.Text('العنوان: LOCAL N°03 SEC 05 GRP N°21 OULED MOUSSA BOUMERDES', style: headerAddr),
                ],
              ),
            ),
          ),
        );

        // ======= Content =======
        body.add(
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(24, 10, 24, 24),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Invoice id & date
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('فاتورة رقم ${_s(facture['id'])}', style: h1),
                      pw.Text('التاريخ: ${fDateStr == null ? '' : fmtDate(fDateStr)}', style: labelB),
                    ],
                  ),
                  pw.SizedBox(height: 8),

                  // Client card
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Row(
                          children: [
                            pw.Expanded(
                              flex: 2,
                              child: pw.Container(
                                padding: const pw.EdgeInsets.all(8),
                                decoration: pw.BoxDecoration(
                                  border: pw.Border(
                                    left: pw.BorderSide(color: PdfColors.grey700, width: 0.8),
                                  ),
                                ),
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text('العميل', style: labelB),
                                    pw.SizedBox(height: 2),
                                    pw.Text(clientName, style: label),
                                  ],
                                ),
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Container(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text('الهاتف', style: labelB),
                                    pw.SizedBox(height: 2),
                                    pw.Text(clientPhone, style: label),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        pw.Container(height: 0.8, color: PdfColors.grey700),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('العنوان', style: labelB),
                              pw.SizedBox(height: 2),
                              pw.Text(clientAddress, style: label),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 12),

                  // Items table (reversed columns): amount | unit | qty | product
                  () {
                    final headers = ['المبلغ', 'سعر الوحدة', 'الكمية', 'المنتج'];
                    final rows = (items).map((it) {
                      final q  = _num(it['quantity']);
                      final pu = _num(it['unit_price']);
                      final mt = _num(it['line_total']) == 0 ? q * pu : _num(it['line_total']);
                      return [
                        _dz(mt),
                        _dz(pu),
                        q % 1 == 0 ? q.toInt().toString() : q.toString(),
                        _s(it['model_name'] ?? ''),
                      ];
                    }).toList();

                    const rowsPerChunk = 35;
                    final chunks = _chunk(rows, rowsPerChunk);
                    final widgets = <pw.Widget>[];

                    if (chunks.isEmpty) {
                      widgets.add(
                        pw.Table.fromTextArray(
                          context: ctx,
                          headers: headers,
                          data: const <List<String>>[],
                          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                          border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
                          headerStyle: thStyle,
                          cellStyle: tdStyle,
                          columnWidths: const {
                            0: pw.FlexColumnWidth(3), // amount
                            1: pw.FlexColumnWidth(3), // unit
                            2: pw.FlexColumnWidth(2), // qty
                            3: pw.FlexColumnWidth(6), // product
                          },
                          cellAlignments: const {
                            0: pw.Alignment.centerRight,
                            1: pw.Alignment.centerRight,
                            2: pw.Alignment.centerRight,
                            3: pw.Alignment.centerRight,
                          },
                        ),
                      );
                    } else {
                      for (var i = 0; i < chunks.length; i++) {
                        widgets.add(
                          pw.Table.fromTextArray(
                            context: ctx,
                            headers: headers,
                            data: chunks[i],
                            tableWidth: pw.TableWidth.max,
                            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
                            headerStyle: thStyle,
                            cellStyle: tdStyle,
                            columnWidths: const {
                              0: pw.FlexColumnWidth(3),
                              1: pw.FlexColumnWidth(3),
                              2: pw.FlexColumnWidth(2),
                              3: pw.FlexColumnWidth(6),
                            },
                            cellAlignments: const {
                              0: pw.Alignment.centerRight,
                              1: pw.Alignment.centerRight,
                              2: pw.Alignment.centerRight,
                              3: pw.Alignment.centerRight,
                            },
                          ),
                        );
                        if (i != chunks.length - 1) widgets.add(pw.SizedBox(height: 6));
                      }
                    }
                    return pw.Column(children: widgets);
                  }(),

                  pw.SizedBox(height: 10),

                  // Totals box (5 lines)
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Container(
                      width: 320,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey700, width: 0.6),
                      ),
                      child: pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          _kvRowAr(arabicFont, latinFont, 'إجمالي الفاتورة', _dz(total)),
                          _kvRowAr(arabicFont, latinFont, 'الإجمالي',           _dz(grandTotal)),
                          _kvRowAr(arabicFont, latinFont, 'المدفوع',            _dz(totalPaid)),
                          _kvRowAr(arabicFont, latinFont, 'المتبقي',            _dz(remaining)),
                          _kvRowAr(arabicFont, latinFont, 'المتبقي الإجمالي',   _dz(globalRemaining)),
                        ],
                      ),
                    ),
                  ),

                  pw.SizedBox(height: 10),

                  // Amount in words (Arabic words + Latin-digit numeric)
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey700, width: 0.6),
                      color: PdfColors.grey200,
                    ),
                    child: pw.Text(
                      'هذه الفاتورة مقفلة على مبلغ: ${_toArabicAmountWords(total)} (${_dz(total)}).',
                      style: label,
                    ),
                  ),

                  // No signatures / No RC-ART-NIF per your request
                ],
              ),
            ),
          ),
        );

        return body;
      },
    ),
  );

  // ========= Save =========
  final bytes = await pdf.save();
  final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'اختر مجلد الحفظ');
  if (dir != null) {
    final path = '$dir/فاتورة_${_s(facture['id'])}.pdf';
    await io.File(path).writeAsBytes(bytes);
  }
}





  @override
  Widget build(BuildContext context) {
    Widget content;

    if (selectedTab == 2) {
      content = Column(
        children: [
          if (facturesSummary != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  summaryCard(typeLabels, 'factures', '${facturesSummary!['total_factures']}'),
                  const SizedBox(width: 8),
                  summaryCard(
                      typeLabels,
                      'income',
                      '${(facturesSummary!['total_income'] as num?)?.toStringAsFixed(2) ?? '0'} دج'),
                  const SizedBox(width: 8),
                  summaryCard(
                      typeLabels,
                      'remaining',
                      '${(facturesSummary!['total_remaining'] as num?)?.toStringAsFixed(2) ?? '0'} دج'),
                  const SizedBox(width: 8),
                  if (role == "Admin" || role == "SuperAdmin")
                    summaryCard(
                        typeLabels,
                        'profit',
                        '${(facturesSummary!['total_profit'] as num?)?.toStringAsFixed(2) ?? '0'} دج'),
                ],
              ),
            ),
          Expanded(
            child: Row(
              children: [
                SidePanel(
                  title: 'فواتير المبيعات',
                  topFilters: Column(
                    children: [
                      if (allSeasons.isNotEmpty)
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
                                ...allSeasons.map<DropdownMenuItem<int?>>((season) {
                                  return DropdownMenuItem<int?>(
                                    value: season['id'] as int,
                                    child: Text(season['name'] as String),
                                  );
                                }).toList(),
                              ],
                              onChanged: _onSeasonChanged,
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text('فاتورة جديدة',
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[700],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: allModels.isNotEmpty && allClients.isNotEmpty
                              ? _addNewFacture
                              : null,
                        ),
                      ),
                    ],
                  ),
                  list: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : allFactures.isEmpty
                          ? const Center(child: Text('لا توجد فواتير'))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              itemCount: allFactures.length,
                              itemBuilder: (_, i) {
                                final f = allFactures[i];
                                final isSel = f['id'] == selectedFactureId;
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  elevation: isSel ? 4 : 1,
                                  color: isSel ? Colors.grey[100] : Colors.white,
                                  child: ListTile(
                                    selected: isSel,
                                    title: Text(
                                      'فاتورة رقم ${f['id']}',
                                      style: TextStyle(
                                        fontWeight: isSel
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('تاريخ: ${fmtDate(f['facture_date'])}'),
                                        Text('العميل: ${f['client_name'] ?? 'غير محدد'}',
                                            style: TextStyle(color: Colors.teal[700])),
                                        Text(
                                            'الإجمالي: ${f['total_amount']?.toStringAsFixed(2) ?? '0'} دج'),
                                        Text(
                                          'المتبقي: ${f['remaining_amount']?.toStringAsFixed(2) ?? '0'} دج',
                                          style: TextStyle(color: Colors.red[700]),
                                        ),
                                      ],
                                    ),
                                    onTap: () => setState(
                                        () => selectedFactureId = f['id']),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteFacture(f),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selectedFacture == null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'اختر فاتورة من القائمة الجانبية',
                                style: TextStyle(
                                    fontSize: 18, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: FutureBuilder<Map<String, dynamic>>(
                            future: _loadFactureDetail(selectedFactureId!),
                            builder: (ctx, snap) {
                              if (snap.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              if (snap.hasError) {
                                return Center(child: Text('خطأ: ${snap.error}'));
                              }
                              final d = snap.data!;
                              return SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'تفاصيل فاتورة رقم ${d['id']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.indigo[800],
                                          ),
                                    ),
                                    const SizedBox(height: 24),
                                    Card(
                                      color: Colors.blue[50],
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'معلومات الفاتورة',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue[800],
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                const Icon(Icons.calendar_today,
                                                    size: 20, color: Colors.blue),
                                                const SizedBox(width: 8),
                                                Text(
                                                    'التاريخ: ${fmtDate(d['facture_date'])}'),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(Icons.person,
                                                    size: 20, color: Colors.blue),
                                                const SizedBox(width: 8),
                                                Text('العميل: ${d['client_name']}'),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(Icons.phone,
                                                    size: 20, color: Colors.blue),
                                                const SizedBox(width: 8),
                                                Text('الهاتف: ${d['client_phone']}'),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(Icons.location_on,
                                                    size: 20, color: Colors.blue),
                                                const SizedBox(width: 8),
                                                Text('العنوان: ${d['client_address']}'),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Card(
                                      color: Colors.green[50],
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'معلومات الدفع',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green[800],
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: costItem('الإجمالي',
                                                      d['total_amount'], Colors.green[700]!),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: costItem('المدفوع',
                                                      d['total_paid'], Colors.blue[700]!),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: costItem('المتبقي',
                                                      d['remaining_amount'],
                                                      Colors.orange[700]!),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Container(
                                                    padding: const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: d['remaining_amount'] <= 0
                                                          ? Colors.green.withOpacity(0.1)
                                                          : Colors.orange.withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(8),
                                                      border: Border.all(
                                                          color: (d['remaining_amount'] <= 0
                                                                  ? Colors.green
                                                                  : Colors.orange)
                                                              .withOpacity(0.3)),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          'الحالة',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: d['remaining_amount'] <= 0
                                                                ? Colors.green[700]
                                                                : Colors.orange[700],
                                                          ),
                                                        ),
                                                        Text(
                                                          d['remaining_amount'] <= 0
                                                              ? 'مدفوع بالكامل'
                                                              : d['total_paid'] > 0
                                                                  ? 'مدفوع جزئياً'
                                                                  : 'غير مدفوع',
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.bold,
                                                            color: d['remaining_amount'] <= 0
                                                                ? Colors.green[700]
                                                                : Colors.orange[700],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'تفاصيل المنتجات',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey[800],
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: DataTable(
                                                headingRowColor:
                                                    MaterialStateProperty.all(
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .primary),
                                                headingTextStyle:
                                                    const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                columns: [
                                                  const DataColumn(label: Text('صورة')),
                                                  const DataColumn(label: Text('المنتج')),
                                                  const DataColumn(label: Text('الكمية')),
                                                  const DataColumn(label: Text('سعر البيع')),
                                                  if (role == 'Admin' || role == 'SuperAdmin')
                                                    const DataColumn(label: Text('ربح/قطعة')),
                                                  if (role == 'Admin' || role == 'SuperAdmin')
                                                    const DataColumn(label: Text('إجمالي الربح')),
                                                  const DataColumn(label: Text('الإجمالي')),
                                                ],
                                                rows: (d['items'] as List<dynamic>).map<DataRow>((it) {
                                                  final totalProfit = (it['profit_per_piece'] ?? 0) * (it['quantity'] ?? 0);
                                                  final imageUrl = it['image_url'] as String?;
                                  leading: (imageUrl != null && imageUrl.isNotEmpty);

                                                  return DataRow(cells: [
                                                    
                                                    DataCell(
                      GestureDetector(
                                            onTap: () => _showModelImagePopup(it['image_url']),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: Image.network(
                                                '${globalServerUri.toString()}$imageUrl',
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
                                              ),
                                            ),
                                          )
                                          
                    ),
                                                    DataCell(Text(it['model_name'] ?? '')),
                                                    DataCell(Text('${it['quantity'] ?? 0}')),
                                                    DataCell(Text(
                                                        '${(it['unit_price'] as num?)?.toStringAsFixed(2) ?? '0'} دج')),
                                                    if (role == 'Admin' || role == 'SuperAdmin')
                                                      DataCell(Text(
                                                          '${(it['profit_per_piece'] as num?)?.toStringAsFixed(2) ?? '0'} دج')),
                                                    if (role == 'Admin' || role == 'SuperAdmin')
                                                      DataCell(Text(
                                                          '${(totalProfit as num?)?.toStringAsFixed(2) ?? '0'} دج')),
                                                    DataCell(Text(
                                                        '${(it['line_total'] as num?)?.toStringAsFixed(2) ?? '0'} دج')),
                                                  ]);
                                                }).toList(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'الدفعات',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey[800],
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            if (d['amount_paid_on_creation'] != null &&
                                                d['amount_paid_on_creation'] > 0)
                                              ListTile(
                                                leading: const Icon(Icons.payment,
                                                    color: Colors.green),
                                                title: Text(
                                                    '${d['amount_paid_on_creation']?.toStringAsFixed(2) ?? '0'} دج'),
                                                subtitle: Text(
                                                    'دفعة عند الإنشاء - تاريخ: ${fmtDate(d['facture_date'])}'),
                                              ),
                                            if (d['payments'] != null &&
                                                (d['payments'] as List).isNotEmpty)
                                              ...((d['payments'] as List)
                                                  .map<Widget>((p) => ListTile(
                                                        leading:
                                                            const Icon(Icons.payment),
                                                        title: Text(
                                                            '${p['amount_paid']?.toStringAsFixed(2) ?? '0'} دج'),
                                                        subtitle: Text(
                                                            'تاريخ: ${fmtDate(p['payment_date'])}'),
                                                      )))
                                                  .toList()
                                            else if (d['amount_paid_on_creation'] ==
                                                    null ||
                                                d['amount_paid_on_creation'] == 0)
                                              const Text('لا توجد دفعات'),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (d['returns'] != null && (d['returns'] as List).isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'المرتجعات',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey[800],
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              SingleChildScrollView(
                                                scrollDirection: Axis.horizontal,
                                                child: DataTable(
                                                  headingRowColor:
                                                      MaterialStateProperty.all(
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .primary),
                                                  headingTextStyle:
                                                      const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold),
                                                  columns: const [
                                                    DataColumn(label: Text('المنتج')),
                                                    DataColumn(label: Text('الكمية')),
                                                    DataColumn(label: Text('تاريخ الإرجاع')),
                                                    DataColumn(label: Text('ملاحظات')),
                                                  ],
                                                  rows: (d['returns'] as List<dynamic>)
                                                      .map<DataRow>((r) => DataRow(cells: [
                                                            DataCell(Text(
                                                                r['model_name'] ?? '')),
                                                            DataCell(
                                                                Text('${r['quantity'] ?? 0}')),
                                                            DataCell(Text(
                                                                fmtDate(r['return_date']))),
                                                            DataCell(
                                                                Text(r['notes'] ?? '')),
                                                          ]))
                                                      .toList(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.print),
                                          label: const Text('طباعة الفاتورة'),
                                          onPressed: () => _printFacture(d),
                                        ),
                                        const SizedBox(width: 16),
                                        if (d['remaining_amount'] > 0)
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.payment),
                                            label: const Text('إضافة دفعة'),
                                            onPressed: () => _addPayment(d),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      );
    } else if (selectedTab == 0) {
      content = Row(
        children: [
          SidePanel(
            title: 'الموديلات',
            topFilters: allSeasons.isNotEmpty
                ? DropdownButtonFormField<int?>(
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
                      ...allSeasons.map<DropdownMenuItem<int?>>((season) {
                        return DropdownMenuItem<int?>(
                          value: season['id'] as int,
                          child: Text(season['name'] as String),
                        );
                      }).toList(),
                    ],
                    onChanged: _onSeasonChanged,
                  )
                : null,
            list: isLoading
                ? const Center(child: CircularProgressIndicator())
                : allModels.isEmpty
                    ? const Center(child: Text('لا يوجد موديلات'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: allModels.length,
                        itemBuilder: (_, i) {
                          final m = allModels[i];
                          final isSel = m['id'] == selectedModelId;
                          final imageUrl = m['image_url'] as String?;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            elevation: isSel ? 4 : 1,
                            color: isSel ? Colors.grey[100] : Colors.white,
                            child: ListTile(
                              leading: (imageUrl != null && imageUrl.isNotEmpty)
                                  ? GestureDetector(
                                      onTap: () => _showModelImagePopup(imageUrl),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.network(
                                          '${globalServerUri.toString()}$imageUrl',
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                        ),
                                      ),
                                    )
                                  : const Icon(Icons.image, size: 40, color: Colors.grey),
                              selected: isSel,
                              title: Text(
                                m['name'],
                                style: TextStyle(
                                  fontWeight:
                                      isSel ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('المتاح: ${m['available_quantity']}'),
                                  if (role == "Admin" || role == "SuperAdmin")
                                    Text('التكلفة: ${m['cost_price']} دج',
                                        style: TextStyle(color: Colors.teal[700])),
                                ],
                              ),
                              onTap: () =>
                                  setState(() => selectedModelId = m['id']),
                            ),
                          );
                        },
                      ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selectedModelId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'اختر موديل لعرض التفاصيل',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ModelBuyersPanel(
                    modelId: selectedModelId!,
                    seasonId: selectedSeasonId,
                  ),
          ),
        ],
      );
    } else {
      content = Row(
        children: [
          SidePanel(
            title: 'العملاء',
            topFilters: allSeasons.isNotEmpty
                ? DropdownButtonFormField<int?>(
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
                      ...allSeasons.map<DropdownMenuItem<int?>>((season) {
                        return DropdownMenuItem<int?>(
                          value: season['id'] as int,
                          child: Text(season['name'] as String),
                        );
                      }).toList(),
                    ],
                    onChanged: _onSeasonChanged,
                  )
                : null,
            list: isLoading
                ? const Center(child: CircularProgressIndicator())
                : allClients.isEmpty
                    ? const Center(child: Text('لا يوجد عملاء'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: allClients.length,
                        itemBuilder: (_, i) {
                          final c = allClients[i];
                          final isSel = c['id'] == selectedClientId;
                          return Card(
                            key: ValueKey(c['id']),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            elevation: isSel ? 4 : 1,
                            color: isSel ? Colors.grey[100] : Colors.white,
                            child: ListTile(
                              selected: isSel,
                              title: Text(
                                c['full_name'],
                                style: TextStyle(
                                  fontWeight:
                                      isSel ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c['phone'] ?? ''),
                                  Text(c['address'] ?? '',
                                      style: TextStyle(color: Colors.teal[700])),
                                ],
                              ),
                              onTap: () =>
                                  setState(() => selectedClientId = c['id']),
                            ),
                          );
                        },
                      ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selectedClientId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'اختر عميل لعرض التفاصيل',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ClientDetailsTabs(
                    clientId: selectedClientId!,
                    seasonId: selectedSeasonId,
                    role: widget.role,
                  ),
          ),
        ],
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          TabHeader(
            tabs: const ['الموديلات', 'العملاء', 'الفواتير'],
            selected: selectedTab,
            onChanged: (i) {
              setState(() {
                selectedTab = i;
                if (i != 1) selectedClientId = null;
                if (i != 0) selectedModelId = null;
              });
            },
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// =============================================================
/// ModelBuyersPanel - Enhanced Design
/// =============================================================
class ModelBuyersPanel extends StatefulWidget {
  final int modelId;
  final int? seasonId;
  const ModelBuyersPanel({super.key, required this.modelId, this.seasonId});

  @override
  State<ModelBuyersPanel> createState() => _ModelBuyersPanelState();
}

class _ModelBuyersPanelState extends State<ModelBuyersPanel> {
  bool isLoading = false;
  List<dynamic> buyers = [];

  @override
  void initState() {
    super.initState();
    _fetchBuyers();
  }

  @override
  void didUpdateWidget(ModelBuyersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelId != widget.modelId ||
        oldWidget.seasonId != widget.seasonId) {
      _fetchBuyers();
    }
  }

  Future<void> _fetchBuyers() async {
    setState(() {
      isLoading = true;
      buyers = [];
    });
    try {
      final resp = await http.get(Uri.parse(
          '${globalServerUri.toString()}/sales/models/${widget.modelId}/clients'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        if (widget.seasonId == null) {
          setState(() => buyers = data);
        } else {
          setState(() => buyers = data);
        }
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (buyers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا يوجد عملاء اشتروا هذا الموديل',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final Map<int, List<Map<String, dynamic>>> byClient = {};
    for (final b in buyers) {
      final id = b['client_id'] as int;
      byClient.putIfAbsent(id, () => []).add(Map<String, dynamic>.from(b));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'العملاء الذين اشتروا هذا الموديل',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.indigo[800],
            ),
          ),
          const SizedBox(height: 24),
          ...byClient.entries.map((entry) {
            final client = entry.value.first;
            final sales = entry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      color: Colors.blue[50],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.blue[200],
                              child: Icon(Icons.person, color: Colors.blue[800]),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    client['client_name'],
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[800],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.phone, size: 16, color: Colors.blue[600]),
                                      const SizedBox(width: 4),
                                      Text('${client['client_phone']}'),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.location_on, size: 16, color: Colors.blue[600]),
                                      const SizedBox(width: 4),
                                      Expanded(child: Text('${client['client_address']}')),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'سجلات بيع هذا الموديل لهذا العميل:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.all(
                            Theme.of(context).colorScheme.primary),
                        headingTextStyle: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        columns: const [
                          DataColumn(label: Text('تاريخ الفاتورة')),
                          DataColumn(label: Text('رقم الفاتورة')),
                          DataColumn(label: Text('الكمية')),
                          DataColumn(label: Text('سعر البيع')),
                          DataColumn(label: Text('الإجمالي')),
                        ],
                        rows: sales
                            .map<DataRow>((s) => DataRow(cells: [
                                  DataCell(Text(fmtDate(s['facture_date'].toString()))),
                                  DataCell(Text(s['facture_id'].toString())),
                                  DataCell(Text(s['quantity'].toString())),
                                  DataCell(Text('${s['unit_price']} دج')),
                                  DataCell(Text(
                                      '${(s['quantity'] * double.parse(s['unit_price'].toString())).toStringAsFixed(2)} دج')),
                                ]))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}

/// =============================================================
/// ClientDetailsTabs - Enhanced Design with Print Function
/// =============================================================
class ClientDetailsTabs extends StatefulWidget {
  final int clientId;
  final int? seasonId;
  final String role;

  const ClientDetailsTabs({super.key, required this.role, required this.clientId, this.seasonId});

  @override
  State<ClientDetailsTabs> createState() => _ClientDetailsTabsState();
}

class _ClientDetailsTabsState extends State<ClientDetailsTabs> {
  int selectedTab = 0;
  List<dynamic> clientFactures = [];
  List<dynamic> clientTransactions = [];
  Set<int> expandedFactureIds = {};
late pw.Font _arabicFont;
  late pw.Font _latinFont;

  bool loadingFactures = false;
  bool loadingTransactions = false;

  DateTime? startDate;
  DateTime? endDate;
  late String role;

  @override
  void initState() {
    super.initState();
    role = widget.role;
     _loadPdfFonts();

    _fetchFactures();
    _fetchTransactions();
  }

  @override
  void didUpdateWidget(ClientDetailsTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId ||
        oldWidget.seasonId != widget.seasonId) {
      _fetchFactures();
      _fetchTransactions();
      expandedFactureIds.clear();
    }
  }
  Future<void> _loadPdfFonts() async {
    // Arabic (from your assets)
    final arabicData = await rootBundle.load('assets/fonts/NotoSansArabic_Condensed-Black.ttf');
    _arabicFont = pw.Font.ttf(arabicData);
    // Latin fallback (you already have Roboto_Condensed-Black.ttf)
    final latinData = await rootBundle.load('assets/fonts/Roboto_Condensed-Black.ttf');
    _latinFont = pw.Font.ttf(latinData);
  }
  Future<void> _fetchFactures() async {
    setState(() {
      loadingFactures = true;
      clientFactures = [];
    });
    try {
      String url =
          '${globalServerUri.toString()}/sales/clients/${widget.clientId}/factures';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        setState(() => clientFactures = data);
      }
    } finally {
      setState(() => loadingFactures = false);
    }
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      loadingTransactions = true;
      clientTransactions = [];
    });
    try {
      String url =
          '${globalServerUri.toString()}/sales/clients/${widget.clientId}/transactions';
      if (startDate != null && endDate != null) {
        final start = startDate!.toIso8601String().split('T')[0];
        final end = endDate!.toIso8601String().split('T')[0];
        url += '?start_date=$start&end_date=$end';
      }
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        setState(() => clientTransactions = jsonDecode(resp.body));
      }
    } finally {
      setState(() => loadingTransactions = false);
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: startDate != null && endDate != null
          ? DateTimeRange(start: startDate!, end: endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
      _fetchTransactions();
    }
  }


Future<void> _printTransactions() async {
  if (clientTransactions.isEmpty) return;

  // 1. Create PDF document
  final pdf = pw.Document();

  // 2. Load fonts from assets
  final arabicData = await rootBundle.load('assets/fonts/NotoSansArabic_Condensed-Black.ttf');
  final arabicFont = pw.Font.ttf(arabicData);
  final latinData = await rootBundle.load('assets/fonts/Roboto_Condensed-Black.ttf');
  final latinFont = pw.Font.ttf(latinData);

  // 3. Fetch client name
  String clientName = 'عميل غير معروف';
  try {
    final resp = await http.get(Uri.parse('${globalServerUri}/sales/clients'));
    if (resp.statusCode == 200) {
      final clients = jsonDecode(resp.body) as List;
      final c = clients.firstWhere(
        (c) => c['id'] == widget.clientId,
        orElse: () => null,
      );
      if (c != null) clientName = c['full_name'];
    }
  } catch (_) {}

  // 4. Prepare table data
  final rawHeaders = ['التاريخ', 'نوع العملية', 'رقم الفاتورة', 'المبلغ'];
  final rawDataRows = clientTransactions.map<List<String>>((tx) {
    return [
      fmtDate(tx['date'].toString()),
      tx['label'].toString(),
      tx['facture_id']?.toString() ?? '-',
      '${(tx['amount'] as num).toStringAsFixed(2)} دج',
    ];
  }).toList();

  // Reverse for RTL column flow
  final headers = rawHeaders.reversed.toList();
  final dataRows = rawDataRows.map((r) => r.reversed.toList()).toList();

  // 5. Timestamps & duration
  final now = DateTime.now();
  final printedAt = '${now.day.toString().padLeft(2, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-${now.year} '
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';

  // 6. Add page with title, date range, duration, divider, then table
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (context) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Title
              pw.Header(
                level: 0,
                child: pw.Text(
                  'كشف حساب العميل: $clientName',
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    fontFallback: [latinFont],
                  ),
                ),
              ),

              // Printed At
              pw.Text(
                'تاريخ التقرير: ${fmtDate(now.toIso8601String())}',
                style: pw.TextStyle(font: arabicFont, fontSize: 12, fontFallback: [latinFont]),
              ),

              // Date range & duration
              if (startDate != null && endDate != null) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  'من ${fmtDate(startDate!.toIso8601String())} إلى ${fmtDate(endDate!.toIso8601String())}',
                  style: pw.TextStyle(font: arabicFont, fontSize: 12, fontFallback: [latinFont]),
                ),
                pw.Text(
                  'المدة: ${endDate!.difference(startDate!).inDays} يومًا',
                  style: pw.TextStyle(font: arabicFont, fontSize: 12, fontFallback: [latinFont]),
                ),
              ],

              // Divider
              pw.SizedBox(height: 8),
              pw.Divider(),

              // Transactions table
              pw.Table.fromTextArray(
                headers: headers,
                data: dataRows,
                headerStyle: pw.TextStyle(
                  font: arabicFont,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                  fontFallback: [latinFont],
                ),
                cellStyle: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 12,
                  fontFallback: [latinFont],
                ),
                cellAlignment: pw.Alignment.centerRight,
                headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
                border: pw.TableBorder.all(width: 0.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // 7. Save via FilePicker
  final bytes = await pdf.save();
  final String? outputDir = await FilePicker.platform.getDirectoryPath(
    dialogTitle: 'اختر مجلد الحفظ',
  );
  if (outputDir != null) {
    final safeStamp = printedAt.replaceAll(':', '-').replaceAll(' ', '_');
    final filePath = '$outputDir/كشف_حساب_${widget.clientId}_$safeStamp.pdf';
    await io.File(filePath).writeAsBytes(bytes);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ الملف في $filePath'), backgroundColor: Colors.green),
    );
  }
}


/// Helper to build a table cell with optional LTR override
pw.Widget _cell(String text, pw.Font font,
    {bool isHeader = false, bool ltr = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Directionality(
      textDirection:
          ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: isHeader ? 12 : 10,
          fontWeight:
              isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    ),
  );
}

/// Simple check for English letters
bool _containsEnglish(String s) => RegExp(r'[A-Za-z]').hasMatch(s);


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[100],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ...['الفواتير', 'الحساب'].asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: selectedTab == e.key,
                        selectedColor: Theme.of(context).colorScheme.primary,
                        labelStyle: TextStyle(
                          color: selectedTab == e.key ? Colors.white : null,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) => setState(() => selectedTab = e.key),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        Expanded(
          child: selectedTab == 0 ? _buildFacturesTab() : _buildAccountTab(),
        ),
      ],
    );
  }

  Widget _buildFacturesTab() {
    if (loadingFactures) {
      return const Center(child: CircularProgressIndicator());
    }
    if (clientFactures.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا توجد فواتير',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'فواتير العميل',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.indigo[800],
            ),
          ),
          const SizedBox(height: 16),
          ...clientFactures.map((f) {
            final expanded = expandedFactureIds.contains(f['id']);
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              elevation: 2,
              child: Column(
                children: [
                  Card(
                    color: Colors.blue[50],
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue[200],
                        child: Text('${f['id']}'),
                      ),
                      title: Text(
                        'فاتورة رقم ${f['id']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 16, color: Colors.blue[600]),
                              const SizedBox(width: 4),
                              Text('التاريخ: ${fmtDate(f['facture_date'])}'),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: costItem('الإجمالي', f['total_amount'], Colors.green[700]!),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: costItem('المدفوع', f['total_paid'], Colors.blue[700]!),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: costItem('المتبقي', f['remaining_amount'], Colors.orange[700]!),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: expanded ? Colors.blue : Colors.grey,
                      ),
                      onTap: () {
                        setState(() {
                          if (expanded) {
                            expandedFactureIds.remove(f['id']);
                          } else {
                            expandedFactureIds.add(f['id']);
                          }
                        });
                      },
                    ),
                  ),
                  if (expanded)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تفاصيل المنتجات:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(
                                  Theme.of(context).colorScheme.primary),
                              headingTextStyle: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold),
                              columns: [
                                const DataColumn(label: Text('المنتج')),
                                const DataColumn(label: Text('الكمية')),
                                const DataColumn(label: Text('سعر البيع')),
                                if (role == 'Admin' || role == 'SuperAdmin')
                                  const DataColumn(label: Text('ربح/قطعة')),
                                if (role == 'Admin' || role == 'SuperAdmin')
                                  const DataColumn(label: Text('إجمالي الربح')),
                                const DataColumn(label: Text('الإجمالي')),
                              ],
                              rows: (f['items'] as List)
                                  .map<DataRow>(
                                    (it) => DataRow(cells: [
                                      DataCell(Text('${it['model_name'] ?? ''}')),
                                      DataCell(Text('${it['quantity']}')),
                                      DataCell(Text('${it['unit_price']} دج')),
                                      if (role == 'Admin' || role == 'SuperAdmin')
                                        DataCell(Text('${(it['profit_per_piece'] ?? 0).toStringAsFixed(2)} دج')),
                                      if (role == 'Admin' || role == 'SuperAdmin')
                                        DataCell(Text(
                                            '${(((it['profit_per_piece'] ?? 0) * (it['quantity'] ?? 0)).toStringAsFixed(2))} دج')),
                                      DataCell(Text('${(it['line_total'] ?? 0).toStringAsFixed(2)} دج')),
                                    ]),
                                  )
                                  .toList(),
                            ),
                          ),
                          if (f['returns'] != null && (f['returns'] as List).isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'المرتجعات:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                    Theme.of(context).colorScheme.primary),
                                headingTextStyle: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold),
                                columns: const [
                                  DataColumn(label: Text('المنتج')),
                                  DataColumn(label: Text('الكمية')),
                                  DataColumn(label: Text('تاريخ الإرجاع')),
                                  DataColumn(label: Text('ملاحظات')),
                                ],
                                rows: (f['returns'] as List)
                                    .map<DataRow>(
                                      (r) => DataRow(cells: [
                                        DataCell(Text('${r['model_name'] ?? ''}')),
                                        DataCell(Text('${r['quantity'] ?? 0}')),
                                        DataCell(Text(fmtDate(r['return_date']))),
                                        DataCell(Text('${r['notes'] ?? ''}')),
                                      ]),
                                    )
                                    .toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildAccountTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        startDate != null && endDate != null
                            ? 'من ${fmtDate(startDate!.toIso8601String())} إلى ${fmtDate(endDate!.toIso8601String())}'
                            : 'اختر نطاق التاريخ',
                      ),
                      onPressed: _selectDateRange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (startDate != null && endDate != null)
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          startDate = null;
                          endDate = null;
                        });
                        _fetchTransactions();
                      },
                      child: const Text('إزالة التصفية'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (clientTransactions.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.print, color: Colors.white),
                    label: const Text('طباعة المعاملات', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _printTransactions,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: loadingTransactions
              ? const Center(child: CircularProgressIndicator())
              : clientTransactions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance_outlined, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'لا يوجد بيانات حساب',
                            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المعاملات المالية',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo[800],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                    Theme.of(context).colorScheme.primary),
                                headingTextStyle: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold),
                                columns: const [
                                  DataColumn(label: Text('التاريخ')),
                                  DataColumn(label: Text('نوع العملية')),
                                  DataColumn(label: Text('رقم الفاتورة')),
                                  DataColumn(label: Text('المبلغ')),
                                ],
                                rows: clientTransactions
                                    .map<DataRow>(
                                      (e) => DataRow(cells: [
                                        DataCell(Text(fmtDate(e['date'].toString()))),
                                        DataCell(Text(e['label'].toString())),
                                        DataCell(Text(e['facture_id']?.toString() ?? '-')),
                                        DataCell(Text(
                                          '${e['amount'].toString()} دج',
                                          style: TextStyle(
                                            color: (e['amount'] as num) >= 0
                                                ? Colors.red
                                                : Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )),
                                      ]),
                                    )
                                    .toList(),
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
}
