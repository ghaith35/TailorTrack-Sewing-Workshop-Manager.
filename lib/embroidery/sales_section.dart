import 'package:flutter/material.dart';

class EmbroiderySalesSection extends StatefulWidget {
  const EmbroiderySalesSection({super.key});

  @override
  State<EmbroiderySalesSection> createState() => _EmbroiderySalesSectionState();
}

class _EmbroiderySalesSectionState extends State<EmbroiderySalesSection> {
  int selectedTab = 0; // 0: الموديلات, 1: العملاء
  int? selectedSidebarIndex; // null means show all

  final tabs = ['الموديلات', 'العملاء'];

  @override
  Widget build(BuildContext context) {
    final sidebarItems = selectedTab == 0
        ? List.generate(5, (i) => 'موديل ${i + 1}')
        : List.generate(5, (i) => 'عميل ${i + 1}');

    return Row(
      children: [
        // Sidebar for tabs (موديلات/عملاء)
        Container(
          width: 180,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Tabs
              ...List.generate(
                tabs.length,
                (i) => ListTile(
                  leading: Icon(i == 0 ? Icons.checkroom : Icons.people),
                  title: Text(tabs[i]),
                  selected: selectedTab == i && selectedSidebarIndex == null,
                  onTap: () => setState(() {
                    if (selectedTab == i && selectedSidebarIndex != null) {
                      selectedSidebarIndex = null;
                    } else {
                      selectedTab = i;
                      selectedSidebarIndex = null;
                    }
                  }),
                ),
              ),
              const Divider(),
              // Sidebar items (models or clients)
              Expanded(
                child: ListView.builder(
                  itemCount: sidebarItems.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(sidebarItems[i]),
                    selected: selectedSidebarIndex == i,
                    onTap: () => setState(() => selectedSidebarIndex = i),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Main content: details or list
        Expanded(
          child: selectedSidebarIndex == null
              // Show all items
              ? ListView.builder(
                  itemCount: sidebarItems.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: Icon(selectedTab == 0 ? Icons.checkroom : Icons.person),
                    title: Text(sidebarItems[i]),
                    subtitle: Text(selectedTab == 0 ? 'تفاصيل المبيعات ...' : 'تفاصيل العميل ...'),
                    onTap: () => setState(() => selectedSidebarIndex = i),
                  ),
                )
              // Show details for one item
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(selectedTab == 0 ? Icons.checkroom : Icons.person, size: 60, color: Colors.teal),
                      const SizedBox(height: 16),
                      Text(
                        sidebarItems[selectedSidebarIndex!],
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        selectedTab == 0 ? 'تفاصيل المبيعات ...' : 'تفاصيل العميل ...',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('رجوع إلى القائمة'),
                        onPressed: () => setState(() => selectedSidebarIndex = null),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}