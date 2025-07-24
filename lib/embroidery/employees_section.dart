import 'package:flutter/material.dart';

class EmbroideryEmployeesSection extends StatefulWidget {
  const EmbroideryEmployeesSection({super.key});

  @override
  State<EmbroideryEmployeesSection> createState() => _EmbroideryEmployeesSectionState();
}

class _EmbroideryEmployeesSectionState extends State<EmbroideryEmployeesSection> {
  int selectedFilter = 0;
  final filters = ['الجميع', 'قطعة', 'شهريا'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            filters.length,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: ChoiceChip(
                label: Text(filters[i]),
                selected: selectedFilter == i,
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(
                  color: selectedFilter == i
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (_) => setState(() => selectedFilter = i),
                backgroundColor: Colors.grey[200],
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Expanded(
          child: ListView.builder(
            itemCount: 5,
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(Icons.person),
              title: Text('عامل ${i + 1} (${filters[selectedFilter]})'),
              subtitle: const Text('تفاصيل العامل ...'),
            ),
          ),
        ),
      ],
    );
  }
}