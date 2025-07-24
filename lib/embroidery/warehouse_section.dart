import 'package:flutter/material.dart';

class EmbroideryWarehouseSection extends StatefulWidget {
  const EmbroideryWarehouseSection({super.key});

  @override
  State<EmbroideryWarehouseSection> createState() => _EmbroideryWarehouseSectionState();
}

class _EmbroideryWarehouseSectionState extends State<EmbroideryWarehouseSection> {
  int selectedTab = 0;
  final tabs = ['البضاعة الجاهزة', 'مواد خام'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            tabs.length,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: ChoiceChip(
                label: Text(tabs[i]),
                selected: selectedTab == i,
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(
                  color: selectedTab == i
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (_) => setState(() => selectedTab = i),
                backgroundColor: Colors.grey[200],
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Expanded(
          child: Center(
            child: Text(
              'عرض بيانات ${tabs[selectedTab]} (تجريبي)',
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
      ],
    );
  }
}