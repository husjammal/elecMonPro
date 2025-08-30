import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../models/meter_reading.dart';
import '../models/readings_search_state.dart';
import '../services/export_service.dart';
import 'add_reading_screen.dart';

class ReadingsListScreen extends StatefulWidget {
  const ReadingsListScreen({super.key});

  @override
  State<ReadingsListScreen> createState() => _ReadingsListScreenState();
}

class _ReadingsListScreenState extends State<ReadingsListScreen> {
  late ReadingsSearchState _searchState;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchState = ReadingsSearchState();
    _loadReadings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReadings() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);

    if (authProvider.currentUser != null) {
      await databaseProvider.loadReadings(authProvider.currentUser!.id);
      await _applyFilters();
    }
  }

  Future<void> _applyFilters() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);

    if (authProvider.currentUser != null) {
      await databaseProvider.loadFilteredReadings(
        userId: authProvider.currentUser!.id,
        searchQuery: _searchState.searchQuery,
        startDate: _searchState.startDate,
        endDate: _searchState.endDate,
        minConsumption: _searchState.minConsumption,
        maxConsumption: _searchState.maxConsumption,
        isManual: _searchState.isManual,
        sortBy: _searchState.sortBy,
        sortAscending: _searchState.sortAscending,
      );
    }
  }

  void _updateSearchState(ReadingsSearchState newState) {
    setState(() {
      _searchState = newState;
    });
    _applyFilters();
  }

  Future<void> _clearFilters() async {
    setState(() {
      _searchState.clearFilters();
      _searchController.clear();
    });
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);
    if (authProvider.currentUser != null) {
      await databaseProvider.clearFilters(authProvider.currentUser!.id);
    }
  }

  Future<void> _showDateRangePicker(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _searchState.startDate != null && _searchState.endDate != null
          ? DateTimeRange(start: _searchState.startDate!, end: _searchState.endDate!)
          : null,
    );

    if (picked != null) {
      _updateSearchState(_searchState.copyWith(
        startDate: picked.start,
        endDate: picked.end,
      ));
    }
  }

  Future<void> _showConsumptionFilter(BuildContext context) async {
    final TextEditingController minController = TextEditingController(
      text: _searchState.minConsumption?.toString() ?? '',
    );
    final TextEditingController maxController = TextEditingController(
      text: _searchState.maxConsumption?.toString() ?? '',
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter by Consumption'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: minController,
              decoration: const InputDecoration(
                labelText: 'Minimum consumption (kWh)',
                hintText: 'Leave empty for no minimum',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: maxController,
              decoration: const InputDecoration(
                labelText: 'Maximum consumption (kWh)',
                hintText: 'Leave empty for no maximum',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final min = minController.text.isNotEmpty ? double.tryParse(minController.text) : null;
              final max = maxController.text.isNotEmpty ? double.tryParse(maxController.text) : null;
              _updateSearchState(_searchState.copyWith(
                minConsumption: min,
                maxConsumption: max,
              ));
              Navigator.of(context).pop();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final databaseProvider = Provider.of<DatabaseProvider>(context);

    // Get screen size for responsive design
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width >= 600;

    // Responsive padding
    final containerPadding = isTablet ? 24.0 : 16.0;
    final cardMargin = isTablet ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meter Readings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _showExportDialog,
            tooltip: 'Export Readings',
          ),
          if (_searchState.hasFilters)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearFilters,
              tooltip: 'Clear filters',
            ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Section
          Container(
            padding: EdgeInsets.all(containerPadding),
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                // Search Bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search in notes, date, or reading value...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _updateSearchState(_searchState.copyWith(searchQuery: ''));
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (value) {
                    _updateSearchState(_searchState.copyWith(searchQuery: value));
                  },
                ),
                const SizedBox(height: 16),
                // Filter Row
                Row(
                  children: [
                    // Date Range Filter
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          _searchState.startDate != null && _searchState.endDate != null
                              ? '${_searchState.startDate!.day}/${_searchState.startDate!.month} - ${_searchState.endDate!.day}/${_searchState.endDate!.month}'
                              : 'Date Range',
                        ),
                        onPressed: () => _showDateRangePicker(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Consumption Filter
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.show_chart),
                        label: Text(
                          _searchState.minConsumption != null || _searchState.maxConsumption != null
                              ? '${_searchState.minConsumption ?? 0} - ${_searchState.maxConsumption ?? '∞'} kWh'
                              : 'Consumption',
                        ),
                        onPressed: () => _showConsumptionFilter(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Filter Chips
                Wrap(
                  spacing: 8,
                  children: [
                    // Manual/OCR Filter
                    FilterChip(
                      label: const Text('Manual'),
                      selected: _searchState.isManual == true,
                      onSelected: (selected) {
                        _updateSearchState(_searchState.copyWith(isManual: selected ? true : null));
                      },
                    ),
                    FilterChip(
                      label: const Text('OCR'),
                      selected: _searchState.isManual == false,
                      onSelected: (selected) {
                        _updateSearchState(_searchState.copyWith(isManual: selected ? false : null));
                      },
                    ),
                    // Sort Options
                    DropdownButton<String>(
                      value: _searchState.sortBy,
                      items: const [
                        DropdownMenuItem(value: 'date', child: Text('Sort by Date')),
                        DropdownMenuItem(value: 'consumption', child: Text('Sort by Consumption')),
                        DropdownMenuItem(value: 'cost', child: Text('Sort by Cost')),
                        DropdownMenuItem(value: 'reading_value', child: Text('Sort by Reading')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _updateSearchState(_searchState.copyWith(sortBy: value));
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(_searchState.sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                      onPressed: () {
                        _updateSearchState(_searchState.copyWith(sortAscending: !_searchState.sortAscending));
                      },
                      tooltip: 'Toggle sort order',
                    ),
                  ],
                ),
                // Results Count
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${databaseProvider.filteredReadings.length} readings found',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          // Readings List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadReadings,
              child: databaseProvider.filteredReadings.isEmpty
                  ? const Center(
                      child: Text('No readings match your filters'),
                    )
                  : ListView.builder(
                      itemCount: databaseProvider.filteredReadings.length,
                      itemBuilder: (context, index) {
                        final reading = databaseProvider.filteredReadings[index];
                        return AnimatedOpacity(
                          opacity: 1.0,
                          duration: const Duration(milliseconds: 500),
                          child: Dismissible(
                            key: Key(reading.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.red,
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            confirmDismiss: (direction) async {
                              // Haptic feedback
                              if (await Vibration.hasVibrator() ?? false) {
                                Vibration.vibrate(duration: 50);
                              }
                              return await _showDeleteConfirmation(reading);
                            },
                            onDismissed: (direction) {
                              _deleteReading(reading);
                            },
                            child: Card(
                              margin: EdgeInsets.symmetric(horizontal: cardMargin, vertical: 8),
                              child: ListTile(
                                leading: const Icon(Icons.electric_meter),
                                title: Text('${reading.readingValue} kWh'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Date: ${reading.date.day}/${reading.date.month}/${reading.date.year}',
                                    ),
                                    Text('Consumption: ${reading.consumption} kWh'),
                                    Text('Type: ${reading.isManual ? 'Manual' : 'OCR'}'),
                                    if (reading.notes != null && reading.notes!.isNotEmpty)
                                      Text('Notes: ${reading.notes}'),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) => _handleMenuAction(value, reading),
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const AddReadingScreen()),
          ).then((_) => _loadReadings());
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _handleMenuAction(String action, MeterReading reading) async {
    switch (action) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => AddReadingScreen(reading: reading)),
        ).then((_) => _loadReadings());
        break;
      case 'delete':
        if (await _showDeleteConfirmation(reading)) {
          _deleteReading(reading);
        }
        break;
    }
  }


  Future<bool> _showDeleteConfirmation(MeterReading reading) async {
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reading'),
        content: const Text('Are you sure you want to delete this reading?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
    return result ?? false;
  }


  Future<void> _deleteReading(MeterReading reading) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);

    await databaseProvider.deleteReading(reading.id, authProvider.currentUser!.id);
    // Remove from filtered readings list
    setState(() {
      databaseProvider.filteredReadings.remove(reading);
    });
  }

  Future<void> _showExportDialog() async {
    String selectedFormat = 'csv';
    DateTime? startDate = _searchState.startDate;
    DateTime? endDate = _searchState.endDate;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Export Meter Readings'),
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
                await _exportReadings(selectedFormat, startDate, endDate);
              },
              child: const Text('Export'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportReadings(String format, DateTime? startDate, DateTime? endDate) async {
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
            Text('Exporting readings...'),
          ],
        ),
      ),
    );

    try {
      final exportService = ExportService();
      await exportService.exportMeterReadings(
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
          const SnackBar(content: Text('Readings exported successfully')),
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