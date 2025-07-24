import 'package:flutter/material.dart';

class EmbroideryModelsSection extends StatelessWidget {
  const EmbroideryModelsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Sidebar for models
        Container(
          width: 180,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView(
            children: List.generate(
              5,
              (i) => ListTile(
                leading: const Icon(Icons.checkroom),
                title: Text('موديل ${i + 1}'),
                selected: i == 0,
                onTap: () {},
              ),
            ),
          ),
        ),
        const SizedBox(width: 24),
        // Main content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('إنشاء موديل جديد'),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('تعديل الموديل'),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete),
                    label: const Text('حذف الموديل'),
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // Model details placeholder
              Row(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    color: Colors.grey[300],
                    child: const Icon(Icons.image, size: 60),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('الكمية في المستودع: 50', style: TextStyle(fontSize: 18)),
                        SizedBox(height: 12),
                        Text('المواصفات: ...', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}