import 'package:flutter/material.dart';
import 'sewing/sewing_dashboard.dart';

void main() {
  runApp(const MyApp());
}

enum MainSection { sewing, embroidery, design }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام إدارة الورشة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Cairo',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const HomePage(),
    );
  }
}

// --- Home Page with 3 main cards ---
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static final sectionData = [
    {
      'title': 'الخياطة',
      'icon': Icons.local_offer_outlined,
      'section': MainSection.sewing,
    },
    {
      'title': 'التطريز',
      'icon': Icons.format_paint_outlined,
      'section': MainSection.embroidery,
    },
    {
      'title': 'التصميم',
      'icon': Icons.design_services_outlined,
      'section': MainSection.design,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نظام إدارة الورشة', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      ),
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(sectionData.length, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DashboardPage(
                        initialSection: sectionData[i]['section'] as MainSection,
                      ),
                    ),
                  );
                },
                child: Card(
                  elevation: 4,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          sectionData[i]['icon'] as IconData,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          sectionData[i]['title'] as String,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// --- Dashboard Page with Sidebar ---
class DashboardPage extends StatefulWidget {
  final MainSection initialSection;
  const DashboardPage({super.key, required this.initialSection});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late MainSection selectedSection;
  int selectedSubSection = 0;
  bool sidebarOpen = false;

  final sectionData = [
    {
      'title': 'الخياطة',
      'icon': Icons.local_offer_outlined,
    },
    {
      'title': 'التطريز',
      'icon': Icons.format_paint_outlined,
    },
    {
      'title': 'التصميم',
      'icon': Icons.design_services_outlined,
    },
  ];

  List<List<Map<String, dynamic>>> get subsections => [
        // Sewing & Embroidery
        [
          {'icon': Icons.store, 'label': 'المستودع'},
          {'icon': Icons.checkroom, 'label': 'الموديلات'},
          {'icon': Icons.engineering, 'label': 'العمال'},
          {'icon': Icons.receipt_long, 'label': 'المبيعات'},
          {'icon': Icons.bar_chart, 'label': 'تقرير الموسم'},
        ],
        [
          {'icon': Icons.store, 'label': 'المستودع'},
          {'icon': Icons.checkroom, 'label': 'الموديلات'},
          {'icon': Icons.engineering, 'label': 'العمال'},
          {'icon': Icons.receipt_long, 'label': 'المبيعات'},
          {'icon': Icons.bar_chart, 'label': 'تقرير الموسم'},
        ],
        // Design
        [
          {'icon': Icons.store, 'label': 'المستودع'},
          {'icon': Icons.checkroom, 'label': 'الموديلات'},
          {'icon': Icons.receipt_long, 'label': 'المبيعات'},
          {'icon': Icons.people, 'label': 'العملاء'},
        ],
      ];

  @override
  void initState() {
    super.initState();
    selectedSection = widget.initialSection;
    selectedSubSection = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home), // Use home icon
          tooltip: 'الصفحة الرئيسية',
          onPressed: () {
            Navigator.pop(context); // Return to HomePage
          },
        ),
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        title: const Text('لوحة تحكم الإدارة', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Row(
        children: [
          // Sidebar
          if (sidebarOpen)
            Container(
              width: 220,
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => sidebarOpen = false),
                    ),
                  ),
                  ...List.generate(sectionData.length, (i) {
                    return ListTile(
                      leading: Icon(sectionData[i]['icon'] as IconData),
                      title: Text(
                        sectionData[i]['title'] as String,
                        style: const TextStyle(fontSize: 18),
                      ),
                      selected: selectedSection.index == i,
                      selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                      onTap: () {
                        setState(() {
                          selectedSection = MainSection.values[i];
                          selectedSubSection = 0;
                          sidebarOpen = false;
                        });
                      },
                    );
                  }),
                ],
              ),
            ),
          // Main content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  // Subsection tabs
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center, // Center the subsection tabs
                        children: List.generate(
                          subsections[selectedSection.index].length,
                          (i) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: ChoiceChip(
                              label: Row(
                                children: [
                                  Icon(subsections[selectedSection.index][i]['icon'] as IconData, size: 20),
                                  const SizedBox(width: 6),
                                  Text(subsections[selectedSection.index][i]['label'] as String),
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
                  // Subsection content
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
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContent() {
    // Sewing & Embroidery have same structure
    if (selectedSection == MainSection.sewing || selectedSection == MainSection.embroidery) {
      switch (selectedSubSection) {
        case 0:
          return _WarehouseSection();
        case 1:
          return _ModelsSection();
        case 2:
          return _EmployeesSection();
        case 3:
          return _SalesSection();
        case 4:
          return _SeasonReportSection();
        default:
          return const SizedBox();
      }
    }
    // Design section
    if (selectedSection == MainSection.design) {
      switch (selectedSubSection) {
        case 0:
          return _WarehouseSection();
        case 1:
          return _ModelsSection();
        case 2:
          return _SalesSection();
        case 3:
          return _ClientsSection();
        default:
          return const SizedBox();
      }
    }
    return const SizedBox();
  }
}

// --- Section Widgets (placeholders) ---

class _WarehouseSection extends StatefulWidget {
  @override
  State<_WarehouseSection> createState() => _WarehouseSectionState();
}

class _WarehouseSectionState extends State<_WarehouseSection> {
  int selectedTab = 0;
  final tabs = ['البضاعة الجاهزة', 'مواد خام'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center, // Center the warehouse tabs
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

class _ModelsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Placeholder for models sidebar and actions
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
                mainAxisAlignment: MainAxisAlignment.center, // Center the action buttons
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

class _EmployeesSection extends StatefulWidget {
  @override
  State<_EmployeesSection> createState() => _EmployeesSectionState();
}

class _EmployeesSectionState extends State<_EmployeesSection> {
  int selectedFilter = 0;
  final filters = ['الجميع', 'قطعة', 'شهريا'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center, // Center the filter buttons
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

class _SalesSection extends StatefulWidget {
  @override
  State<_SalesSection> createState() => _SalesSectionState();
}

class _SalesSectionState extends State<_SalesSection> {
  int selectedTab = 0; // 0: الموديلات, 1: العملاء
  int? selectedSidebarIndex; // null means show all

  final tabs = ['الموديلات', 'العملاء'];

  @override
  Widget build(BuildContext context) {
    // Sidebar data
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
                      // If already on this tab but a specific item is selected, go back to list
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

class _ClientsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (_, i) => ListTile(
        leading: const Icon(Icons.person),
        title: Text('عميل ${i + 1}'),
        subtitle: const Text('تفاصيل العميل ...'),
      ),
    );
  }
}

class _SeasonReportSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Placeholder for season report
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.bar_chart, size: 80, color: Colors.teal),
          SizedBox(height: 24),
          Text('تقرير الموسم (تجريبي)', style: TextStyle(fontSize: 24)),
        ],
      ),
    );
  }
}