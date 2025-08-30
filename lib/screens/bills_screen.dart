import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../models/bill.dart';
import '../models/meter_reading.dart';
import '../models/pricing_tier.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isGeneratingBill = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _checkAndGenerateBill();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkAndGenerateBill() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);

    if (authProvider.currentUser == null) return;

    final now = DateTime.now();
    final isOddMonth = [1, 3, 5, 7, 9, 11].contains(now.month);
    final isFirstOfMonth = now.day == 1;

    if (isOddMonth && isFirstOfMonth) {
      await _generateAutomaticBill(authProvider.currentUser!.id, databaseProvider);
    }
  }

  Future<void> _generateAutomaticBill(String userId, DatabaseProvider databaseProvider) async {
    setState(() => _isGeneratingBill = true);

    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 1, 1);
      final endDate = DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));

      // Check if bill already exists for this period
      final existingBills = await databaseProvider.getBillsByUserId(userId);
      final billExists = existingBills.any((bill) =>
        bill.startDate.year == startDate.year &&
        bill.startDate.month == startDate.month &&
        bill.endDate.year == endDate.year &&
        bill.endDate.month == endDate.month
      );

      if (!billExists) {
        final totalAmount = await databaseProvider.calculateBillAmount(userId, startDate, endDate);
        final readings = await databaseProvider.getMeterReadingsByDateRange(userId, startDate, endDate);
        final totalUnits = readings.fold(0.0, (sum, reading) => sum + reading.consumption);

        final bill = Bill(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          userId: userId,
          startDate: startDate,
          endDate: endDate,
          totalUnits: totalUnits,
          totalAmount: totalAmount,
          status: 'unpaid',
          generatedAt: DateTime.now(),
        );

        await databaseProvider.addBill(bill);
        await databaseProvider.loadBills(userId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Automatic bill generated for previous month')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating bill: $e')),
        );
      }
    } finally {
      setState(() => _isGeneratingBill = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final databaseProvider = Provider.of<DatabaseProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills & Reports'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Bills', icon: Icon(Icons.receipt)),
            Tab(text: 'Reports', icon: Icon(Icons.analytics)),
            Tab(text: 'Savings', icon: Icon(Icons.savings)),
            Tab(text: 'History', icon: Icon(Icons.history)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _checkAndGenerateBill(),
            tooltip: 'Generate Bill',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _showExportDialog,
            tooltip: 'Export Bills',
          ),
        ],
      ),
      body: _isGeneratingBill
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(
            controller: _tabController,
            children: [
              _buildBillsTab(databaseProvider),
              _buildReportsTab(databaseProvider),
              _buildSavingsTab(databaseProvider),
              _buildHistoryTab(databaseProvider),
            ],
          ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showBillResetDialog(context, databaseProvider),
        tooltip: 'Reset Bills',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildBillsTab(DatabaseProvider databaseProvider) {
    final bills = databaseProvider.bills;

    if (bills.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No bills available', style: TextStyle(fontSize: 18)),
            Text('Bills will be automatically generated on the 1st of odd months'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bills.length,
      itemBuilder: (context, index) {
        final bill = bills[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getStatusColor(bill.status),
              child: Icon(
                _getStatusIcon(bill.status),
                color: Colors.white,
              ),
            ),
            title: Text('\$${bill.totalAmount.toStringAsFixed(2)}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${bill.startDate.day}/${bill.startDate.month}/${bill.startDate.year} - ${bill.endDate.day}/${bill.endDate.month}/${bill.endDate.year}'),
                Text('${bill.totalUnits.toStringAsFixed(1)} kWh • ${bill.status.toUpperCase()}'),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) => _handleBillAction(value, bill, databaseProvider),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'view', child: Text('View Details')),
                const PopupMenuItem(value: 'mark_paid', child: Text('Mark as Paid')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
            onTap: () => _showBillDetails(bill, databaseProvider),
          ),
        );
      },
    );
  }

  Widget _buildReportsTab(DatabaseProvider databaseProvider) {
    final bills = databaseProvider.bills;
    final readings = databaseProvider.readings;
    final pricingTiers = databaseProvider.pricingTiers;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryReport(bills, readings),
          const SizedBox(height: 24),
          _buildTierBreakdownReport(readings, pricingTiers),
          const SizedBox(height: 24),
          _buildComparisonReport(bills),
        ],
      ),
    );
  }

  Widget _buildSavingsTab(DatabaseProvider databaseProvider) {
    final bills = databaseProvider.bills;
    final readings = databaseProvider.readings;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Savings Tips', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ..._generateSavingsTips(readings, bills),
          const SizedBox(height: 24),
          _buildSavingsRecommendations(readings),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(DatabaseProvider databaseProvider) {
    final bills = databaseProvider.bills;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search bills...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    // TODO: Implement search functionality
                  },
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: 'all',
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Status')),
                  DropdownMenuItem(value: 'paid', child: Text('Paid')),
                  DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                  DropdownMenuItem(value: 'overdue', child: Text('Overdue')),
                ],
                onChanged: (value) {
                  // TODO: Implement filter functionality
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildBillsTab(databaseProvider),
        ),
      ],
    );
  }

  Widget _buildSummaryReport(List<Bill> bills, List<MeterReading> readings) {
    if (bills.isEmpty) return const SizedBox.shrink();

    final totalAmount = bills.fold(0.0, (sum, bill) => sum + bill.totalAmount);
    final totalUnits = bills.fold(0.0, (sum, bill) => sum + bill.totalUnits);
    final averageBill = bills.isNotEmpty ? totalAmount / bills.length : 0.0;
    final averageConsumption = bills.isNotEmpty ? totalUnits / bills.length : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Summary Report', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildReportMetric('Total Bills', bills.length.toString()),
                ),
                Expanded(
                  child: _buildReportMetric('Total Amount', '\$${totalAmount.toStringAsFixed(2)}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildReportMetric('Average Bill', '\$${averageBill.toStringAsFixed(2)}'),
                ),
                Expanded(
                  child: _buildReportMetric('Avg. Consumption', '${averageConsumption.toStringAsFixed(1)} kWh'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierBreakdownReport(List<MeterReading> readings, List<PricingTier> pricingTiers) {
    if (readings.isEmpty || pricingTiers.isEmpty) return const SizedBox.shrink();

    final tierBreakdown = _calculateTierBreakdown(readings, pricingTiers);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tier Breakdown', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...tierBreakdown.entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(entry.key),
                  Text('${entry.value.toStringAsFixed(1)} kWh'),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonReport(List<Bill> bills) {
    if (bills.length < 2) return const SizedBox.shrink();

    final currentBill = bills.first;
    final previousBill = bills.length > 1 ? bills[1] : null;

    if (previousBill == null) return const SizedBox.shrink();

    final consumptionChange = ((currentBill.totalUnits - previousBill.totalUnits) / previousBill.totalUnits * 100);
    final amountChange = ((currentBill.totalAmount - previousBill.totalAmount) / previousBill.totalAmount * 100);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Period Comparison', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildComparisonMetric(
                    'Consumption',
                    '${currentBill.totalUnits.toStringAsFixed(1)} kWh',
                    '${previousBill.totalUnits.toStringAsFixed(1)} kWh',
                    consumptionChange,
                  ),
                ),
                Expanded(
                  child: _buildComparisonMetric(
                    'Amount',
                    '\$${currentBill.totalAmount.toStringAsFixed(2)}',
                    '\$${previousBill.totalAmount.toStringAsFixed(2)}',
                    amountChange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportMetric(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildComparisonMetric(String label, String current, String previous, double change) {
    final color = change > 0 ? Colors.red : Colors.green;
    final icon = change > 0 ? Icons.arrow_upward : Icons.arrow_downward;

    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(current, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(previous, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            Text(
              '${change.abs().toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _generateSavingsTips(List<MeterReading> readings, List<Bill> bills) {
    final tips = <Widget>[];

    if (readings.isEmpty) return tips;

    // Calculate average consumption
    final totalConsumption = readings.fold(0.0, (sum, reading) => sum + reading.consumption);
    final averageConsumption = totalConsumption / readings.length;

    // High consumption tip
    if (averageConsumption > 500) {
      tips.add(_buildSavingsTip(
        'High Consumption Alert',
        'Your average consumption is ${averageConsumption.toStringAsFixed(1)} kWh. Consider reducing usage during peak hours.',
        Icons.warning,
        Colors.orange,
      ));
    }

    // Seasonal comparison tip
    if (bills.length >= 2) {
      final currentBill = bills.first;
      final previousBill = bills[1];
      final consumptionChange = ((currentBill.totalUnits - previousBill.totalUnits) / previousBill.totalUnits * 100);

      if (consumptionChange > 10) {
        tips.add(_buildSavingsTip(
          'Increasing Usage',
          'Your consumption increased by ${consumptionChange.toStringAsFixed(1)}% compared to last period. Check for energy waste.',
          Icons.trending_up,
          Colors.red,
        ));
      }
    }

    // General tips
    tips.addAll([
      _buildSavingsTip(
        'Peak Hours',
        'Use appliances during off-peak hours (10 PM - 6 AM) to reduce costs.',
        Icons.schedule,
        Colors.blue,
      ),
      _buildSavingsTip(
        'LED Bulbs',
        'Replace incandescent bulbs with LED bulbs to save up to 75% on lighting costs.',
        Icons.lightbulb,
        Colors.green,
      ),
      _buildSavingsTip(
        'Appliance Maintenance',
        'Regularly clean and maintain appliances to ensure efficient operation.',
        Icons.build,
        Colors.purple,
      ),
    ]);

    return tips;
  }

  Widget _buildSavingsTip(String title, String description, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
      ),
    );
  }

  Widget _buildSavingsRecommendations(List<MeterReading> readings) {
    if (readings.isEmpty) return const SizedBox.shrink();

    final recommendations = _calculateSavingsRecommendations(readings);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Personalized Recommendations', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...recommendations.map((rec) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(child: Text(rec)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Map<String, double> _calculateTierBreakdown(List<MeterReading> readings, List<PricingTier> pricingTiers) {
    final breakdown = <String, double>{};
    final tiers = pricingTiers..sort((a, b) => a.threshold.compareTo(b.threshold));

    for (final reading in readings) {
      double remainingConsumption = reading.consumption;

      for (int i = 0; i < tiers.length; i++) {
        final tier = tiers[i];
        double consumptionInTier = 0.0;

        if (i == 0) {
          consumptionInTier = remainingConsumption < tier.threshold ? remainingConsumption : tier.threshold;
        } else {
          final prevThreshold = tiers[i - 1].threshold;
          if (remainingConsumption > prevThreshold) {
            consumptionInTier = (remainingConsumption < tier.threshold ? remainingConsumption : tier.threshold) - prevThreshold;
          }
        }

        if (consumptionInTier > 0) {
          breakdown[tier.name] = (breakdown[tier.name] ?? 0) + consumptionInTier;
          remainingConsumption -= consumptionInTier;
        }

        if (remainingConsumption <= 0) break;
      }
    }

    return breakdown;
  }

  List<String> _calculateSavingsRecommendations(List<MeterReading> readings) {
    final recommendations = <String>[];

    if (readings.isEmpty) return recommendations;

    final totalConsumption = readings.fold(0.0, (sum, reading) => sum + reading.consumption);
    final averageConsumption = totalConsumption / readings.length;

    if (averageConsumption > 400) {
      recommendations.add('Consider installing solar panels to reduce dependency on grid electricity');
    }

    if (averageConsumption > 300) {
      recommendations.add('Implement smart home automation to optimize energy usage');
    }

    recommendations.add('Monitor usage patterns and set consumption goals');
    recommendations.add('Schedule regular energy audits to identify inefficiencies');

    return recommendations;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'unpaid':
        return Colors.orange;
      case 'overdue':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Icons.check_circle;
      case 'unpaid':
        return Icons.pending;
      case 'overdue':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  void _handleBillAction(String action, Bill bill, DatabaseProvider databaseProvider) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    switch (action) {
      case 'view':
        _showBillDetails(bill, databaseProvider);
        break;
      case 'mark_paid':
        final updatedBill = bill.copyWith(status: 'paid');
        await databaseProvider.updateBill(updatedBill);
        break;
      case 'delete':
        await databaseProvider.deleteBill(bill.id, bill.userId);
        break;
    }
  }

  void _showBillDetails(Bill bill, DatabaseProvider databaseProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bill Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Period: ${bill.startDate.day}/${bill.startDate.month}/${bill.startDate.year} - ${bill.endDate.day}/${bill.endDate.month}/${bill.endDate.year}'),
            Text('Total Units: ${bill.totalUnits.toStringAsFixed(1)} kWh'),
            Text('Total Amount: \$${bill.totalAmount.toStringAsFixed(2)}'),
            Text('Status: ${bill.status.toUpperCase()}'),
            Text('Generated: ${bill.generatedAt.day}/${bill.generatedAt.month}/${bill.generatedAt.year}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showBillResetDialog(BuildContext context, DatabaseProvider databaseProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Bills'),
        content: const Text('This will delete all bills and regenerate them based on current readings. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _resetBills(databaseProvider);
            },
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _resetBills(DatabaseProvider databaseProvider) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentUser == null) return;

    try {
      // Delete all existing bills
      final bills = databaseProvider.bills;
      for (final bill in bills) {
        await databaseProvider.deleteBill(bill.id, bill.userId);
      }

      // Regenerate bills for all periods
      await _regenerateAllBills(authProvider.currentUser!.id, databaseProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bills reset successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting bills: $e')),
        );
      }
    }
  }

  Future<void> _regenerateAllBills(String userId, DatabaseProvider databaseProvider) async {
    final readings = databaseProvider.readings;
    if (readings.isEmpty) return;

    // Group readings by month
    final monthlyReadings = <String, List<MeterReading>>{};
    for (final reading in readings) {
      final key = '${reading.date.year}-${reading.date.month.toString().padLeft(2, '0')}';
      monthlyReadings[key] ??= [];
      monthlyReadings[key]!.add(reading);
    }

    // Generate bills for each month
    for (final entry in monthlyReadings.entries) {
      final readingsInMonth = entry.value;
      if (readingsInMonth.isEmpty) continue;

      final firstReading = readingsInMonth.first;
      final startDate = DateTime(firstReading.date.year, firstReading.date.month, 1);
      final endDate = DateTime(firstReading.date.year, firstReading.date.month + 1, 1).subtract(const Duration(days: 1));

      final totalAmount = await databaseProvider.calculateBillAmount(userId, startDate, endDate);
      final totalUnits = readingsInMonth.fold(0.0, (sum, reading) => sum + reading.consumption);

      final bill = Bill(
        id: DateTime.now().millisecondsSinceEpoch.toString() + entry.key,
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        totalUnits: totalUnits,
        totalAmount: totalAmount,
        status: 'unpaid',
        generatedAt: DateTime.now(),
      );

      await databaseProvider.addBill(bill);
    }

    await databaseProvider.loadBills(userId);
  }

  Future<void> _showExportDialog() async {
    String selectedFormat = 'csv';
    DateTime? startDate;
    DateTime? endDate;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Export Bills'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select export format:'),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: selectedFormat,
                items: const [
                  DropdownMenuItem(value: 'csv', child: Text('CSV')),
                  DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                  DropdownMenuItem(value: 'json', child: Text('JSON')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => selectedFormat = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('Date range (optional):'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => startDate = picked);
                        }
                      },
                      child: Text(startDate != null
                        ? '${startDate!.day}/${startDate!.month}/${startDate!.year}'
                        : 'Start Date'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: endDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => endDate = picked);
                        }
                      },
                      child: Text(endDate != null
                        ? '${endDate!.day}/${endDate!.month}/${endDate!.year}'
                        : 'End Date'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _exportBills(selectedFormat, startDate, endDate);
              },
              child: const Text('Export'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBills(String format, DateTime? startDate, DateTime? endDate) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentUser == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Exporting bills...'),
          ],
        ),
      ),
    );

    try {
      final exportService = ExportService();
      await exportService.exportBills(
        authProvider.currentUser!.id,
        format,
        startDate: startDate,
        endDate: endDate,
        onProgress: (progress) {
          // Could update progress indicator here
        },
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bills exported successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _generatePDFReport(List<Bill> bills) async {
    if (bills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bills to export')),
      );
      return;
    }

    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Electricity Bill Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),
                pw.Text('Generated on: ${DateTime.now().toString()}'),
                pw.SizedBox(height: 20),
                pw.Table.fromTextArray(
                  headers: ['Period', 'Units (kWh)', 'Amount (\$)', 'Status'],
                  data: bills.map((bill) => [
                    '${bill.startDate.day}/${bill.startDate.month}/${bill.startDate.year} - ${bill.endDate.day}/${bill.endDate.month}/${bill.endDate.year}',
                    bill.totalUnits.toStringAsFixed(1),
                    bill.totalAmount.toStringAsFixed(2),
                    bill.status.toUpperCase(),
                  ]).toList(),
                ),
              ],
            );
          },
        ),
      );

      final output = await getApplicationDocumentsDirectory();
      final file = File('${output.path}/bill_report.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF report saved to ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e')),
        );
      }
    }
  }
}

extension BillExtension on Bill {
  Bill copyWith({
    String? id,
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    double? totalUnits,
    double? totalAmount,
    String? status,
    DateTime? generatedAt,
    bool? isSynced,
    DateTime? lastSyncedAt,
  }) {
    return Bill(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      totalUnits: totalUnits ?? this.totalUnits,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      generatedAt: generatedAt ?? this.generatedAt,
      isSynced: isSynced ?? this.isSynced,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}