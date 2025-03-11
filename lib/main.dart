import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:html' as html;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:spc_app/histogram_util.dart';
import 'package:spc_app/spc_utils.dart';
import 'Xbar_utils.dart';
import 'package:pdf/pdf.dart';
import 'dart:async';
import 'package:spc_app/widgets/loading_overlay.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

void main() {
  runApp(ChangeNotifierProvider(
    create: (context) => SPCModel(),
    child: SPCApp(),
  ));
}

class PlatformPdfExport {
  static Future<void> exportToPDF({
    required pw.Document pdf,
    required String fileName,
    required BuildContext context,
    Function(double)? onProgress,
    Function(String)? onSuccess,
    Function(String)? onError,
  }) async {
    // Create progress controller
    final progressController = StreamController<double>();

    // Show loading overlay with progress
    OverlayEntry? loadingOverlay;
    loadingOverlay = OverlayEntry(
      builder: (context) => LoadingProgressOverlay(
        progressController: progressController,
      ),
    );

    try {
      Overlay.of(context).insert(loadingOverlay);

      // Update progress
      progressController.add(0.2);

      if (kIsWeb) {
        // Web implementation with progress
        final bytes = await compute((_) => pdf.save(), null);
        progressController.add(0.6);

        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);

        progressController.add(0.8);

        html.Url.revokeObjectUrl(url);
        progressController.add(1.0);

        if (onSuccess != null) onSuccess('PDF downloaded successfully');
      } else {
        // Mobile implementation with progress
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);

        progressController.add(0.4);
        final bytes = await compute((_) => pdf.save(), null);
        progressController.add(0.7);

        await file.writeAsBytes(bytes);
        progressController.add(0.9);

        await Share.shareXFiles([XFile(filePath)], text: 'SPC Report');
        progressController.add(1.0);

        if (onSuccess != null) onSuccess('PDF shared successfully');
      }
    } catch (e) {
      if (onError != null) onError('Error generating PDF: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 500));
      loadingOverlay.remove();
      await progressController.close();
    }
  }
}

class SPCApp extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPC App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        textTheme: GoogleFonts.latoTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        textTheme: GoogleFonts.latoTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      home: HomePage(),
      routes: {
        '/about': (context) => AboutPage(),
        '/chart': (context) => ChartPage(),
      },
    );
  }
}
class ThreeSAnalysis {
  final bool processShift;
  final bool processSpread;
  final String specialCauseStatus;

  ThreeSAnalysis({
    required this.processShift,
    required this.processSpread,
    required this.specialCauseStatus
  });
}

class SPCModel extends ChangeNotifier {
  String? jsonData;
  ThreeSAnalysis? threeSAnalysis;
  Set<int> selectedShifts = {1};
  int sampleSize = 1;
  String selectedPart = 'Part A1';
  DateTime? startDate;
  DateTime? endDate;
  bool _disposed = false;
  bool isLoading = false;
  List<Map<String, dynamic>> filteredData = [];
  SPCMetics? spcMetrics;
  String chartType = 'LineChart';
  Map<String, double> chartAxes = {'min': 0.0, 'max': 10.0};
  int currentTabIndex = 0; // Add this to track current tab
  Uint8List? _cachedChartImage;
  bool _isExporting = false;

  @override
  void dispose() {
    clearCache();
    _disposed = true;
    super.dispose();
  }

  void updateState() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void setCurrentTab(int index) {
    currentTabIndex = index;
    updateState();
  }

  Future<void> calculateThreeSAnalysis(List<Map<String, dynamic>> data) async {
    final xBar = calculateMean(data.map((item) => item['Data'] as double).toList());
    final stdevOverall = calculateStdevOverall(data.map((item) => item['Data'] as double).toList());

    final ucl = xBar + 3 * stdevOverall;
    final lcl = xBar - 3 * stdevOverall;

    bool hasProcessShift = checkProcessShift(data, xBar);
    bool hasProcessSpread = checkProcessSpread(data);
    String specialCauseStatus = detectSpecialCauses(data, ucl, lcl, xBar, stdevOverall);

    threeSAnalysis = ThreeSAnalysis(
        processShift: hasProcessShift,
        processSpread: hasProcessSpread,
        specialCauseStatus: specialCauseStatus
    );

    notifyListeners();
  }

