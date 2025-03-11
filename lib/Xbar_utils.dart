import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class SPCXbarChartWidget extends StatefulWidget {
  final List<double> data;
  final double height;
  final Color lineColor;
  final Color controlLimitColor;
  final Color centerLineColor;

  const SPCXbarChartWidget({
    required this.data,
    this.height = 600,
    this.lineColor = Colors.blue,
    this.controlLimitColor = Colors.red,
    this.centerLineColor = Colors.purple,
    Key? key,
  }) : super(key: key);

  @override
  State<SPCXbarChartWidget> createState() => _SPCXbarChartWidgetState();
}

class _SPCXbarChartWidgetState extends State<SPCXbarChartWidget> {
  int _subgroupSize = 1;
  Map<String, double> _limits = {};
  List<double> _xBarValues = [];
  double _rBar = 0.0;
  bool _isInitialized = false;

  static const Map<int, Map<String, double>> _controlConstants = {
    1: {'d2': 1.128, 'a2': 2.66, 'd3': 0.0, 'd4': 3.267},
    2: {'d2': 1.128, 'a2': 1.88, 'd3': 0.0, 'd4': 3.267},
    3: {'d2': 1.693, 'a2': 1.772, 'd3': 0.0, 'd4': 2.574},
    4: {'d2': 2.059, 'a2': 0.796, 'd3': 0.0, 'd4': 2.282},
    5: {'d2': 2.326, 'a2': 0.691, 'd3': 0.0, 'd4': 2.114},
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
  void didUpdateWidget(SPCXbarChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _updateControlLimits();
    }
  }

  void _updateControlLimits() {
    if (!mounted) return;

    setState(() {
      _xBarValues = _calculateXbarValues();
      final ranges = _calculateRanges();
      if (ranges.isNotEmpty) {
        _rBar = ranges.reduce((a, b) => a + b) / ranges.length;
      }
      _limits = _calculateControlLimits();
    });
  }


  List<double> _calculateXbarValues() {
    if (widget.data.isEmpty || widget.data.length < _subgroupSize) {
      return [];
    }

    // Special handling for Sample Size 1
    if (_subgroupSize == 1) {
      // For Sample Size 1, each value represents its own measurement
      return List<double>.from(widget.data);
    }

    final xBarValues = <double>[];
    final numberOfCompleteGroups = (widget.data.length / _subgroupSize).floor();

    for (var i = 0; i < numberOfCompleteGroups; i++) {
      final start = i * _subgroupSize;
      final end = start + _subgroupSize;
      final subgroup = widget.data.sublist(start, end);

      // Calculate average for the subgroup
      final xBar = subgroup.reduce((a, b) => a + b) / subgroup.length;
      xBarValues.add(xBar);
    }

    // Handle remaining points if they form a valid group
    final remainingStart = numberOfCompleteGroups * _subgroupSize;
    if (remainingStart < widget.data.length) {
      final remainingPoints = widget.data.sublist(remainingStart);
      // Only include if we have enough points for a meaningful average
      if (remainingPoints.length >= 2) {
        final xBar = remainingPoints.reduce((a, b) => a + b) / remainingPoints.length;
        xBarValues.add(xBar);
      }
    }

    return xBarValues;
  }

  int getNumberOfGroups(int sampleSize) {
    if (widget.data.isEmpty) return 0;

    if (sampleSize == 1) {
      return widget.data.length; // Each point is its own group
    }

    final completeGroups = (widget.data.length / sampleSize).floor();
    final remainingPoints = widget.data.length % sampleSize;

    // Add one more group if there are enough remaining points
    return completeGroups + (remainingPoints >= 2 ? 1 : 0);
  }

  List<double> _calculateRanges() {
    if (widget.data.isEmpty) return [];

    if (_subgroupSize == 1) {
      // For Sample Size 1, calculate range for each individual point
      return List<double>.generate(
        widget.data.length,
            (i) => 0.0, // Range for individual points is 0
      );
    }

    final ranges = <double>[];
    final numberOfCompleteGroups = (widget.data.length / _subgroupSize).floor();

    for (var i = 0; i < numberOfCompleteGroups; i++) {
      final start = i * _subgroupSize;
      final end = start + _subgroupSize;
      final subgroup = widget.data.sublist(start, end);

      // Calculate range (max - min) for the subgroup
      final range = subgroup.reduce(max) - subgroup.reduce(min);
      ranges.add(range);
    }

    // Handle remaining points if they form a valid group
    final remainingStart = numberOfCompleteGroups * _subgroupSize;
    if (remainingStart < widget.data.length) {
      final remainingPoints = widget.data.sublist(remainingStart);
      if (remainingPoints.length >= 2) {
        final range = remainingPoints.reduce(max) - remainingPoints.reduce(min);
        ranges.add(range);
      }
    }

    return ranges;
  }
  Map<String, double> _calculateControlLimits() {
    if (_xBarValues.isEmpty) {
      return {
        'mean': 0.0,
        'ucl': 0.0,
        'lcl': 0.0,
      };
    }

    final xBarBar = _xBarValues.reduce((a, b) => a + b) / _xBarValues.length;
    final ranges = _calculateRanges();

    // Calculate standard deviation for sample size 1
    if (_subgroupSize == 1) {
      final sumSquaredDiff = _xBarValues.map((x) => pow(x - xBarBar, 2)).reduce((a, b) => a + b);
      final standardDev = sqrt(sumSquaredDiff / (_xBarValues.length - 1));

      return {
        'mean': xBarBar,
        'ucl': xBarBar + (3 * standardDev),
        'lcl': xBarBar - (3 * standardDev),
      };
    }

    if (ranges.isEmpty) {
      return {
        'mean': xBarBar,
        'ucl': xBarBar,
        'lcl': xBarBar,
      };
    }

    final rBar = ranges.reduce((a, b) => a + b) / ranges.length;
    final constants = _controlConstants[_subgroupSize]!;

    return {
      'mean': xBarBar,
      'ucl': xBarBar + (constants['a2']! * rBar),
      'lcl': xBarBar - (constants['a2']! * rBar),
    };
  }

