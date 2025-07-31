import 'package:flutter/material.dart';

import 'embroidery_warehouse_section.dart';
import 'embroidery_models_section.dart';
import 'embroidery_employees_section.dart';
import 'embroidery_sales_section.dart';
import 'embroidery_clients_section.dart';
import 'embroidery_purchases_section.dart';
import 'embroidery_season_report_section.dart';
import 'embroidery_expenses_section.dart';
import 'embroidery_debts_section.dart';
import 'embroidery_suppliers_section.dart';
import 'embroidery_returns_section.dart';

class EmbroideryDashboard extends StatefulWidget {
  final String role; // Add a role parameter to handle user roles
  const EmbroideryDashboard({super.key, required this.role}); // Updated constructor

  @override
  State<EmbroideryDashboard> createState() => _EmbroideryDashboardState();
}

class _EmbroideryDashboardState extends State<EmbroideryDashboard> {
  int selectedSubSection = 0;

  // Define subsections based on the role
  List<Map<String, dynamic>> getAvailableSubsections() {
    final base = [
      {'icon': Icons.store,           'label': 'المستودع'},
      {'icon': Icons.checkroom,       'label': 'الموديلات'},
      {'icon': Icons.engineering,     'label': 'العمال'},
      {'icon': Icons.receipt_long,    'label': 'المبيعات'},
      {'icon': Icons.people,          'label': 'العملاء'},
      {'icon': Icons.shopping_cart,   'label': 'المشتريات'},
      {'icon': Icons.attach_money,    'label': 'المصاريف'},
      {'icon': Icons.money_off,       'label': 'الديون'},
      {'icon': Icons.local_shipping,  'label': 'الموردين'},
      {'icon': Icons.keyboard_return, 'label': 'مرتجع بضاعه'},
    ];

    // Conditionally add the season report section for Admin and SuperAdmin
    if (widget.role == 'Admin' || widget.role == 'SuperAdmin') {
      base.add({'icon': Icons.bar_chart, 'label': 'تقرير الموسم'});
    }

    return base;
  }

  @override
  Widget build(BuildContext context) {
    final subsections = getAvailableSubsections();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home),
          tooltip: 'الصفحة الرئيسية',
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        title: const Text(
          'التطريز',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
                            Icon(
                              subsections[i]['icon'] as IconData,
                              size: 20,
                            ),
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
                        onSelected: (_) =>
                            setState(() => selectedSubSection = i),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildSectionContent(subsections),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContent(List<Map<String, dynamic>> tabs) {
    switch (tabs[selectedSubSection]['label']) {
      case 'المستودع':
        return const EmbroideryWarehouseSection();
      case 'الموديلات':
        return const EmbroideryModelsSection();
      case 'العمال':
        return const EmbroideryEmployeesSection();
      case 'المبيعات':
        return const EmbroiderySalesSection();
      case 'العملاء':
        return const EmbroideryClientsSection();
      case 'المشتريات':
        return const EmbroideryPurchasesSection();
      case 'تقرير الموسم':
        if (widget.role == 'Admin' || widget.role == 'SuperAdmin') {
          return const EmbroiderySeasonReportSection();
        } else {
          return const Center(
            child: Text(
              'غير مصرح لك برؤية تقرير الموسم',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          );
        }
      case 'المصاريف':
        return const EmbroideryExpensesSection();
      case 'الديون':
        return const EmbroideryDebtsSection();
      case 'الموردين':
        return const EmbroiderySuppliersSection();
      case 'مرتجع بضاعه':
        return const EmbroideryReturnsSection();
      default:
        return const SizedBox();
    }
  }
}
