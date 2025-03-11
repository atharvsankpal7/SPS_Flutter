import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class SPCRChartWidget extends StatefulWidget {
  final List<double> data;
  final double height;
  final Color lineColor;
  final Color controlLimitColor;
  final Color centerLineColor;

  const SPCRChartWidget({
    required this.data,
    this.height = 600,
    this.lineColor = Colors.blue,
    this.controlLimitColor = Colors.red,
    this.centerLineColor = Colors.purple,
    Key? key,
  }) : super(key: key);

  @override
  State<SPCRChartWidget> createState() => _SPCRChartWidgetState();
}


class _SPCRChartWidgetState extends State<SPCRChartWidget> {
  int _subgroupSize = 2; // Starting with 2 as minimum for range calculations
  late Map<String, double> _limits;
  late List<double> _rangeValues;
  bool _isInitialized = false;
  bool _hasEnoughData(int sampleSize) {
    return widget.data.length >= sampleSize * 2; // Need at least 2 groups
  }

  static const Map<int, Map<String, double>> _controlConstants = {
    1: {'d2': 1.128, 'd3': 0.0, 'd4': 3.267},  // Add this
    2: {'d2': 1.128, 'd3': 0.0, 'd4': 3.267},
    3: {'d2': 1.693, 'd3': 0.0, 'd4': 2.574},
    4: {'d2': 2.059, 'd3': 0.0, 'd4': 2.282},
    5: {'d2': 2.326, 'd3': 0.0, 'd4': 2.114},
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateControlLimits();
        setState(() {
          _isInitialized = true;
        });
      }
    });
  }

  @override
  void didUpdateWidget(SPCRChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _updateControlLimits();
    }
  }

  void _updateControlLimits() {
    setState(() {
      _limits = _calculateControlLimits();
      _rangeValues = _calculateRanges();
    });
  }

  Widget _buildSubgroupSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Sample Size Selection'), // Added label
          DropdownButton<int>(
            value: _subgroupSize,
            items: [1, 2, 3, 4, 5].map((size) =>
                DropdownMenuItem(value: size, child: Text('Sample Size: $size'))
            ).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _subgroupSize = value;
                  _updateControlLimits();
                });
              }
            },
          ),
        ],
      ),
    );
  }
  Widget _buildStatisticsPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatisticItem(
            label: 'UCL',
            value: _limits['ucl']?.toStringAsFixed(3) ?? 'N/A',
            color: widget.controlLimitColor,
          ),
          _StatisticItem(
            label: 'R̄ (Mean)',
            value: _limits['mean']?.toStringAsFixed(3) ?? 'N/A',
            color: widget.centerLineColor,
          ),
          _StatisticItem(
            label: 'LCL',
            value: _limits['lcl']?.toStringAsFixed(3) ?? 'N/A',
            color: widget.controlLimitColor,
          ),
        ],
      ),
    );
  }

  List<double> _calculateRanges() {
    if (widget.data.isEmpty) return [];

    if (_subgroupSize == 1) {
      return List<double>.generate(
          widget.data.length - 1,
              (i) =>
          max(widget.data[i], widget.data[i + 1]) -
              min(widget.data[i], widget.data[i + 1])
      );
    } else {
      final numberOfGroups = (widget.data.length / _subgroupSize).floor();
      return List<double>.generate(
        numberOfGroups,
            (i) {
          final start = i * _subgroupSize;
          final end = min((i + 1) * _subgroupSize, widget.data.length);
          final subgroup = widget.data.sublist(start, end);
          return subgroup.reduce(max) - subgroup.reduce(min);
        },
      );
    }
  }

  Map<String, double> _calculateControlLimits() {
    final ranges = _calculateRanges();
    if (ranges.isEmpty) {
      return {
        'mean': 0.0,
        'ucl': 0.0,
        'lcl': 0.0,
        'rBar': 0.0,
      };
    }
      final rBar = ranges.reduce((a, b) => a + b) / ranges.length;
      final constants = _controlConstants[_subgroupSize]!;

      return {
        'mean': rBar,
        'ucl': rBar * constants['d4']!,
        'lcl': rBar * constants['d3']!,
        'rBar': rBar,
      };
    }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        children: [
          _LegendItem(
            label: 'Range Values',
            color: widget.lineColor,
          ),
          _LegendItem(
            label: 'R̄ (Mean)',
            color: widget.centerLineColor,
            isLine: true,
          ),
          _LegendItem(
            label: 'UCL/LCL',
            color: widget.controlLimitColor,
            isLine: true,
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_rangeValues.isEmpty) {
          return const Center(
            child: Text('Not enough data to render the chart'),
          );
        }

        final allValues = [..._rangeValues, _limits['ucl']!, _limits['lcl']!];
        final minY = allValues.reduce(min);
        final maxY = allValues.reduce(max);
        final range = maxY - minY;
        final padding = range * 0.1;

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: 1,
                verticalInterval: 1,
              ),
              titlesData: _buildTitlesData(minY - padding, maxY + padding),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.black12, width: 1),
              ),
              minX: 0,
              maxX: (_rangeValues.length - 1).toDouble(),
              minY: minY - padding,
              maxY: maxY + padding,
              lineBarsData: [
                _buildDataLine(),
                _buildHorizontalLine(_limits['ucl']!, widget.controlLimitColor, 'UCL'),
                _buildHorizontalLine(_limits['lcl']!, widget.controlLimitColor, 'LCL'),
                _buildHorizontalLine(_limits['mean']!, widget.centerLineColor, 'Mean'),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  tooltipBorder: BorderSide(color: Colors.black.withOpacity(0.8)),
                  tooltipRoundedRadius: 8,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                    return touchedSpots.map((spot) {
                      String tooltipText = spot.y.toStringAsFixed(3);
                      if (spot.x.toInt() < _rangeValues.length) {
                        tooltipText += '\nGroup ${spot.x.toInt() + 1}';
                      }
                      return LineTooltipItem(
                        tooltipText,
                        const TextStyle(color: Colors.white),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  FlTitlesData _buildTitlesData(double minY, double maxY) {
    return FlTitlesData(
      show: true,
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        axisNameWidget: const Padding(
          padding: EdgeInsets.only(bottom: 12, right: 8),
          child: Text(
            'Range Value',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 60,
          interval: _calculateYAxisInterval(minY, maxY),
          getTitlesWidget: (value, meta) {
            return SideTitleWidget(
              axisSide: meta.axisSide,
              space: 8,
              child: Text(
                value.toStringAsFixed(3),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.normal,
                ),
              ),
            );
          },
        ),
      ),
      bottomTitles: AxisTitles(
        axisNameWidget: const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Subgroup',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index >= 0 && index < _rangeValues.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'G${index + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }
            return const Text('');
          },
        ),
      ),
    );
  }

  double _calculateYAxisInterval(double minY, double maxY) {
    final range = maxY - minY;
    final targetSteps = 8;
    final roughInterval = range / targetSteps;
    final magnitude = pow(10, (log(roughInterval) / ln10).floor());
    final normalized = roughInterval / magnitude;
    double niceInterval;
    if (normalized < 1.2) {
      niceInterval = 1;
    } else if (normalized < 2.5) {
      niceInterval = 2;
    } else if (normalized < 5) {
      niceInterval = 4;
    } else {
      niceInterval = 5;
    }

    final result = niceInterval * magnitude;
    final minMeaningfulInterval = range / 100;
    return max(result, minMeaningfulInterval);
  }

  LineChartBarData _buildDataLine() {
    return LineChartBarData(
      spots: List<FlSpot>.generate(
        _rangeValues.length,
            (i) => FlSpot(i.toDouble(), _rangeValues[i]),
      ),
      isCurved: false,
      color: widget.lineColor,
      barWidth: 2.5,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 5,
          color: widget.lineColor,
          strokeColor: Colors.white,
          strokeWidth: 2,
        ),
      ),
    );
  }

  LineChartBarData _buildHorizontalLine(double y, Color color, String label) {
    return LineChartBarData(
      spots: [
        FlSpot(0, y),
        FlSpot((_rangeValues.length - 1).toDouble(), y),
      ],
      isCurved: false,
      color: color,
      barWidth: label == 'Mean' ? 2.0 : 1.5,
      dotData: const FlDotData(show: false),
      dashArray: label == 'Mean' ? null : [5, 5],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: [
        _buildSubgroupSelector(),
        _buildStatisticsPanel(),
        _buildLegend(),
        SizedBox(
          height: widget.height * 0.7,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 32, 32),
            child: _buildChart(),
          ),
        ),
      ],
    );
  }
}

class _StatisticItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatisticItem({
    required this.label,
    required this.value,
    required this.color,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;
  final bool isLine;

  const _LegendItem({
    required this.label,
    required this.color,
    this.isLine = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isLine)
          Container(
            width: 24,
            height: 4,
            color: color,
            margin: const EdgeInsets.only(right: 8),
          )
        else
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            margin: const EdgeInsets.only(right: 8),
          ),
        Text(label),
      ],
    );
  }
}