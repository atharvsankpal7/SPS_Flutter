// import 'package:fl_chart/fl_chart.dart';
// import 'package:flutter/material.dart';
// import 'dart:math';
//
// class HistogramWidget extends StatefulWidget {
//   final List<double> data;
//   final double? lsl;
//   final double? usl;
//   final double? target;
//
//   const HistogramWidget({
//     required this.data,
//     this.lsl,
//     this.usl,
//     this.target,
//     Key? key,
//   }) : super(key: key);
//
//   @override
//   _HistogramWidgetState createState() => _HistogramWidgetState();
// }
//
// class _HistogramWidgetState extends State<HistogramWidget> {
//   late int _binCount;
//   late double _mean;
//   late double _stdDev;
//
//   @override
//   void initState() {
//     super.initState();
//     _binCount = _calculateOptimalBinCount(widget.data);
//     _calculateStatistics();
//   }
//
//   void _calculateStatistics() {
//     _mean = widget.data.reduce((a, b) => a + b) / widget.data.length;
//     final squaredDiffs = widget.data.map((value) => pow(value - _mean, 2));
//     _stdDev = sqrt(squaredDiffs.reduce((a, b) => a + b) / widget.data.length);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final histogramData = _calculateHistogramData(widget.data, _binCount);
//     final dropdownOptions = _getDropdownOptions(widget.data);
//
//     if (!dropdownOptions.contains(_binCount)) {
//       setState(() {
//         _binCount = dropdownOptions.first;
//       });
//       return const Center(child: CircularProgressIndicator());
//     }
//
//     return Card(
//       elevation: 4,
//       margin: const EdgeInsets.all(8),
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 const Text(
//                   'Distribution Analysis',
//                   style: TextStyle(
//                     fontSize: 20,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
//                   decoration: BoxDecoration(
//                     border: Border.all(color: Colors.grey.shade300),
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                   child: Row(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       const Text('Bins: '),
//                       DropdownButtonHideUnderline(
//                         child: DropdownButton<int>(
//                           value: _binCount,
//                           items: dropdownOptions.map((int value) {
//                             return DropdownMenuItem<int>(
//                               value: value,
//                               child: Text('$value'),
//                             );
//                           }).toList(),
//                           onChanged: (int? newValue) {
//                             if (newValue != null) {
//                               setState(() {
//                                 _binCount = newValue;
//                               });
//                             }
//                           },
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//             Container(
//               padding: const EdgeInsets.all(8),
//               decoration: BoxDecoration(
//                 color: Colors.grey.shade100,
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceAround,
//                 children: [
//                   _StatisticBox(
//                     label: 'Mean',
//                     value: _mean.toStringAsFixed(4),
//                     color: Colors.blue.shade100,
//                   ),
//                   _StatisticBox(
//                     label: 'Std Dev',
//                     value: _stdDev.toStringAsFixed(4),
//                     color: Colors.green.shade100,
//                   ),
//                   if (widget.target != null)
//                     _StatisticBox(
//                       label: 'Target',
//                       value: widget.target!.toStringAsFixed(4),
//                       color: Colors.orange.shade100,
//                     ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 16),
//             SizedBox(
//               height: 400, // Increased height for better visibility
//               child: BarChart(
//                 _buildBarChart(histogramData),
//               ),
//             ),
//             const SizedBox(height: 8),
//             _buildLegend(),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildLegend() {
//     return Wrap(
//       spacing: 16,
//       runSpacing: 8,
//       alignment: WrapAlignment.center,
//       children: [
//         _LegendItem(color: Colors.blue.shade700, label: 'Frequency'),
//         _LegendItem(color: Colors.green.shade700, label: 'Mean'),
//         if (widget.target != null)
//           _LegendItem(color: Colors.green, label: 'Target'),
//         if (widget.lsl != null)
//           _LegendItem(color: Colors.red, label: 'LSL'),
//         if (widget.usl != null)
//           _LegendItem(color: Colors.red, label: 'USL'),
//       ],
//     );
//   }
//
//   BarChartData _buildBarChart(List<Map<String, dynamic>> histogramData) {
//     final maxFrequency = histogramData
//         .map((bin) => bin['frequency'] as num)
//         .reduce((a, b) => max(a, b))
//         .ceil();
//     final totalSamples = widget.data.length;
//
//     return BarChartData(
//       alignment: BarChartAlignment.spaceEvenly,
//       maxY: maxFrequency + (maxFrequency * 0.1), // Add 10% padding
//       minY: 0,
//       barGroups: histogramData.asMap().entries.map((entry) {
//         final index = entry.key;
//         final bin = entry.value;
//         return BarChartGroupData(
//           x: index,
//           barRods: [
//             BarChartRodData(
//               toY: (bin['frequency'] as num).toDouble(),
//               gradient: LinearGradient(
//                 colors: [Colors.blue.shade300, Colors.blue.shade700],
//                 begin: Alignment.bottomCenter,
//                 end: Alignment.topCenter,
//               ),
//               width: (MediaQuery.of(context).size.width - 64) / (histogramData.length * 2),
//               borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
//             ),
//           ],
//         );
//       }).toList(),
//       titlesData: _buildTitlesData(histogramData),
//       gridData: FlGridData(
//         show: true,
//         drawVerticalLine: true,
//         horizontalInterval: 1,
//         verticalInterval: 1,
//         getDrawingHorizontalLine: (value) {
//           return FlLine(
//             color: Colors.grey.shade300,
//             strokeWidth: 1,
//             dashArray: [5, 5],
//           );
//         },
//         getDrawingVerticalLine: (value) {
//           return FlLine(
//             color: Colors.grey.shade300,
//             strokeWidth: 1,
//             dashArray: [5, 5],
//           );
//         },
//       ),
//       borderData: FlBorderData(
//         show: true,
//         border: Border.all(color: Colors.grey.shade400),
//       ),
//       extraLinesData: ExtraLinesData(
//         horizontalLines: [],
//         verticalLines: [
//           if (widget.lsl != null)
//             VerticalLine(
//               x: _getXPositionForValue(widget.lsl!, histogramData),
//               color: Colors.red,
//               strokeWidth: 2,
//               dashArray: [5, 5],
//               label: VerticalLineLabel(
//                 show: true,
//                 labelResolver: (line) => 'LSL',
//                 alignment: Alignment.topRight,
//                 style: const TextStyle(color: Colors.red),
//               ),
//             ),
//           if (widget.usl != null)
//             VerticalLine(
//               x: _getXPositionForValue(widget.usl!, histogramData),
//               color: Colors.red,
//               strokeWidth: 2,
//               dashArray: [5, 5],
//               label: VerticalLineLabel(
//                 show: true,
//                 labelResolver: (line) => 'USL',
//                 alignment: Alignment.topRight,
//                 style: const TextStyle(color: Colors.red),
//               ),
//             ),
//           if (widget.target != null)
//             VerticalLine(
//               x: _getXPositionForValue(widget.target!, histogramData),
//               color: Colors.green,
//               strokeWidth: 2,
//               dashArray: [5, 5],
//               label: VerticalLineLabel(
//                 show: true,
//                 labelResolver: (line) => 'Target',
//                 alignment: Alignment.topRight,
//                 style: const TextStyle(color: Colors.green),
//               ),
//             ),
//           VerticalLine(
//             x: _getXPositionForValue(_mean, histogramData),
//             color: Colors.green.shade700,
//             strokeWidth: 2,
//             label: VerticalLineLabel(
//               show: true,
//               labelResolver: (line) => 'Mean',
//               alignment: Alignment.topRight,
//               style: TextStyle(color: Colors.green.shade700),
//             ),
//           ),
//         ],
//       ),
//       barTouchData: BarTouchData(
//         enabled: true,
//         touchTooltipData: BarTouchTooltipData(
//           fitInsideHorizontally: true,
//           fitInsideVertically: true,
//           getTooltipItem: (group, groupIndex, rod, rodIndex) {
//             final bin = histogramData[groupIndex];
//             final percentage = (rod.toY / totalSamples * 100).toStringAsFixed(1);
//             return BarTooltipItem(
//               'Range: ${bin['binStart'].toStringAsFixed(4)} - ${bin['binEnd'].toStringAsFixed(4)}\n'
//                   'Count: ${rod.toY.toStringAsFixed(0)}\n'
//                   'Percentage: $percentage%',
//               const TextStyle(color: Colors.white),
//             );
//           },
//         ),
//       ),
//     );
//   }
//
//   double _getXPositionForValue(
//       double value, List<Map<String, dynamic>> histogramData) {
//     for (int i = 0; i < histogramData.length; i++) {
//       if (value >= histogramData[i]['binStart'] &&
//           value <= histogramData[i]['binEnd']) {
//         return i.toDouble();
//       }
//     }
//     final firstBin = histogramData.first;
//     final lastBin = histogramData.last;
//     final totalRange = lastBin['binEnd'] - firstBin['binStart'];
//     final position =
//         (value - firstBin['binStart']) / totalRange * histogramData.length;
//     return position.clamp(0, histogramData.length - 1).toDouble();
//   }
//
//   FlTitlesData _buildTitlesData(List<Map<String, dynamic>> histogramData) {
//     return FlTitlesData(
//       leftTitles: AxisTitles(
//         sideTitles: SideTitles(
//           showTitles: true,
//           reservedSize: 40,
//           getTitlesWidget: (value, meta) => Text(value.toInt().toString(),
//               style: const TextStyle(fontSize: 12)),
//         ),
//       ),
//       bottomTitles: AxisTitles(
//         sideTitles: SideTitles(
//           showTitles: true,
//           reservedSize: 50,
//           getTitlesWidget: (value, meta) {
//             final index = value.toInt();
//             if (index >= 0 && index < histogramData.length) {
//               final bin = histogramData[index];
//               return Padding(
//                 padding: const EdgeInsets.only(top: 8.0),
//                 child: Text(
//                   "${bin['binStart'].toStringAsFixed(4)}\n${bin['binEnd'].toStringAsFixed(4)}",
//                   style: const TextStyle(fontSize: 10),
//                   textAlign: TextAlign.center,
//                 ),
//               );
//             }
//             return const Text("");
//           },
//         ),
//       ),
//       topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//       rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//     );
//   }
//
//   List<int> _getDropdownOptions(List<double> data) {
//     final optimalBins = _calculateOptimalBinCount(data);
//     // Create a set and convert to sorted list
//     final options = <int>{
//       4,  // minimum
//       optimalBins,
//       min(optimalBins + 2, 20),
//       min(16, 20)  // maximum
//     };
//     return options.toList()..sort();
//   }
//
//   int _calculateOptimalBinCount(List<double> data) {
//     final n = data.length;
//     if (n <= 1) return 4;  // Return minimum bins for very small datasets
//     // Use Sturges' formula with a minimum of 4 bins
//     return max(4, (1 + 3.322 * log(n) / log(10)).round().clamp(4, 20));
//   }
//
//
//   List<Map<String, dynamic>> _calculateHistogramData(
//       List<double> data, int bins) {
//     if (data.isEmpty) return [];
//     final dataMin = data.reduce(min);
//     final dataMax = data.reduce(max);
//     final binWidth = (dataMax - dataMin) / bins;
//     final precision = pow(10, 4);
//
//     final histogram = List.generate(bins, (i) {
//       final start = ((dataMin + i * binWidth) * precision).round() / precision;
//       final end = ((start + binWidth) * precision).round() / precision;
//       return {"binStart": start, "binEnd": end, "frequency": 0};
//     });
//
//     for (final value in data) {
//       final int index =
//       ((value - dataMin) / binWidth).floor().clamp(0, bins - 1);
//       histogram[index]["frequency"] = (histogram[index]["frequency"] ?? 0) + 1;
//     }
//     return histogram;
//   }
// }
//
// class _StatisticBox extends StatelessWidget {
//   final String label;
//   final String value;
//   final Color color;
//
//   const _StatisticBox({
//     required this.label,
//     required this.value,
//     required this.color,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//       decoration: BoxDecoration(
//         color: color,
//         borderRadius: BorderRadius.circular(8),
//       ),
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Text(
//             label,
//             style: const TextStyle(
//               fontWeight: FontWeight.bold,
//               fontSize: 12,
//             ),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             value,
//             style: const TextStyle(fontSize: 14),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// class _LegendItem extends StatelessWidget {
//   final Color color;
//   final String label;
//
//   const _LegendItem({
//     required this.color,
//     required this.label,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Container(
//           width: 16,
//           height: 16,
//           decoration: BoxDecoration(
//             color: color,
//             borderRadius: BorderRadius.circular(4),
//           ),
//         ),
//         const SizedBox(width: 4),
//         Text(
//           label,
//           style: const TextStyle(fontSize: 12),
//         ),
//       ],
//     );
//   }
// }
