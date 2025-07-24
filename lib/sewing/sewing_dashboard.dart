import 'package:flutter/material.dart';
import 'warehouse_section.dart';
import 'suppliers_section.dart';
import 'debts_section.dart';
import 'expenses_section.dart';
import 'models_section.dart';
import 'employees_section.dart';
import 'sales_section.dart';
import 'season_report_section.dart';
import 'clients_section.dart';
import 'purchases_section.dart';
import 'sewing_returns_section.dart';
// import 'machines_section.dart'; // ← new

class SewingDashboard extends StatefulWidget {
  const SewingDashboard({super.key});

  @override
  State<SewingDashboard> createState() => _SewingDashboardState();
}

class _SewingDashboardState extends State<SewingDashboard> {
  int selectedSubSection = 0;

  final subsections = [
    {'icon': Icons.store,                'label': 'المستودع'},
    {'icon': Icons.checkroom,            'label': 'الموديلات'},
    {'icon': Icons.engineering,          'label': 'العمال'},
    {'icon': Icons.receipt_long,         'label': 'المبيعات'},
    {'icon': Icons.people,               'label': 'العملاء'},
    {'icon': Icons.shopping_cart,        'label': 'المشتريات'},
    {'icon': Icons.bar_chart,            'label': 'تقرير الموسم'},
    {'icon': Icons.attach_money,         'label': 'المصاريف'},
    {'icon': Icons.money_off,            'label': 'الديون'},
    {'icon': Icons.local_shipping,       'label': 'الموردين'},
    {'icon': Icons.keyboard_return,       'label': 'مرتجع بضاعه',},

    // {'icon': Icons.precision_manufacturing, 'label': 'المكينات'}, // ← new
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home),
          tooltip: 'الصفحة الرئيسية',
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        title: const Text('الخياطة', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // ─── Tabs Row ──────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(
                    subsections.length,
                    (i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: ChoiceChip(
                        label: Row(
                          children: [
                            Icon(subsections[i]['icon'] as IconData, size: 20),
                            const SizedBox(width: 6),
                            Text(subsections[i]['label'] as String),
                          ],
                        ),
                        selected: selectedSubSection == i,
                        selectedColor: Theme.of(context).colorScheme.primary,
                        backgroundColor: Colors.grey[200],
                        labelStyle: TextStyle(
                          color: selectedSubSection == i
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) => setState(() => selectedSubSection = i),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ─── Content Card ──────────────────────────────────────────────────────
            Expanded(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildSectionContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContent() {
    switch (selectedSubSection) {
      case 0:  return const SewingWarehouseSection();
      case 1:  return const SewingModelsSection();
      case 2:  return const SewingEmployeesSection();
      case 3:  return const SewingSalesSection();
      case 4:  return const SewingClientsSection();
      case 5:  return const SewingPurchasesSection();
      case 6:  return const SeasonReportSection();
      case 7:  return const SewingExpensesSection();
      case 8:  return const DebtsSection();
      case 9:  return const SewingSuppliersSection();
      case 10: return const SewingReturnsSection();

      // case 10: return const MachinesSection();  // ← new
      default: return const SizedBox();
    }
  }
}
