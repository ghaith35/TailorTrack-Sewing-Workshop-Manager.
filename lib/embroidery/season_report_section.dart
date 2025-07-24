import 'package:flutter/material.dart';

class EmbroiderySeasonReportSection extends StatelessWidget {
  const EmbroiderySeasonReportSection({super.key});

  @override
  Widget build(BuildContext context) {
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