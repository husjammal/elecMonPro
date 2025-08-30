import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/database_provider.dart';
import '../providers/auth_provider.dart';
import '../models/pricing_tier.dart';

class PricingScreen extends StatefulWidget {
  const PricingScreen({super.key});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends State<PricingScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _rateControllers = [];
  final List<TextEditingController> _thresholdControllers = [];
  late TextEditingController _inflationController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _inflationController = TextEditingController();
    for (int i = 0; i < 5; i++) {
      _rateControllers.add(TextEditingController());
      _thresholdControllers.add(TextEditingController());
    }
    _loadPricingTiers();
  }

  @override
  void dispose() {
    for (var controller in _rateControllers) {
      controller.dispose();
    }
    for (var controller in _thresholdControllers) {
      controller.dispose();
    }
    _inflationController.dispose();
    super.dispose();
  }

  Future<void> _loadPricingTiers() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);
    final userId = authProvider.currentUser!.id;

    await databaseProvider.loadPricingTiers(userId);
    final tiers = databaseProvider.pricingTiers;

    if (tiers.isNotEmpty) {
      // Sort by threshold
      tiers.sort((a, b) => a.threshold.compareTo(b.threshold));
      for (int i = 0; i < tiers.length && i < 5; i++) {
        _rateControllers[i].text = tiers[i].ratePerUnit.toString();
        _thresholdControllers[i].text = tiers[i].threshold.toString();
      }
      if (tiers.isNotEmpty) {
        _inflationController.text = tiers.first.inflationFactor.toString();
      }
    } else {
      // Default values
      _rateControllers[0].text = '0.1';
      _thresholdControllers[0].text = '1000';
      _rateControllers[1].text = '0.15';
      _thresholdControllers[1].text = '2000';
      _rateControllers[2].text = '0.2';
      _thresholdControllers[2].text = '3000';
      _rateControllers[3].text = '0.25';
      _thresholdControllers[3].text = '4000';
      _rateControllers[4].text = '0.3';
      _thresholdControllers[4].text = '5000';
      _inflationController.text = '0.05';
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _savePricingTiers() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);
    final userId = authProvider.currentUser!.id;

    final inflationFactor = double.tryParse(_inflationController.text) ?? 0.0;

    // Delete existing tiers
    final existingTiers = databaseProvider.pricingTiers;
    for (var tier in existingTiers) {
      await databaseProvider.deletePricingTier(tier.id, userId);
    }

    // Insert new tiers
    for (int i = 0; i < 5; i++) {
      final rate = double.tryParse(_rateControllers[i].text) ?? 0.0;
      final threshold = double.tryParse(_thresholdControllers[i].text) ?? 0.0;

      final tier = PricingTier(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '_$i',
        userId: userId,
        name: 'Tier ${i + 1}',
        ratePerUnit: rate,
        threshold: threshold,
        inflationFactor: inflationFactor,
        startDate: DateTime.now(),
      );

      await databaseProvider.addPricingTier(tier);
    }

    await databaseProvider.loadPricingTiers(userId);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pricing tiers saved successfully')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pricing Configuration'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                'Configure 5-tier pricing structure (SYP per 1000 kWh)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              for (int i = 0; i < 5; i++) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tier ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        TextFormField(
                          controller: _rateControllers[i],
                          decoration: const InputDecoration(labelText: 'Rate (SYP per 1000 kWh)'),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Required';
                            if (double.tryParse(value) == null) return 'Invalid number';
                            return null;
                          },
                        ),
                        TextFormField(
                          controller: _thresholdControllers[i],
                          decoration: const InputDecoration(labelText: 'Threshold (kWh)'),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Required';
                            if (double.tryParse(value) == null) return 'Invalid number';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 20),
              TextFormField(
                controller: _inflationController,
                decoration: const InputDecoration(labelText: 'Inflation Adjustment Factor (%)'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  if (double.tryParse(value) == null) return 'Invalid number';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _savePricingTiers,
                child: const Text('Save Pricing Configuration'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}