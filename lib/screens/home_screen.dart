import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../providers/sync_provider.dart';
import '../models/meter_reading.dart';
import '../models/bill.dart';
import '../models/pricing_tier.dart';
import '../services/voice_over_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VoiceOverService _voiceOverService = VoiceOverService();

  @override
  void initState() {
    super.initState();
    _voiceOverService.initialize();
    _loadData();
  }

  Future<void> _loadData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);

    if (authProvider.currentUser != null) {
      await databaseProvider.loadReadings(authProvider.currentUser!.id);
      await databaseProvider.loadBills(authProvider.currentUser!.id);
      await databaseProvider.loadPricingTiers(authProvider.currentUser!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final databaseProvider = Provider.of<DatabaseProvider>(context);
    final syncProvider = Provider.of<SyncProvider>(context);

    // Get screen size and orientation
    final screenSize = MediaQuery.of(context).size;
    final orientation = MediaQuery.of(context).orientation;

    // Define responsive breakpoints
    final isTablet = screenSize.width >= 600;
    final isLandscape = orientation == Orientation.landscape;

    // Announce screen title for voice-over
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _voiceOverService.speakScreenTitle('Electricity Monitor');
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Electricity Monitor'),
        actions: [
          // Sync status indicator
          Semantics(
            label: 'Sync status: ${syncProvider.getSyncStatusDescription()}',
            button: true,
            child: IconButton(
              icon: Icon(syncProvider.getSyncStatusIcon()),
              color: syncProvider.getSyncStatusColor(),
              onPressed: () {
                _voiceOverService.speakButton('Sync Status');
                _showSyncStatusDialog(context, syncProvider);
              },
              tooltip: syncProvider.getSyncStatusDescription(),
            ),
          ),
          Semantics(
            label: 'Logout button',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () {
                _voiceOverService.speakButton('Logout');
                authProvider.logout();
              },
            ),
          ),
        ],
      ),
      body: Semantics(
        label: 'Pull down to refresh data',
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome Section
                Semantics(
                  label: 'Welcome message for ${authProvider.currentUser?.name ?? 'User'}',
                  child: Text(
                    'Welcome, ${authProvider.currentUser?.name ?? 'User'}!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: isTablet ? 28 : 24,
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 32 : 24),

                     // Consumption Summary Cards
                     if (isLandscape && isTablet)
                       // Landscape tablet: 4 cards in a row
                       Row(
                         children: [
                           Expanded(
                             child: _buildSummaryCard(
                               context,
                               'Current Usage',
                               '${_calculateCurrentConsumption(databaseProvider.readings)} kWh',
                               Icons.electric_bolt,
                               Colors.blue,
                             ),
                           ),
                           const SizedBox(width: 16),
                           Expanded(
                             child: _buildSummaryCard(
                               context,
                               'Estimated Bill',
                               '\$${_calculateEstimatedBill(databaseProvider.readings, databaseProvider.pricingTiers)}',
                               Icons.receipt,
                               Colors.green,
                             ),
                           ),
                         ],
                       )
                     else
                       // Portrait or phone: 2 cards in a row
                       Row(
                         children: [
                           Expanded(
                             child: _buildSummaryCard(
                               context,
                               'Current Usage',
                               '${_calculateCurrentConsumption(databaseProvider.readings)} kWh',
                               Icons.electric_bolt,
                               Colors.blue,
                             ),
                           ),
                           const SizedBox(width: 16),
                           Expanded(
                             child: _buildSummaryCard(
                               context,
                               'Estimated Bill',
                               '\$${_calculateEstimatedBill(databaseProvider.readings, databaseProvider.pricingTiers)}',
                               Icons.receipt,
                               Colors.green,
                             ),
                           ),
                         ],
                       ),
                     const SizedBox(height: 24),

                     // Recent Readings
                     Semantics(
                       header: true,
                       child: Text(
                         'Recent Readings',
                         style: Theme.of(context).textTheme.titleLarge,
                       ),
                     ),
                     const SizedBox(height: 16),
                     _buildRecentReadingsList(databaseProvider.readings),

                     const SizedBox(height: 24),

                     // Bill Overview
                     Semantics(
                       header: true,
                       child: Text(
                         'Bill Overview',
                         style: Theme.of(context).textTheme.titleLarge,
                       ),
                     ),
                     const SizedBox(height: 16),
                     _buildBillOverview(databaseProvider.bills),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buildSummaryCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Semantics(
      label: '$title: $value',
      child: Card(
        elevation: 4,
        child: InkWell(
          onTap: () => _voiceOverService.speakCard(title, value),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Icon(icon, size: 32, color: color),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentReadingsList(List<MeterReading> readings) {
    if (readings.isEmpty) {
      return Semantics(
        label: 'No readings available',
        child: const Card(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No readings available'),
          ),
        ),
      );
    }

    final recentReadings = readings.take(5).toList();

    return Semantics(
      label: 'Recent readings list with ${recentReadings.length} items',
      child: Card(
        child: ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: recentReadings.length,
          itemBuilder: (context, index) {
            final reading = recentReadings[index];
            final readingText = '${reading.readingValue} kWh on ${reading.date.day}/${reading.date.month}/${reading.date.year}, consumption: ${reading.consumption} kWh';

            return AnimatedOpacity(
              opacity: 1.0,
              duration: Duration(milliseconds: 300 + (index * 100)),
              child: Semantics(
                label: readingText,
                child: ListTile(
                  minVerticalPadding: 12, // Increase touch target
                  leading: const Icon(Icons.electric_meter),
                  title: Text('${reading.readingValue} kWh'),
                  subtitle: Text(
                    '${reading.date.day}/${reading.date.month}/${reading.date.year}',
                  ),
                  trailing: Text('${reading.consumption} kWh'),
                  onTap: () => _voiceOverService.speakListItem(readingText, index),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBillOverview(List<Bill> bills) {
    if (bills.isEmpty) {
      return Semantics(
        label: 'No bills available',
        child: const Card(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No bills available'),
          ),
        ),
      );
    }

    final recentBills = bills.take(3).toList();

    return Semantics(
      label: 'Bill overview list with ${recentBills.length} items',
      child: Card(
        child: ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: recentBills.length,
          itemBuilder: (context, index) {
            final bill = recentBills[index];
            final billText = 'Bill for \$${bill.totalAmount.toStringAsFixed(2)} from ${bill.startDate.day}/${bill.startDate.month} to ${bill.endDate.day}/${bill.endDate.month}, status: ${bill.status}';

            return AnimatedOpacity(
              opacity: 1.0,
              duration: Duration(milliseconds: 300 + (index * 100)),
              child: Semantics(
                label: billText,
                child: ListTile(
                  minVerticalPadding: 12, // Increase touch target
                  leading: Icon(
                    bill.status == 'paid' ? Icons.check_circle : Icons.pending,
                    color: bill.status == 'paid' ? Colors.green : Colors.orange,
                  ),
                  title: Text('\$${bill.totalAmount.toStringAsFixed(2)}'),
                  subtitle: Text(
                    '${bill.startDate.day}/${bill.startDate.month} - ${bill.endDate.day}/${bill.endDate.month}',
                  ),
                  trailing: Text(bill.status.toUpperCase()),
                  onTap: () => _voiceOverService.speakListItem(billText, index),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  double _calculateCurrentConsumption(List<MeterReading> readings) {
    if (readings.isEmpty) return 0.0;
    return readings.last.consumption;
  }

  double _calculateEstimatedBill(List<MeterReading> readings, List<PricingTier> pricingTiers) {
    if (readings.isEmpty || pricingTiers.isEmpty) return 0.0;

    final consumption = _calculateCurrentConsumption(readings);
    return _calculateCost(consumption, DateTime.now(), pricingTiers);
  }

  double _calculateCost(double consumption, DateTime date, List<PricingTier> pricingTiers) {
    if (pricingTiers.isEmpty) return 0.0;

    // Sort tiers by threshold ascending
    final tiers = pricingTiers..sort((a, b) => a.threshold.compareTo(b.threshold));

    double totalCost = 0.0;
    double remainingConsumption = consumption;

    for (int i = 0; i < tiers.length; i++) {
      final tier = tiers[i];
      double consumptionInTier = 0.0;

      if (i == 0) {
        // First tier: 0 to threshold
        consumptionInTier = remainingConsumption < tier.threshold ? remainingConsumption : tier.threshold;
      } else {
        // Subsequent tiers: from previous threshold to current
        final prevThreshold = tiers[i - 1].threshold;
        final currentThreshold = tier.threshold;
        if (remainingConsumption > prevThreshold) {
          consumptionInTier = (remainingConsumption < currentThreshold ? remainingConsumption : currentThreshold) - prevThreshold;
        }
      }

      if (consumptionInTier > 0) {
        // Apply inflation adjustment
        final yearsSinceStart = date.difference(tier.startDate).inDays / 365.0;
        final adjustedRate = tier.ratePerUnit * pow(1 + tier.inflationFactor, yearsSinceStart);

        totalCost += consumptionInTier * adjustedRate;
        remainingConsumption -= consumptionInTier;
      }

      if (remainingConsumption <= 0) break;
    }

    // If consumption exceeds all tiers, use the last tier's rate for remaining
    if (remainingConsumption > 0 && tiers.isNotEmpty) {
      final lastTier = tiers.last;
      final yearsSinceStart = date.difference(lastTier.startDate).inDays / 365.0;
      final adjustedRate = lastTier.ratePerUnit * pow(1 + lastTier.inflationFactor, yearsSinceStart);
      totalCost += remainingConsumption * adjustedRate;
    }

    return totalCost;
  }

  void _showSyncStatusDialog(BuildContext context, SyncProvider syncProvider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sync Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(syncProvider.getSyncStatusIcon(), color: syncProvider.getSyncStatusColor()),
                  const SizedBox(width: 8),
                  Text(syncProvider.getSyncStatusDescription()),
                ],
              ),
              const SizedBox(height: 16),
              if (syncProvider.hasError)
                Text(
                  'Error: ${syncProvider.syncError}',
                  style: const TextStyle(color: Colors.red),
                ),
              const SizedBox(height: 16),
              if (!syncProvider.isOnline)
                const Text(
                  'You are currently offline. Changes will be synced when connection is restored.',
                  style: TextStyle(fontSize: 12),
                ),
            ],
          ),
          actions: [
            if (syncProvider.isOnline && !syncProvider.isSyncing)
              TextButton(
                onPressed: () {
                  syncProvider.performFullSync();
                  Navigator.of(context).pop();
                },
                child: const Text('Sync Now'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}