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

class SewingDashboard extends StatefulWidget {
  final String role;
  const SewingDashboard({Key? key, required this.role}) : super(key: key);

  @override
  State<SewingDashboard> createState() => _SewingDashboardState();
}

class _SewingDashboardState extends State<SewingDashboard> {
  int selectedSubSection = 0;

  List<Map<String, dynamic>> getAvailableSubsections() {
    // full list in desired order:
    const all = [
      {'icon': Icons.store,          'label': 'المستودع'},
      {'icon': Icons.checkroom,      'label': 'الموديلات'},
      {'icon': Icons.engineering,    'label': 'العمال'},
      {'icon': Icons.receipt_long,   'label': 'المبيعات'},
      {'icon': Icons.people,         'label': 'العملاء'},
      {'icon': Icons.shopping_cart,  'label': 'المشتريات'},
      {'icon': Icons.attach_money,   'label': 'المصاريف'},
      {'icon': Icons.bar_chart,      'label': 'تقرير الموسم'},
      {'icon': Icons.money_off,      'label': 'الديون'},
      {'icon': Icons.local_shipping, 'label': 'الموردين'},
      {'icon': Icons.keyboard_return,'label': 'مرتجع بضاعه'},
    ];
    final isAdmin = widget.role == 'Admin' || widget.role == 'SuperAdmin';

    // filter out sales, expenses & season-report for non-admins
    return all.where((tab) {
      final l = tab['label'] as String;
      if (!isAdmin && (l == 'المبيعات' || l == 'المصاريف' || l == 'تقرير الموسم')) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = getAvailableSubsections();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home),
          tooltip: 'الصفحة الرئيسية',
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor:
            Theme.of(context).colorScheme.primary.withOpacity(0.1),
        title: const Text(
          'الخياطة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // ─── Tabs Row ─────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(tabs.length, (i) {
                    final tab = tabs[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: ChoiceChip(
                        label: Row(
                          children: [
                            Icon(tab['icon'] as IconData, size: 20),
                            const SizedBox(width: 6),
                            Text(tab['label'] as String),
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
                    );
                  }),
                ),
              ),
            ),

            // ─── Content Card ─────────────────────────
            Expanded(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildSectionContent(tabs),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContent(List<Map<String, dynamic>> tabs) {
    final role = widget.role;
    final label = tabs[selectedSubSection]['label'] as String;

    switch (label) {
      case 'المستودع':
        return const SewingWarehouseSection();
      case 'الموديلات':
        return SewingModelsSection(userRole: role);
      case 'العمال':
        return const SewingEmployeesSection();
      case 'المبيعات':
        // only admins ever see this tab, but just in case:
        return role == 'Admin' || role == 'SuperAdmin'
            ? SewingSalesSection(role: role)
            : _notAllowed();
      case 'العملاء':
        return const SewingClientsSection();
      case 'المشتريات':
        return const SewingPurchasesSection();
      case 'المصاريف':
        return role == 'Admin' || role == 'SuperAdmin'
            ? SewingExpensesSection(role: role)
            : _notAllowed();
      case 'تقرير الموسم':
        return role == 'Admin' || role == 'SuperAdmin'
            ? const SeasonReportSection()
            : _notAllowed();
      case 'الديون':
        // we now pass role in so DebtsSection can conditionally hide UI internally
        return DebtsSection(role: role);
      case 'الموردين':
        return const SewingSuppliersSection();
      case 'مرتجع بضاعه':
        return const SewingReturnsSection();
      default:
        return const SizedBox();
    }
  }

  Widget _notAllowed() {
    return const Center(
      child: Text(
        'غير مصرح لك برؤية هذه الصفحة',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
