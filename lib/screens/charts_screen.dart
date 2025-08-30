import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/database_provider.dart';
import '../providers/auth_provider.dart';
import '../models/meter_reading.dart';
import '../models/pricing_tier.dart';
import '../services/export_service.dart';

enum ChartType { consumption, costs, trend, predictive }

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  ChartType _selectedChartType = ChartType.consumption;
  DateTimeRange? _selectedDateRange;
  List<MeterReading> _readings = [];
  List<PricingTier> _pricingTiers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);

      if (authProvider.currentUser != null) {
        await databaseProvider.loadReadings(authProvider.currentUser!.id);
        await databaseProvider.loadPricingTiers(authProvider.currentUser!.id);

        setState(() {
          _readings = databaseProvider.readings;
          _pricingTiers = databaseProvider.pricingTiers;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  List<MeterReading> _getFilteredReadings() {
    if (_selectedDateRange == null) return _readings;

    return _readings.where((reading) =>
      reading.date.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
      reading.date.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)))
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Charts & Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _showExportDialog,
            tooltip: 'Export Reports',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh Data',
          ),
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _selectDateRange,
            tooltip: 'Select Date Range',
          ),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              _buildDateRangeIndicator(),
              _buildChartTypeSelector(),
              Expanded(
                child: _buildChart(),
              ),
            ],
          ),
    );
  }

  Widget _buildDateRangeIndicator() {
    if (_selectedDateRange == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Text(
          'Showing all data',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'Date range: ${DateFormat('MMM dd, yyyy').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd, yyyy').format(_selectedDateRange!.end)}',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }

  Widget _buildChartTypeSelector() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Container(
      padding: const EdgeInsets.all(16),
      child: isSmallScreen
        ? Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ChartType.values.take(2).map((type) => _buildChartButton(type)).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ChartType.values.skip(2).map((type) => _buildChartButton(type)).toList(),
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ChartType.values.map((type) => _buildChartButton(type)).toList(),
          ),
    );
  }

  Widget _buildChartButton(ChartType type) {
    final isSelected = _selectedChartType == type;
    return ElevatedButton(
      onPressed: () => setState(() => _selectedChartType = type),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
          ? Theme.of(context).primaryColor
          : Colors.grey[300],
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(80, 36),
      ),
      child: Text(
        _getChartTypeLabel(type),
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black,
          fontSize: 12,
        ),
      ),
    );
  }

  String _getChartTypeLabel(ChartType type) {
    switch (type) {
      case ChartType.consumption:
        return 'Consumption';
      case ChartType.costs:
        return 'Costs';
      case ChartType.trend:
        return 'Trend';
      case ChartType.predictive:
        return 'Predictive';
    }
  }

  Widget _buildChart() {
    final filteredReadings = _getFilteredReadings();

    if (filteredReadings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _selectedDateRange != null
                ? 'No data available for the selected date range'
                : 'No meter readings available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add some meter readings to see charts',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final chartWidget = switch (_selectedChartType) {
      ChartType.consumption => _buildConsumptionChart(filteredReadings),
      ChartType.costs => _buildCostsChart(filteredReadings),
      ChartType.trend => _buildTrendChart(filteredReadings),
      ChartType.predictive => _buildPredictiveChart(filteredReadings),
    };

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 3.0,
      child: chartWidget,
    );
  }

  Widget _buildConsumptionChart(List<MeterReading> readings) {
    if (readings.isEmpty) {
      return const Center(child: Text('No consumption data available'));
    }

    // Sort readings by date
    final sortedReadings = readings..sort((a, b) => a.date.compareTo(b.date));

    // Create data points
    final spots = <FlSpot>[];
    final minDate = sortedReadings.first.date;
    final maxDate = sortedReadings.last.date;
    final totalDays = maxDate.difference(minDate).inDays;

    for (int i = 0; i < sortedReadings.length; i++) {
      final reading = sortedReadings[i];
      final daysSinceStart = reading.date.difference(minDate).inDays.toDouble();
      spots.add(FlSpot(daysSinceStart, reading.consumption));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text('${value.toStringAsFixed(1)} kWh');
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: totalDays > 30 ? totalDays / 10 : 1,
                getTitlesWidget: (value, meta) {
                  final date = minDate.add(Duration(days: value.toInt()));
                  return Text(DateFormat('MM/dd').format(date));
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: true),
          minX: 0,
          maxX: totalDays.toDouble(),
          minY: 0,
          maxY: spots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b) * 1.2,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Theme.of(context).primaryColor,
              barWidth: 3,
              belowBarData: BarAreaData(
                show: true,
                color: Theme.of(context).primaryColor.withAlpha(25),
              ),
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: Theme.of(context).primaryColor,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                },
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final date = minDate.add(Duration(days: spot.x.toInt()));
                  return LineTooltipItem(
                    '${DateFormat('MMM dd, yyyy').format(date)}\n${spot.y.toStringAsFixed(2)} kWh',
                    const TextStyle(color: Colors.white),
                  );
                }).toList();
              },
            ),
            handleBuiltInTouches: true,
          ),
        ),
      ),
    );
  }

  Widget _buildCostsChart(List<MeterReading> readings) {
    if (readings.isEmpty || _pricingTiers.isEmpty) {
      return const Center(child: Text('No cost data available'));
    }

    // Group readings by month and calculate costs
    final monthlyData = <DateTime, double>{};
    final sortedReadings = readings..sort((a, b) => a.date.compareTo(b.date));

    for (final reading in sortedReadings) {
      final monthKey = DateTime(reading.date.year, reading.date.month);
      final cost = _calculateCost(reading.consumption, reading.date);
      monthlyData[monthKey] = (monthlyData[monthKey] ?? 0) + cost;
    }

    if (monthlyData.isEmpty) {
      return const Center(child: Text('No cost data available'));
    }

    final sortedMonths = monthlyData.keys.toList()..sort();
    final barGroups = <BarChartGroupData>[];

    for (int i = 0; i < sortedMonths.length; i++) {
      final month = sortedMonths[i];
      final cost = monthlyData[month]!;
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: cost,
              color: Theme.of(context).primaryColor,
              width: 20,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: monthlyData.values.reduce((a, b) => a > b ? a : b) * 1.2,
          barGroups: barGroups,
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, meta) {
                  return Text('\$${value.toStringAsFixed(0)}');
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() < sortedMonths.length) {
                    final month = sortedMonths[value.toInt()];
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(DateFormat('MMM yy').format(month)),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: true),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final month = sortedMonths[group.x.toInt()];
                return BarTooltipItem(
                  '${DateFormat('MMMM yyyy').format(month)}\n\$${rod.toY.toStringAsFixed(2)}',
                  const TextStyle(color: Colors.white),
                );
              },
            ),
            handleBuiltInTouches: true,
          ),
        ),
      ),
    );
  }

  double _calculateCost(double consumption, DateTime date) {
    if (_pricingTiers.isEmpty) return 0.0;

    // Sort tiers by threshold ascending
    final tiers = _pricingTiers..sort((a, b) => a.threshold.compareTo(b.threshold));

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

  Widget _buildTrendChart(List<MeterReading> readings) {
    if (readings.isEmpty) {
      return const Center(child: Text('No trend data available'));
    }

    // Sort readings by date
    final sortedReadings = readings..sort((a, b) => a.date.compareTo(b.date));

    // Create original data points
    final minDate = sortedReadings.first.date;
    final originalSpots = <FlSpot>[];

    for (int i = 0; i < sortedReadings.length; i++) {
      final reading = sortedReadings[i];
      final daysSinceStart = reading.date.difference(minDate).inDays.toDouble();
      originalSpots.add(FlSpot(daysSinceStart, reading.consumption));
    }

    // Calculate 7-day moving average
    final movingAverageSpots = _calculateMovingAverage(sortedReadings, 7, minDate);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('Consumption', Theme.of(context).primaryColor),
              const SizedBox(width: 16),
              _buildLegendItem('7-Day Average', Colors.orange),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text('${value.toStringAsFixed(1)} kWh');
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: originalSpots.length > 10 ? originalSpots.length / 10 : 1,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < originalSpots.length) {
                          final date = minDate.add(Duration(days: value.toInt()));
                          return Text(DateFormat('MM/dd').format(date));
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                minX: 0,
                maxX: originalSpots.isNotEmpty ? originalSpots.last.x : 1,
                minY: 0,
                maxY: originalSpots.isNotEmpty
                  ? originalSpots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b) * 1.2
                  : 1,
                lineBarsData: [
                  // Original consumption line
                  LineChartBarData(
                    spots: originalSpots,
                    isCurved: false,
                    color: Theme.of(context).primaryColor,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 3,
                          color: Theme.of(context).primaryColor,
                          strokeWidth: 1,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                  ),
                  // Moving average line
                  LineChartBarData(
                    spots: movingAverageSpots,
                    isCurved: true,
                    color: Colors.orange,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final date = minDate.add(Duration(days: spot.x.toInt()));
                        final label = spot.barIndex == 0 ? 'Consumption' : '7-Day Avg';
                        return LineTooltipItem(
                          '${DateFormat('MMM dd').format(date)}\n$label: ${spot.y.toStringAsFixed(2)} kWh',
                          TextStyle(
                            color: spot.barIndex == 0
                              ? Theme.of(context).primaryColor
                              : Colors.orange,
                          ),
                        );
                      }).toList();
                    },
                  ),
                  handleBuiltInTouches: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<FlSpot> _calculateMovingAverage(List<MeterReading> readings, int windowSize, DateTime minDate) {
    if (readings.length < windowSize) return [];

    final movingAverageSpots = <FlSpot>[];

    for (int i = windowSize - 1; i < readings.length; i++) {
      double sum = 0;
      for (int j = i - windowSize + 1; j <= i; j++) {
        sum += readings[j].consumption;
      }
      final average = sum / windowSize;
      final daysSinceStart = readings[i].date.difference(minDate).inDays.toDouble();
      movingAverageSpots.add(FlSpot(daysSinceStart, average));
    }

    return movingAverageSpots;
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildPredictiveChart(List<MeterReading> readings) {
    if (readings.length < 2) {
      return const Center(child: Text('Need at least 2 readings for prediction'));
    }

    // Sort readings by date
    final sortedReadings = readings..sort((a, b) => a.date.compareTo(b.date));

    // Create historical data points
    final minDate = sortedReadings.first.date;
    final historicalSpots = <FlSpot>[];

    for (int i = 0; i < sortedReadings.length; i++) {
      final reading = sortedReadings[i];
      final daysSinceStart = reading.date.difference(minDate).inDays.toDouble();
      historicalSpots.add(FlSpot(daysSinceStart, reading.consumption));
    }

    // Calculate linear regression
    final regressionResult = _calculateLinearRegression(historicalSpots);

    // Generate prediction points (next 30 days)
    final predictionSpots = <FlSpot>[];
    final lastDay = historicalSpots.last.x;
    final predictionDays = 30;

    for (int i = 1; i <= predictionDays; i++) {
      final x = lastDay + i;
      final y = regressionResult['slope']! * x + regressionResult['intercept']!;
      predictionSpots.add(FlSpot(x, y));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('Historical', Theme.of(context).primaryColor),
              const SizedBox(width: 16),
              _buildLegendItem('Predicted', Colors.red),
              const SizedBox(width: 16),
              _buildLegendItem('Trend Line', Colors.green),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text('${value.toStringAsFixed(1)} kWh');
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: (historicalSpots.length + predictionDays) > 20
                        ? (historicalSpots.length + predictionDays) / 10
                        : 5,
                      getTitlesWidget: (value, meta) {
                        final date = minDate.add(Duration(days: value.toInt()));
                        return Text(DateFormat('MM/dd').format(date));
                      },
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                minX: 0,
                maxX: historicalSpots.isNotEmpty ? historicalSpots.last.x + predictionDays : predictionDays.toDouble(),
                minY: 0,
                maxY: predictionSpots.isNotEmpty
                  ? [...historicalSpots, ...predictionSpots].map((spot) => spot.y).reduce((a, b) => a > b ? a : b) * 1.2
                  : 1,
                lineBarsData: [
                  // Historical data
                  LineChartBarData(
                    spots: historicalSpots,
                    isCurved: false,
                    color: Theme.of(context).primaryColor,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: Theme.of(context).primaryColor,
                          strokeWidth: 2,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                  ),
                  // Trend line (regression line through historical data)
                  LineChartBarData(
                    spots: _generateTrendLine(historicalSpots, regressionResult),
                    isCurved: false,
                    color: Colors.green,
                    barWidth: 2,
                    dotData: FlDotData(show: false),
                  ),
                  // Prediction line
                  LineChartBarData(
                    spots: predictionSpots,
                    isCurved: false,
                    color: Colors.red,
                    barWidth: 2,
                    dotData: FlDotData(show: false),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final date = minDate.add(Duration(days: spot.x.toInt()));
                        String label;
                        Color color;

                        if (spot.barIndex == 0) {
                          label = 'Historical';
                          color = Theme.of(context).primaryColor;
                        } else if (spot.barIndex == 1) {
                          label = 'Trend';
                          color = Colors.green;
                        } else {
                          label = 'Predicted';
                          color = Colors.red;
                        }

                        return LineTooltipItem(
                          '${DateFormat('MMM dd').format(date)}\n$label: ${spot.y.toStringAsFixed(2)} kWh',
                          TextStyle(color: color),
                        );
                      }).toList();
                    },
                  ),
                  handleBuiltInTouches: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, double> _calculateLinearRegression(List<FlSpot> spots) {
    if (spots.length < 2) {
      return {'slope': 0.0, 'intercept': 0.0};
    }

    final n = spots.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;

    for (final spot in spots) {
      sumX += spot.x;
      sumY += spot.y;
      sumXY += spot.x * spot.y;
      sumXX += spot.x * spot.x;
    }

    final slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);
    final intercept = (sumY - slope * sumX) / n;

    return {'slope': slope, 'intercept': intercept};
  }

  List<FlSpot> _generateTrendLine(List<FlSpot> spots, Map<String, double> regression) {
    if (spots.isEmpty) return [];

    final minX = spots.first.x;
    final maxX = spots.last.x;
    final slope = regression['slope']!;
    final intercept = regression['intercept']!;

    return [
      FlSpot(minX, slope * minX + intercept),
      FlSpot(maxX, slope * maxX + intercept),
    ];
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange ?? DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now(),
      ),
    );

    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  Future<void> _showExportDialog() async {
    String selectedFormat = 'csv';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Export Consumption Reports'),
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
                await _exportReports(selectedFormat);
              },
              child: const Text('Export'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportReports(String format) async {
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
            Text('Exporting reports...'),
          ],
        ),
      ),
    );

    try {
      final exportService = ExportService();
      await exportService.exportReports(
        authProvider.currentUser!.id,
        format,
        startDate: _selectedDateRange?.start,
        endDate: _selectedDateRange?.end,
        onProgress: (progress) {
          // Could update progress indicator here
        },
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reports exported successfully')),
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
}