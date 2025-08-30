import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/meter_reading.dart';
import '../models/bill.dart';
import 'database_service.dart';

class ExportService {
  static final ExportService _instance = ExportService._internal();
  factory ExportService() => _instance;
  ExportService._internal();

  final DatabaseService _dbService = DatabaseService();

  Future<String> _getTempFilePath(String fileName) async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/$fileName';
  }

  Future<void> shareFile(String filePath, String fileName) async {
    await Share.shareFiles([filePath], text: 'Exported $fileName');
  }

  Future<String> exportMeterReadings(
    String userId,
    String format, {
    DateTime? startDate,
    DateTime? endDate,
    Function(double)? onProgress,
  }) async {
    try {
      onProgress?.call(0.1);

      List<MeterReading> readings;
      if (startDate != null && endDate != null) {
        readings = await _dbService.getMeterReadingsByDateRange(userId, startDate, endDate);
      } else {
        readings = await _dbService.getMeterReadings(userId);
      }

      onProgress?.call(0.3);

      String fileName = 'meter_readings_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.$format';
      String filePath = await _getTempFilePath(fileName);

      switch (format.toLowerCase()) {
        case 'csv':
          await _exportMeterReadingsToCsv(readings, filePath);
          break;
        case 'pdf':
          await _exportMeterReadingsToPdf(readings, filePath);
          break;
        case 'json':
          await _exportMeterReadingsToJson(readings, filePath);
          break;
        default:
          throw Exception('Unsupported format: $format');
      }

      onProgress?.call(0.8);

      await shareFile(filePath, fileName);

      onProgress?.call(1.0);

      return filePath;
    } catch (e) {
      throw Exception('Failed to export meter readings: $e');
    }
  }

  Future<String> exportBills(
    String userId,
    String format, {
    DateTime? startDate,
    DateTime? endDate,
    Function(double)? onProgress,
  }) async {
    try {
      onProgress?.call(0.1);

      List<Bill> bills = await _dbService.getBills(userId);

      // Filter by date range if provided
      if (startDate != null && endDate != null) {
        bills = bills.where((bill) =>
          bill.generatedAt.isAfter(startDate.subtract(const Duration(days: 1))) &&
          bill.generatedAt.isBefore(endDate.add(const Duration(days: 1)))
        ).toList();
      }

      onProgress?.call(0.3);

      String fileName = 'bills_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.$format';
      String filePath = await _getTempFilePath(fileName);

      switch (format.toLowerCase()) {
        case 'csv':
          await _exportBillsToCsv(bills, filePath);
          break;
        case 'pdf':
          await _exportBillsToPdf(bills, filePath);
          break;
        case 'json':
          await _exportBillsToJson(bills, filePath);
          break;
        default:
          throw Exception('Unsupported format: $format');
      }

      onProgress?.call(0.8);

      await shareFile(filePath, fileName);

      onProgress?.call(1.0);

      return filePath;
    } catch (e) {
      throw Exception('Failed to export bills: $e');
    }
  }

  Future<String> exportReports(
    String userId,
    String format, {
    DateTime? startDate,
    DateTime? endDate,
    Function(double)? onProgress,
  }) async {
    try {
      onProgress?.call(0.1);

      List<MeterReading> readings;
      if (startDate != null && endDate != null) {
        readings = await _dbService.getMeterReadingsByDateRange(userId, startDate, endDate);
      } else {
        readings = await _dbService.getMeterReadings(userId);
      }

      List<Bill> bills = await _dbService.getBills(userId);

      onProgress?.call(0.3);

      // Generate summary report
      Map<String, dynamic> report = await _generateSummaryReport(readings, bills, startDate, endDate);

      onProgress?.call(0.5);

      String fileName = 'consumption_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.$format';
      String filePath = await _getTempFilePath(fileName);

      switch (format.toLowerCase()) {
        case 'csv':
          await _exportReportToCsv(report, filePath);
          break;
        case 'pdf':
          await _exportReportToPdf(report, filePath);
          break;
        case 'json':
          await _exportReportToJson(report, filePath);
          break;
        default:
          throw Exception('Unsupported format: $format');
      }

      onProgress?.call(0.8);

      await shareFile(filePath, fileName);

      onProgress?.call(1.0);

      return filePath;
    } catch (e) {
      throw Exception('Failed to export reports: $e');
    }
  }

  Future<Map<String, dynamic>> _generateSummaryReport(
    List<MeterReading> readings,
    List<Bill> bills,
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    double totalConsumption = readings.fold(0.0, (sum, reading) => sum + reading.consumption);
    double totalBillAmount = bills.fold(0.0, (sum, bill) => sum + bill.totalAmount);
    double averageConsumption = readings.isNotEmpty ? totalConsumption / readings.length : 0.0;
    double averageBillAmount = bills.isNotEmpty ? totalBillAmount / bills.length : 0.0;

    // Calculate monthly averages
    Map<String, double> monthlyConsumption = {};
    for (var reading in readings) {
      String monthKey = DateFormat('yyyy-MM').format(reading.date);
      monthlyConsumption[monthKey] = (monthlyConsumption[monthKey] ?? 0) + reading.consumption;
    }

    Map<String, double> monthlyBills = {};
    for (var bill in bills) {
      String monthKey = DateFormat('yyyy-MM').format(bill.generatedAt);
      monthlyBills[monthKey] = (monthlyBills[monthKey] ?? 0) + bill.totalAmount;
    }

    return {
      'summary': {
        'total_readings': readings.length,
        'total_bills': bills.length,
        'total_consumption_kwh': totalConsumption,
        'total_bill_amount': totalBillAmount,
        'average_consumption_per_reading': averageConsumption,
        'average_bill_amount': averageBillAmount,
        'date_range': {
          'start': startDate?.toIso8601String(),
          'end': endDate?.toIso8601String(),
        },
      },
      'monthly_consumption': monthlyConsumption,
      'monthly_bills': monthlyBills,
      'generated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _exportMeterReadingsToCsv(List<MeterReading> readings, String filePath) async {
    List<List<dynamic>> csvData = [
      ['ID', 'Date', 'Reading Value', 'Consumption (kWh)', 'Notes', 'Manual', 'Photo Path']
    ];

    for (var reading in readings) {
      csvData.add([
        reading.id,
        DateFormat('yyyy-MM-dd HH:mm:ss').format(reading.date),
        reading.readingValue,
        reading.consumption,
        reading.notes ?? '',
        reading.isManual ? 'Yes' : 'No',
        reading.photoPath ?? '',
      ]);
    }

    String csv = const ListToCsvConverter().convert(csvData);
    await File(filePath).writeAsString(csv);
  }

  Future<void> _exportMeterReadingsToPdf(List<MeterReading> readings, String filePath) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Header(text: 'Meter Readings Report'),
              pw.Table.fromTextArray(
                headers: ['Date', 'Reading Value', 'Consumption (kWh)', 'Notes'],
                data: readings.map((reading) => [
                  DateFormat('yyyy-MM-dd').format(reading.date),
                  reading.readingValue.toString(),
                  reading.consumption.toString(),
                  reading.notes ?? '',
                ]).toList(),
              ),
            ],
          );
        },
      ),
    );

    await File(filePath).writeAsBytes(await pdf.save());
  }

  Future<void> _exportMeterReadingsToJson(List<MeterReading> readings, String filePath) async {
    List<Map<String, dynamic>> jsonData = readings.map((reading) => reading.toJson()).toList();
    String json = jsonEncode(jsonData);
    await File(filePath).writeAsString(json);
  }

  Future<void> _exportBillsToCsv(List<Bill> bills, String filePath) async {
    List<List<dynamic>> csvData = [
      ['ID', 'Start Date', 'End Date', 'Total Units', 'Total Amount', 'Status', 'Generated At']
    ];

    for (var bill in bills) {
      csvData.add([
        bill.id,
        DateFormat('yyyy-MM-dd').format(bill.startDate),
        DateFormat('yyyy-MM-dd').format(bill.endDate),
        bill.totalUnits,
        bill.totalAmount,
        bill.status,
        DateFormat('yyyy-MM-dd HH:mm:ss').format(bill.generatedAt),
      ]);
    }

    String csv = const ListToCsvConverter().convert(csvData);
    await File(filePath).writeAsString(csv);
  }

  Future<void> _exportBillsToPdf(List<Bill> bills, String filePath) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Header(text: 'Bills Report'),
              pw.Table.fromTextArray(
                headers: ['Start Date', 'End Date', 'Total Units', 'Total Amount', 'Status'],
                data: bills.map((bill) => [
                  DateFormat('yyyy-MM-dd').format(bill.startDate),
                  DateFormat('yyyy-MM-dd').format(bill.endDate),
                  bill.totalUnits.toString(),
                  bill.totalAmount.toString(),
                  bill.status,
                ]).toList(),
              ),
            ],
          );
        },
      ),
    );

    await File(filePath).writeAsBytes(await pdf.save());
  }

  Future<void> _exportBillsToJson(List<Bill> bills, String filePath) async {
    List<Map<String, dynamic>> jsonData = bills.map((bill) => bill.toJson()).toList();
    String json = jsonEncode(jsonData);
    await File(filePath).writeAsString(json);
  }

  Future<void> _exportReportToCsv(Map<String, dynamic> report, String filePath) async {
    List<List<dynamic>> csvData = [
      ['Metric', 'Value'],
      ['Total Readings', report['summary']['total_readings']],
      ['Total Bills', report['summary']['total_bills']],
      ['Total Consumption (kWh)', report['summary']['total_consumption_kwh']],
      ['Total Bill Amount', report['summary']['total_bill_amount']],
      ['Average Consumption per Reading', report['summary']['average_consumption_per_reading']],
      ['Average Bill Amount', report['summary']['average_bill_amount']],
    ];

    String csv = const ListToCsvConverter().convert(csvData);
    await File(filePath).writeAsString(csv);
  }

  Future<void> _exportReportToPdf(Map<String, dynamic> report, String filePath) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Header(text: 'Consumption Report'),
              pw.Text('Summary Statistics'),
              pw.Bullet(text: 'Total Readings: ${report['summary']['total_readings']}'),
              pw.Bullet(text: 'Total Bills: ${report['summary']['total_bills']}'),
              pw.Bullet(text: 'Total Consumption: ${report['summary']['total_consumption_kwh']} kWh'),
              pw.Bullet(text: 'Total Bill Amount: ${report['summary']['total_bill_amount']}'),
              pw.Bullet(text: 'Average Consumption per Reading: ${report['summary']['average_consumption_per_reading']}'),
              pw.Bullet(text: 'Average Bill Amount: ${report['summary']['average_bill_amount']}'),
            ],
          );
        },
      ),
    );

    await File(filePath).writeAsBytes(await pdf.save());
  }

  Future<void> _exportReportToJson(Map<String, dynamic> report, String filePath) async {
    String json = jsonEncode(report);
    await File(filePath).writeAsString(json);
  }
}