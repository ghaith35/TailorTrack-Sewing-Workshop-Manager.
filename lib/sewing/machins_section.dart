// machines_section.dart

import 'package:flutter/material.dart';

/// MachinesSection: displays and manages workshop machines
class MachinesSection extends StatefulWidget {
  const MachinesSection({Key? key}) : super(key: key);

  @override
  State<MachinesSection> createState() => _MachinesSectionState();
}

class _MachinesSectionState extends State<MachinesSection> {
  // Example in-memory list; replace with real data fetch
  List<Map<String, dynamic>> machines = [
    {'id': 1, 'name': 'آلة خياطة 1', 'status': 'working'},
    {'id': 2, 'name': 'آلة خياطة 2', 'status': 'needs_repair'},
  ];
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('إضافة ماكينة'),
            onPressed: () => _showMachineDialog(),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(
                          Theme.of(context).colorScheme.primary),
                      columns: const [
                        DataColumn(
                            label: Text('الاسم',
                                style: TextStyle(color: Colors.white))),
                        DataColumn(
                            label: Text('الحالة',
                                style: TextStyle(color: Colors.white))),
                        DataColumn(
                            label: Text('إجراءات',
                                style: TextStyle(color: Colors.white))),
                      ],
                      rows: machines.map((machine) {
                        return DataRow(cells: [
                          DataCell(Center(child: Text(machine['name']))),
                          DataCell(Center(child: Text(machine['status']))),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.green),
                                onPressed: () =>
                                    _showMachineDialog(initial: machine),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteMachine(machine['id']),
                              ),
                            ],
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _showMachineDialog({Map<String, dynamic>? initial}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => MachineDialog(initial: initial),
    );
    if (result != null) {
      setState(() {
        if (initial == null) {
          // Assign a temporary ID; replace with real backend ID
          final newId =
              (machines.isNotEmpty ? machines.last['id'] as int : 0) + 1;
          machines.add({'id': newId, ...result});
        } else {
          final index = machines.indexWhere((m) => m['id'] == initial['id']);
          machines[index] = {'id': initial['id'], ...result};
        }
      });
    }
  }

  void _deleteMachine(int id) {
    setState(() {
      machines.removeWhere((m) => m['id'] == id);
    });
  }
}

/// Dialog for adding/editing a machine
class MachineDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const MachineDialog({this.initial, Key? key}) : super(key: key);

  @override
  State<MachineDialog> createState() => _MachineDialogState();
}

class _MachineDialogState extends State<MachineDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  String _status = 'working';

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _nameController = TextEditingController(text: init?['name'] ?? '');
    _status = init?['status'] ?? 'working';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'إضافة ماكينة' : 'تعديل ماكينة'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'اسم الماكينة'),
              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              items: const [
                DropdownMenuItem(value: 'working', child: Text('عاملة')),
                DropdownMenuItem(
                    value: 'needs_repair', child: Text('بحاجة لصيانة')),
                DropdownMenuItem(value: 'retired', child: Text('متقاعدة')),
              ],
              decoration: const InputDecoration(labelText: 'الحالة'),
              onChanged: (v) => setState(() => _status = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop<Map<String, dynamic>>(context, {
                'name': _nameController.text.trim(),
                'status': _status,
              });
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