  Widget _buildSubgroupSelector() {
    return Material(
      color: Colors.transparent,
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
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
                const SizedBox(width: 16),
                Text('XBar Chart UCL = X̄ + (A2 × R̄)'),
                const SizedBox(width: 16),
                Text('LCL = X̄ - (A2 × R̄)'),
                const SizedBox(width: 16),
                Text('R̄ = ${_rBar.toStringAsFixed(3)}'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticsPanel() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatisticItem(
                label: 'UCL',
                value: _limits['ucl']?.toStringAsFixed(3) ?? 'N/A',
                color: widget.controlLimitColor,
              ),
              const SizedBox(width: 16),
              _StatisticItem(
                label: 'X̄ (Mean)',
                value: _limits['mean']?.toStringAsFixed(3) ?? 'N/A',
                color: widget.centerLineColor,
              ),
              const SizedBox(width: 16),
              _StatisticItem(
                label: 'LCL',
                value: _limits['lcl']?.toStringAsFixed(3) ?? 'N/A',
                color: widget.controlLimitColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        children: [
          _LegendItem(
            label: 'X-bar Values',
            color: widget.lineColor,
          ),
          _LegendItem(
            label: 'Mean (X̿)',
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
        final allValues = [..._xBarValues, _limits['ucl'] ?? 0.0, _limits['lcl'] ?? 0.0];
        final minY = allValues.reduce(min);
        final maxY = allValues.reduce(max);
        final range = maxY - minY;
        final padding = range * 0.2; // Reduced padding

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
              minX: 0, // Changed from -0.5
              maxX: (_xBarValues.length - 1).toDouble(), // Changed from length - 0.5
              minY: minY - padding,
              maxY: maxY + padding,
              lineBarsData: [
                _buildDataLine(),
                _buildHorizontalLine(_limits['ucl'] ?? 0.0, widget.controlLimitColor, 'UCL'),
                _buildHorizontalLine(_limits['lcl'] ?? 0.0, widget.controlLimitColor, 'LCL'),
                _buildHorizontalLine(_limits['mean'] ?? 0.0, widget.centerLineColor, 'Mean'),
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
                      if (spot.x.toInt() < _xBarValues.length) {
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
            'X-bar Value',
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
            // Only show label if it's a valid index
            if (index >= 0 && index < _xBarValues.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'G${index + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,  // Made bold for better visibility
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
    final targetSteps = 6;
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
    // Ensure minimum interval is meaningful but not too small
    final minMeaningfulInterval = range / 50;  // Changed from 1000 to 100
    return max(result, minMeaningfulInterval);
  }
  LineChartBarData _buildDataLine() {
    return LineChartBarData(
      spots: List<FlSpot>.generate(
        _xBarValues.length,
            (i) => FlSpot(i.toDouble(), _xBarValues[i]),
      ),
      isCurved: false,
      color: widget.lineColor,
      barWidth: 2.5, // Increased line width
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 5, // Increased dot size
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
        FlSpot(0, y), // Changed from -0.5
        FlSpot((_xBarValues.length - 1).toDouble(), y), // Changed end point
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

    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: widget.height,
            maxHeight: widget.height,
          ),
          child: Card(
            elevation: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSubgroupSelector(),
                _buildStatisticsPanel(),
                _buildLegend(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 32, 32),
                    child: _buildChart(),
                  ),
                ),
              ],
            ),
          ),
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
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLine)
            Container(
              width: 24,
              height: 4,
              decoration: BoxDecoration(
                color: color,
                border: Border.all(color: color, width: 1),
              ),
              margin: const EdgeInsets.only(right: 8),
            )
          else
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withOpacity(0.8),
                  width: 1,
                ),
              ),
              margin: const EdgeInsets.only(right: 8),
            ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
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
                fontSize: 14,  // Increased font size
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 13,  // Increased font size
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}