  Future<void> uploadJSONFile(BuildContext context) async {
    isLoading = true;
    updateState();
    try {
      final XTypeGroup typeGroup = XTypeGroup(
        label: 'JSON Files',
        extensions: ['json'],
      );
      final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        jsonData = await file.readAsString();
        await processJSONData(jsonData!, context: context);
      }
    } catch (e) {
      showErrorDialog(context, 'Error uploading file: $e');
    } finally {
      isLoading = false;
      updateState();
    }
  }

  Future<void> processJSONData(String jsonData, {required BuildContext context}) async {
    try {
      final data = json.decode(jsonData);
      if (data is! Map || !data.containsKey('data')) {
        throw FormatException('Invalid JSON format');
      }

      if (startDate == null || endDate == null) {
        throw Exception('Please select both start and end dates.');
      }

      final List<Map<String, dynamic>> dataList = List<Map<String, dynamic>>.from(data["data"]);
      filteredData.clear();

      for (int shift in selectedShifts) {
        final shiftData = dataList.where((item) {
          if (!item.containsKey("Date") || !item.containsKey("Shift")) {
            return false;
          }

          try {
            final date = DateTime.parse(item["Date"]);
            final itemShift = item["Shift"];

            if (itemShift is! int) {
              return false;
            }

            return itemShift == shift &&
                !date.isBefore(startDate!) &&
                !date.isAfter(endDate!);
          } catch (e) {
            return false;
          }
        }).toList();
        filteredData.addAll(shiftData);
      }

      filteredData = filteredData.map((item) {
        item['Data'] = double.tryParse(item['Data'].toString()) ?? 0.0;
        return item;
      }).toList();

      filteredData.sort((a, b) => DateTime.parse(a['Date']).compareTo(DateTime.parse(b['Date'])));

      if (filteredData.isEmpty) {
        throw Exception('No data found for the selected date range and shifts.');
      }

      await calculateSPCMetrics(filteredData);
      await calculateThreeSAnalysis(filteredData);

      // Show success dialog
      if (!_disposed) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 50),
                  SizedBox(height: 10),
                  Text(
                    'Success!',
                    style: TextStyle(color: Colors.green),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'JSON data processed successfully!',
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'View the analysis results in the Charts tab.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: Text('View Charts'),
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pushNamed(context, '/chart'); // Navigate to charts page
                  },
                ),
                TextButton(
                  child: Text('Stay Here'),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      showErrorDialog(context, 'Error processing JSON: ${e.toString()}');
    }
  }

  Future<void> calculateSPCMetrics(List<Map<String, dynamic>> jsonData) async {
    final dataValues = jsonData.map((item) => item["Data"] as double).toList();
    final movingRanges = _calculateMovingRanges(dataValues);

    if (dataValues.isEmpty) {
      throw Exception('No valid data found for calculations.');
    }

    final usl = 40.04;
    final lsl = 40.00;
    final unbiasedConstants = getUnbiasedConstants(sampleSize);

    final xBar = calculateMean(dataValues);
    final rBar = calculateMean(movingRanges);

    final d2 = unbiasedConstants["D2"]!;
    final stdevWithin = rBar / d2;
    final stdevOverall = calculateStdevOverall(dataValues);

    final cp = (usl - lsl) / (6 * stdevWithin);
    final cpku = (usl - xBar) / (3 * stdevWithin);
    final cpkl = (xBar - lsl) / (3 * stdevWithin);
    final cpk = min(cpku, cpkl);

    final pp = (usl - lsl) / (6 * stdevOverall);
    final ppu = (usl - xBar) / (3 * stdevOverall);
    final ppl = (xBar - lsl) / (3 * stdevOverall);
    final ppk = min(ppu, ppl);

    spcMetrics = SPCMetics(
      xBar: xBar,
      stdevOverall: stdevOverall,
      pp: pp,
      ppu: ppu,
      ppl: ppl,
      ppk: ppk,
      rbar: rBar,
      stdevWithin: stdevWithin,
      cp: cp,
      cpku: cpku,
      cpkl: cpkl,
      cpk: cpk,
    );
    notifyListeners();
  }

  // Helper methods remain the same
  bool checkProcessShift(List<Map<String, dynamic>> data, double centerline) {
    int consecutiveCount = 0;
    bool? lastAbove;

    for (var point in data) {
      double value = point['Data'];
      bool isAbove = value > centerline;

      if (lastAbove == null) {
        lastAbove = isAbove;
        consecutiveCount = 1;
      } else if (isAbove == lastAbove) {
        consecutiveCount++;
        if (consecutiveCount >= 7) return true;
      } else {
        lastAbove = isAbove;
        consecutiveCount = 1;
      }
    }
    return false;
  }

  bool checkProcessSpread(List<Map<String, dynamic>> data) {
    int trendCount = 0;
    bool? increasing;

    for (int i = 1; i < data.length; i++) {
      double current = data[i]['Data'];
      double previous = data[i-1]['Data'];
      bool isIncreasing = current > previous;

      if (increasing == null) {
        increasing = isIncreasing;
        trendCount = 1;
      } else if (isIncreasing == increasing) {
        trendCount++;
        if (trendCount >= 7) return true;
      } else {
        increasing = isIncreasing;
        trendCount = 1;
      }
    }
    return false;
  }

  String detectSpecialCauses(List<Map<String, dynamic>> data, double ucl, double lcl, double centerline, double stdev) {
    bool hasOutliers = data.any((point) {
      double value = point['Data'];
      return value > ucl || value < lcl;
    });

    bool hasZoneAViolation = checkZoneViolation(data, centerline, stdev, 2, 3, 2);
    bool hasZoneBViolation = checkZoneViolation(data, centerline, stdev, 4, 5, 1);

    if (hasOutliers || hasZoneAViolation || hasZoneBViolation) {
      return "Special Cause Detected";
    }
    return "No Special Cause";
  }

  bool checkZoneViolation(List<Map<String, dynamic>> data, double centerline, double stdev,
      int requiredPoints, int windowSize, double sigmaLevel) {
    for (int i = 0; i <= data.length - windowSize; i++) {
      int pointsInZone = 0;
      for (int j = 0; j < windowSize; j++) {
        double value = data[i + j]['Data'];
        double distanceFromCenter = (value - centerline).abs();
        if (distanceFromCenter > sigmaLevel * stdev) {
          pointsInZone++;
        }
      }
      if (pointsInZone >= requiredPoints) return true;
    }
    return false;
  }

  double calculateMean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  List<double> _calculateMovingRanges(List<double> values) {
    List<double> ranges = [];
    for (int i = 1; i < values.length; i++) {
      ranges.add((values[i] - values[i-1]).abs());
    }
    return ranges;
  }

  double calculateStdevOverall(List<double> values) {
    if (values.isEmpty) return 0;
    double mean = calculateMean(values);
    double sumSquaredDiff = values.fold(0, (sum, value) => sum + pow(value - mean, 2));
    return sqrt(sumSquaredDiff / (values.length - 1));
  }

  Map<String, num> getUnbiasedConstants(int n) {
    final constants = {
      1: {"D2": 1.128, "D3": 0, "D4": 3.267},
      2: {"D2": 1.128, "D3": 0, "D4": 3.267},
      3: {"D2": 1.693, "D3": 0, "D4": 2.574},
      4: {"D2": 2.059, "D3": 0, "D4": 2.282},
      5: {"D2": 2.326, "D3": 0, "D4": 2.114}
    };
    return constants[n] ?? constants[1]!;
  }

  void showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // State management methods
  void setSampleSize(int size) {
    sampleSize = size;
    updateState();
  }

  void setSelectedPart(String part) {
    selectedPart = part;
    updateState();
  }

  void setStartDate(DateTime? date) {
    startDate = date;
    updateState();
  }

  void setEndDate(DateTime? date) {
    endDate = date;
    updateState();
  }

  void updateChartType(String type) {
    chartType = type;
    updateState();
  }

  void updateChartAxes(Map<String, double> axes) {
    chartAxes = axes;
    updateState();
  }

  void resetData() {
    filteredData = [];
    spcMetrics = null;
    updateState();
  }

  void toggleShift(int shift, BuildContext context) {
    if (selectedShifts.contains(shift)) {
      if (selectedShifts.length > 1) {
        selectedShifts.remove(shift);
      }
    } else {
      selectedShifts.add(shift);
    }

    if (filteredData.isNotEmpty && jsonData != null) {
      processJSONData(jsonData!, context: context);
    }
    updateState();
  }

  Future<void> exportToPDF(BuildContext context, {bool showFeedback = true}) async {
    if (_isExporting) return;
    _isExporting = true;

    try {
      // Create progress controller
      final progressController = StreamController<double>();

      // Show loading overlay with progress
      final loadingOverlay = OverlayEntry(
        builder: (context) => LoadingProgressOverlay(
          progressController: progressController,
        ),
      );

      if (context.mounted) {
        Overlay.of(context).insert(loadingOverlay);
      }

      try {
        // Update progress for chart preparation
        progressController.add(0.1);

        // Prepare charts in sequence to avoid memory issues
        final xbarBytes = await _prepareChart(
          context,
          SPCXbarChartWidget(
            data: filteredData.map((item) => item['Data'] as double).toList(),
          ),
        );
        progressController.add(0.3);

        final rbarBytes = await _prepareChart(
          context,
          SPCRChartWidget(
            data: filteredData.map((item) => item['Data'] as double).toList(),
          ),
        );
        progressController.add(0.5);

        final histogramBytes = await _prepareChart(
          context,
          HistogramWidget(
            data: filteredData.map((item) => item['Data'] as double).toList(),
            lsl: 40.000,
            usl: 40.045,
            target: 40.025,
          ),
        );
        progressController.add(0.7);

        // Create PDF document in isolate
        final pdf = await compute(_createPDFDocument, {
          'xbarBytes': xbarBytes,
          'rbarBytes': rbarBytes,
          'histogramBytes': histogramBytes,
          'metrics': spcMetrics,
          'analysis': threeSAnalysis,
        });

        progressController.add(0.8);

        // Export PDF using platform-specific implementation
        if (context.mounted) {
          await PlatformPdfExport.exportToPDF(
            pdf: pdf,
            fileName: 'spc_report.pdf',
            context: context,
            onProgress: (progress) {
              progressController.add(0.8 + (progress * 0.2)); // Scale remaining 20%
            },
            onSuccess: (message) {
              if (showFeedback) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(message)),
                );
              }
            },
            onError: (error) {
              if (showFeedback) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error)),
                );
              }
            },
          );
        }
      } finally {
        // Ensure overlay is removed and controller is closed
        await Future.delayed(const Duration(milliseconds: 500));
        loadingOverlay.remove();
        await progressController.close();
      }
    } catch (e) {
      if (context.mounted && showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: ${e.toString()}')),
        );
      }
    } finally {
      _isExporting = false;
    }
  }

  Future<Uint8List> _prepareChart(BuildContext context, Widget chart) async {
    final key = GlobalKey();

    // Create a layout that forces the chart to fit within bounds
    final chartWidget = RepaintBoundary(
      key: key,
      child: Material(
        child: Container(
          width: 1200,
          height: 800,  // Increased height further
          color: Colors.white,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: Container(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: 1200,
                        height: 800,
                        child: chart,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final overlayEntry = OverlayEntry(
      builder: (buildContext) => Positioned(
        left: -99999,
        child: SizedBox(
          width: 1200,
          height: 800,
          child: chartWidget,
        ),
      ),
    );

    try {
      if (context.mounted) {
        Overlay.of(context).insert(overlayEntry);

        // Increased delay to ensure complete rendering
        await Future.delayed(const Duration(milliseconds: 800));

        final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) {
          throw Exception('Failed to get render boundary');
        }

        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

        if (byteData == null) {
          throw Exception('Failed to get image data');
        }

        return byteData.buffer.asUint8List();
      } else {
        throw Exception('Context is not mounted');
      }
    } catch (e) {
      print('Error capturing chart: $e');
      rethrow;
    } finally {
      overlayEntry.remove();
    }
  }

  static Future<pw.Document> _createPDFDocument(Map<String, dynamic> params) async {
    final pdf = pw.Document(
      compress: true,
      version: PdfVersion.pdf_1_5,
      pageMode: PdfPageMode.fullscreen,  // Added for better viewing
    );

    // Add metrics and analysis page
    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(40),  // Increased margin
        build: (pw.Context context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('SPC Metrics Report',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              _buildMetricsTable(params['metrics'] as SPCMetics),
              pw.SizedBox(height: 30),
              pw.Text('3S Analysis Results',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              _buildAnalysisTable(params['analysis'] as ThreeSAnalysis),
            ],
          ),
        ],
      ),
    );

    // Add chart pages with increased margins and size
    for (var chartData in [
      {'title': 'X-Bar Chart', 'bytes': params['xbarBytes']},
      {'title': 'R-Bar Chart', 'bytes': params['rbarBytes']},
      {'title': 'Histogram', 'bytes': params['histogramBytes']},
    ]) {
      pdf.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(40),
          build: (context) => _createChartPage(
            chartData['title'] as String,
            chartData['bytes'] as Uint8List,
          ),
        ),
      );
    }

    return pdf;
  }

  static pw.Widget _buildMetricsTable(SPCMetics metrics) {
    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        pw.TableRow(
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.all(8),
              child: pw.Text(
                'Metric',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(8),
              child: pw.Text(
                'Value',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
        _buildTableRow('X-Bar (Mean)', metrics.xBar),
        _buildTableRow('Standard Deviation (Overall)', metrics.stdevOverall),
        _buildTableRow('Standard Deviation (Within)', metrics.stdevWithin),
        _buildTableRow('Moving Range (R-bar)', metrics.rbar),
        _buildTableRow('Cp', metrics.cp),
        _buildTableRow('Cpk', metrics.cpk),
        _buildTableRow('Pp', metrics.pp),
        _buildTableRow('Ppk', metrics.ppk),
      ],
    );
  }

  static pw.Widget _buildAnalysisTable(ThreeSAnalysis analysis) {
    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        pw.TableRow(
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.all(8),
              child: pw.Text(
                'Analysis Type',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(8),
              child: pw.Text(
                'Status',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
        _buildTableRow('Process Shift', analysis.processShift ? 'Detected' : 'Not Detected'),
        _buildTableRow('Process Spread', analysis.processSpread ? 'Detected' : 'Not Detected'),
        _buildTableRow('Special Cause Status', analysis.specialCauseStatus),
      ],
    );
  }

  static pw.TableRow _buildTableRow(String label, dynamic value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: pw.EdgeInsets.all(8),
          child: pw.Text(label),
        ),
        pw.Padding(
          padding: pw.EdgeInsets.all(8),
          child: pw.Text(
            value is double ? value.toStringAsFixed(4) : value.toString(),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> calculateRBarChartData(List<Map<String, dynamic>> data) {
    final List<Map<String, dynamic>> rBarData = [];
    int subgroupSize = sampleSize;

    for (int i = 0; i < data.length; i += subgroupSize) {
      List<double> subgroup = [];
      for (int j = 0; j < subgroupSize && i + j < data.length; j++) {
        subgroup.add(data[i + j]['Data']);
      }

      if (subgroup.length > 0) {
        double sum = subgroup.reduce((a, b) => a + b);
        double mean = sum / subgroup.length;
        rBarData.add({'Index': rBarData.length + 1, 'Mean': mean});
      }
    }

    return rBarData;
  }

  Future<Uint8List> captureChart(GlobalKey chartKey) async {
    if (_cachedChartImage != null) return _cachedChartImage!;

    _cachedChartImage = await ChartCapture.captureChart(chartKey);
    return _cachedChartImage!;
  }

  void clearCache() {
    _cachedChartImage = null;
  }

  static pw.Widget _createChartPage(String title, Uint8List chartBytes) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 20),
        pw.Center(
          child: pw.Container(
            width: 550,
            height: 500,  // Increased height
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            padding: const pw.EdgeInsets.all(20),
            child: pw.Center(
              child: pw.Image(
                pw.MemoryImage(chartBytes),
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ChartCapture {
  static Future<Uint8List> captureChart(GlobalKey key, {double pixelRatio = 2.0}) async {
    try {
      return await compute(_captureChartInIsolate, {
        'key': key,
        'pixelRatio': pixelRatio,
      });
    } catch (e) {
      throw Exception('Failed to capture chart: $e');
    }
  }

  static Future<Uint8List> _captureChartInIsolate(Map<String, dynamic> params) async {
    final key = params['key'] as GlobalKey;
    final pixelRatio = params['pixelRatio'] as double;

    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List() ?? Uint8List(0);
  }
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final model = Provider.of<SPCModel>(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue[100]!, Colors.blue[50]!],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                backgroundColor: Colors.white,
                elevation: 2,
                title: Row(
                  children: [
                    Icon(Icons.analytics, color: Colors.blue[700], size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Online SPC',
                      style: GoogleFonts.lato(
                        textStyle: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: Icon(Icons.help_outline, color: Colors.blue[700]),
                    onPressed: () {
                      // Show help dialog
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.logout, color: Colors.blue[700]),
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, 'login');
                    },
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildForm(model, context),
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Upload data to view SPC chart',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Chart'),
          BottomNavigationBarItem(icon: Icon(Icons.info), label: 'About'),
        ],
        currentIndex: 0,
        onTap: (index) {
          if (index == 2) {
            Navigator.pushNamed(context, '/about');
          } else if (index == 1) {
            Navigator.pushNamed(context, '/chart');
          }
        },
        selectedItemColor: Colors.blue[700],
        unselectedItemColor: Colors.grey[600],
        showUnselectedLabels: true,
        elevation: 8,
      ),
    );
  }

  Widget _buildForm(SPCModel model, BuildContext context) {
    return Container(
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildShiftCheckboxes(model, context),
            _buildDropdownField(
              label: 'Sample Size',
              value: model.sampleSize,
              items: [1, 2, 3, 4, 5],
              onChanged: (value) => model.sampleSize = value,
              icon: Icons.format_list_numbered,
              context: context,
            ),
            _buildDropdownField(
              label: 'Part Name',
              value: model.selectedPart,
              items: ['Part A1', 'Part A2', 'Part A3', 'Part B1', 'Part B2', 'Part C1', 'Part C2', 'Part D1', 'Part D2'],
              onChanged: (value) => model.selectedPart = value,
              icon: Icons.category,
              context: context,
            ),
            SizedBox(height: 8),
            _buildDateField('Start Date', model.startDate, () => model.pickStartDate(context)),
            _buildDateField('End Date', model.endDate, () => model.pickEndDate(context)),
            SizedBox(height: 24),
            ElevatedButton.icon(
              icon: Icon(Icons.upload_file),
              label: model.isLoading
                  ? SpinKitFadingCircle(color: Colors.white, size: 18)
                  : Text(
                'Upload JSON File',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              onPressed: () => model.uploadJSONFile(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftCheckboxes(SPCModel model, BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {},
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shift',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    Checkbox(
                      value: model.selectedShifts.contains(1),
                      onChanged: (bool? value) {
                        model.toggleShift(1,context);
                      },
                    ),
                    Text('Shift 1'),
                  ],
                ),
                Row(
                  children: [
                    Checkbox(
                      value: model.selectedShifts.contains(2),
                      onChanged: (bool? value) {
                        model.toggleShift(2,context);
                      },
                    ),
                    Text('Shift 2'),
                  ],
                ),
                Row(
                  children: [
                    Checkbox(
                      value: model.selectedShifts.contains(3),
                      onChanged: (bool? value) {
                        model.toggleShift(3,context);
                      },
                    ),
                    Text('Shift 3'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required dynamic value,
    required List<dynamic> items,
    required Function(dynamic) onChanged,
    required IconData icon,
    required BuildContext context,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {},
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: Colors.blue[700], size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      DropdownButton<dynamic>(
                        value: value,
                        isExpanded: true,
                        underline: SizedBox(),
                        icon: Icon(Icons.arrow_drop_down, color: Colors.blue[700]),
                        items: items.map((item) => DropdownMenuItem(
                          value: item,
                          child: Text(
                            item.toString(),
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )).toList(),
                        onChanged: (value) {
                          onChanged(value);
                          Provider.of<SPCModel>(context, listen: false). updateState();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateField(String label, DateTime? date, Function() onTap) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.blue[700], size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        date == null ? 'Select Date' : '${date.toLocal()}'.split(' ')[0],
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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

extension SPCModelExtensions on SPCModel {
  Future<void> pickStartDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      startDate = picked;
      updateState();
    }
  }

  Future<void> pickEndDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: endDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      endDate = picked;
      updateState();
    }
  }
}

class AboutPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('About')),
      body: Center(
        child: Text(
          'Zanvar Groups, Kolhapur: A premier institution in Industrial services.',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
class ChartPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final model = Provider.of<SPCModel>(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('SPC Metrics Chart'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (BuildContext context) {
                  return Container(
                    height: 300,
                    child: Column(
                      children: [
                        ListTile(
                          title: Text('Chart Type'),
                          trailing: DropdownButton<String>(
                            value: model.chartType,
                            onChanged: (value) => model.updateChartType(value!),
                            items: ['LineChart', 'BarChart'].map((
                                String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                          ),
                        ),
                        ListTile(
                          title: Text('Chart Axes'),
                          subtitle: Text(
                              'Min: ${model.chartAxes['min']}, Max: ${model
                                  .chartAxes['max']}'),
                          trailing: IconButton(
                            icon: Icon(Icons.edit),
                            onPressed: () {
                              // Implement axis customization logic here
                              model.updateChartAxes(
                                  {'min': 0.0, 'max': 10.0}); // Example
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.download),
            onPressed: () {
              model.exportToPDF(context);
            },
          ),
        ],
      ),
      body: model.spcMetrics == null
          ? Center(child: Text('No data available. Please upload a JSON file.'))
          : Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              DataTable(
                columns: [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Shift')),
                  DataColumn(label: Text('Data')),
                  DataColumn(label: Text('Moving Range R')),
                ],
                rows: model.filteredData.map((row) {
                  return DataRow(cells: [
                    DataCell(Text(row['Date'])),
                    DataCell(Text(row['Shift'].toString())),
                    DataCell(Text(row['Data'].toString())),
                    DataCell(Text(row['Moving Range R'].toString())),
                  ]);
                }).toList(),
              ),
              _buildMetricCard(
                title: 'Process Location',
                metrics: [
                  {
                    'label': 'X-Bar (Mean)',
                    'value': model.spcMetrics!.xBar.toStringAsFixed(4)
                  },
                ],
              ),
              _buildMetricCard(
                title: 'Variation Metrics',
                metrics: [
                  {
                    'label': 'Standard Deviation (Overall)',
                    'value': model.spcMetrics!.stdevOverall.toStringAsFixed(4)
                  },
                  {
                    'label': 'Standard Deviation (Within)',
                    'value': model.spcMetrics!.stdevWithin.toStringAsFixed(4)
                  },
                  {
                    'label': 'Moving Range (R-bar)',
                    'value': model.spcMetrics!.rbar.toStringAsFixed(4)
                  },
                ],
              ),
              _buildMetricCard(
                title: 'Process Capability (Short-term)',
                metrics: [
                  {
                    'label': 'Cp',
                    'value': model.spcMetrics!.cp.toStringAsFixed(4)
                  },
                  {
                    'label': 'Cpk Upper',
                    'value': model.spcMetrics!.cpku.toStringAsFixed(4)
                  },
                  {
                    'label': 'Cpk Lower',
                    'value': model.spcMetrics!.cpkl.toStringAsFixed(4)
                  },
                  {
                    'label': 'Cpk',
                    'value': model.spcMetrics!.cpk.toStringAsFixed(4)
                  },
                ],
              ),
              _buildMetricCard(
                title: 'Process Performance (Long-term)',
                metrics: [
                  {
                    'label': 'Pp',
                    'value': model.spcMetrics!.pp.toStringAsFixed(4)
                  },
                  {
                    'label': 'Ppu',
                    'value': model.spcMetrics!.ppu.toStringAsFixed(4)
                  },
                  {
                    'label': 'Ppl',
                    'value': model.spcMetrics!.ppl.toStringAsFixed(4)
                  },
                  {
                    'label': 'Ppk',
                    'value': model.spcMetrics!.ppk.toStringAsFixed(4)
                  },
                ],
              ),
              _build3SAnalysis(model),
              SizedBox(height: 20),
              _buildProcessInterpretation(
                  model.spcMetrics!.cp, model.spcMetrics!.cpk,
                  model.spcMetrics!.pp, model.spcMetrics!.ppk),
              SizedBox(height: 20),
              SPCRChartWidget(
                  data: model.filteredData.map((item) => item['Data'] as double)
                      .toList()),
              SizedBox(height: 20),
              SPCXbarChartWidget(
                data: model.filteredData.map((item) => item['Data'] as double).toList(),
              ),
              SizedBox(height: 20),
              HistogramWidget(
                data: model.filteredData.map((item) => item['Data'] as double)
                    .toList(),
                lsl: 40.000,
                // Your Lower Specification Limit
                usl: 40.045,
                // Your Upper Specification Limit
                target: 40.025,),
              // Histogram
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pop(context);
          Navigator.pushNamed(context, '/');
        },
        child: Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildMetricCard(
      {required String title, required List<Map<String, String>> metrics}) {
    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            SizedBox(height: 10),
            ...metrics.map((metric) =>
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        metric['label']!,
                        style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                      ),
                      Text(
                        metric['value']!,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _build3SAnalysis(SPCModel model) {
    if (model.threeSAnalysis == null) return SizedBox.shrink();

    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '3S Analysis',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            SizedBox(height: 10),
            _build3SRow(
              'Process Shift',
              model.threeSAnalysis!.processShift ? 'Yes' : 'No',
              model.threeSAnalysis!.processShift ? Colors.red : Colors.green,
            ),
            _build3SRow(
              'Process Spread',
              model.threeSAnalysis!.processSpread ? 'Yes' : 'No',
              model.threeSAnalysis!.processSpread ? Colors.red : Colors.green,
            ),
            _build3SRow(
              'Special Cause',
              model.threeSAnalysis!.specialCauseStatus,
              model.threeSAnalysis!.specialCauseStatus == 'No Special Cause'
                  ? Colors.green
                  : Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _build3SRow(String label, String status, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 16, color: Colors.grey[800]),
          ),
          Text(
            status,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessInterpretation(double cp, double cpk, double pp,
      double ppk) {
    String getProcessStatus(double cpk) {
      if (cpk >= 1.67) return "Process Excellent";
      if (cpk >= 1.45) return "Process is more capable";
      if (cpk >= 1.33) return "Process is capable";
      if (cpk >= 1.00) return "Process is slightly capable";
      return "Stop Process change";
    }

    Color getStatusColor(String status) {
      switch (status) {
        case 'Excellent':
          return Colors.green;
        case 'Good':
          return Colors.blue;
        case 'Marginal':
          return Colors.orange;
        default:
          return Colors.red;
      }
    }

    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Process Interpretation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            SizedBox(height: 10),
            _buildInterpretationRow(
              'Short-term Capability (Cp)',
              getProcessStatus(cp),
              getStatusColor(getProcessStatus(cp)),
            ),
            _buildInterpretationRow(
              'Short-term Centered (Cpk)',
              getProcessStatus(cpk),
              getStatusColor(getProcessStatus(cpk)),
            ),
            _buildInterpretationRow(
              'Long-term Performance (Pp)',
              getProcessStatus(pp),
              getStatusColor(getProcessStatus(pp)),
            ),
            _buildInterpretationRow(
              'Long-term Centered (Ppk)',
              getProcessStatus(ppk),
              getStatusColor(getProcessStatus(ppk)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterpretationRow(String label, String status, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 16, color: Colors.grey[800]),
          ),
          Text(
            status,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class SPCMetics {
  final double xBar;
  final double stdevOverall;
  final double pp;
  final double ppu;
  final double ppl;
  final double ppk;
  final double rbar;
  final double stdevWithin;
  final double cp;
  final double cpku;
  final double cpkl;
  final double cpk;

  SPCMetics({
    required this.xBar,
    required this.stdevOverall,
    required this.pp,
    required this.ppu,
    required this.ppl,
    required this.ppk,
    required this.rbar,
    required this.stdevWithin,
    required this.cp,
    required this.cpku,
    required this.cpkl,
    required this.cpk,
  });
}