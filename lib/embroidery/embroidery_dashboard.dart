import 'package:flutter/material.dart';
import 'warehouse_section.dart';
import 'models_section.dart';
import 'employees_section.dart';
import 'sales_section.dart';
import 'season_report_section.dart';

class EmbroideryDashboard extends StatefulWidget {
  const EmbroideryDashboard({super.key});

  @override
  State<EmbroideryDashboard> createState() => _EmbroideryDashboardState();
}

class _EmbroideryDashboardState extends State<EmbroideryDashboard> {
  int selectedSubSection = 0;

  final subsections = [
    {'icon': Icons.store, 'label': 'المستودع'},
    {'icon': Icons.checkroom, 'label': 'الموديلات'},
    {'icon': Icons.engineering, 'label': 'العمال'},
    {'icon': Icons.receipt_long, 'label': 'المبيعات'},
    {'icon': Icons.bar_chart, 'label': 'تقرير الموسم'},
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
        title: const Text('التطريز', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                        labelStyle: TextStyle(
                          color: selectedSubSection == i
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) => setState(() => selectedSubSection = i),
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                  ),
                ),
              ),
            ),
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
      case 0:
        return const EmbroideryWarehouseSection();
      case 1:
        return const EmbroideryModelsSection();
      case 2:
        return const EmbroideryEmployeesSection();
      case 3:
        return const EmbroiderySalesSection();
      case 4:
        return const EmbroiderySeasonReportSection();
      default:
        return const SizedBox();
    }
  }
}