import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../providers/theme_provider.dart';
import '../models/app_settings.dart';
import '../services/cloud_service.dart';
import '../services/voice_over_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _autoBackup = true;
  bool _ocrEnabled = true;
  bool _voiceOverEnabled = false;
  bool _highContrastEnabled = false;
  String _theme = 'light';
  final CloudService _cloudService = CloudService();
  final VoiceOverService _voiceOverService = VoiceOverService();
  bool _isBackingUp = false;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _voiceOverService.initialize();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);

    if (authProvider.currentUser != null) {
      await databaseProvider.loadAppSettings(authProvider.currentUser!.id);
      final settings = databaseProvider.appSettings;
      if (settings != null) {
        setState(() {
          _notificationsEnabled = settings.notificationEnabled;
          _autoBackup = settings.autoBackup;
          _ocrEnabled = settings.ocrEnabled;
          _voiceOverEnabled = settings.voiceOverEnabled;
          _highContrastEnabled = settings.highContrastEnabled;
          _theme = settings.theme;
        });
        _voiceOverService.setEnabled(settings.voiceOverEnabled);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // User Profile Section
          const ListTile(
            leading: Icon(Icons.person),
            title: Text('User Profile'),
            subtitle: Text('Manage your account information'),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: null, // Placeholder for future implementation
          ),

          const Divider(),

          // Theme Settings
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              String currentTheme;
              switch (themeProvider.themeMode) {
                case ThemeMode.light:
                  currentTheme = 'Light';
                  break;
                case ThemeMode.dark:
                  currentTheme = 'Dark';
                  break;
                case ThemeMode.system:
                  currentTheme = 'System';
                  break;
              }

              return ListTile(
                leading: const Icon(Icons.palette),
                title: const Text('Theme'),
                subtitle: Text('Current: $currentTheme'),
                trailing: DropdownButton<ThemeMode>(
                  value: themeProvider.themeMode,
                  items: const [
                    DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                    DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      themeProvider.setThemeMode(value);
                      // Also update database settings
                      _theme = value == ThemeMode.light ? 'light' : value == ThemeMode.dark ? 'dark' : 'system';
                      _saveSettings();
                    }
                  },
                ),
              );
            },
          ),

          // Notifications
          SwitchListTile(
            secondary: const Icon(Icons.notifications),
            title: const Text('Notifications'),
            subtitle: const Text('Receive usage alerts and reminders'),
            value: _notificationsEnabled,
            onChanged: (value) {
              setState(() => _notificationsEnabled = value);
              _saveSettings();
            },
          ),

          // Auto Backup
          SwitchListTile(
            secondary: const Icon(Icons.backup),
            title: const Text('Auto Backup'),
            subtitle: const Text('Automatically backup data to cloud'),
            value: _autoBackup,
            onChanged: (value) {
              setState(() => _autoBackup = value);
              _saveSettings();
            },
          ),

          // Manual Backup
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('Backup to Cloud'),
            subtitle: const Text('Manually backup all data to cloud'),
            trailing: _isBackingUp
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_ios),
            onTap: _isBackingUp ? null : () => _manualBackup(),
          ),

          // Manual Restore
          ListTile(
            leading: const Icon(Icons.cloud_download),
            title: const Text('Restore from Cloud'),
            subtitle: const Text('Restore data from cloud backup'),
            trailing: _isRestoring
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_ios),
            onTap: _isRestoring ? null : () => _manualRestore(),
          ),

          // OCR Processing
          SwitchListTile(
            secondary: const Icon(Icons.camera),
            title: const Text('OCR Processing'),
            subtitle: const Text('Automatically extract readings from meter photos'),
            value: _ocrEnabled,
            onChanged: (value) {
              setState(() => _ocrEnabled = value);
              _saveSettings();
            },
          ),

          const Divider(),

          // Accessibility Settings
          const ListTile(
            leading: Icon(Icons.accessibility),
            title: Text('Accessibility'),
            subtitle: Text('Voice-over and high-contrast options'),
          ),

          // Voice-over
          SwitchListTile(
            secondary: const Icon(Icons.volume_up),
            title: const Text('Voice-over'),
            subtitle: const Text('Enable screen reader support'),
            value: _voiceOverEnabled,
            onChanged: (value) {
              setState(() => _voiceOverEnabled = value);
              _voiceOverService.setEnabled(value);
              _saveSettings();
            },
          ),

          // High-contrast mode
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return SwitchListTile(
                secondary: const Icon(Icons.contrast),
                title: const Text('High-contrast mode'),
                subtitle: const Text('Increase contrast for better visibility'),
                value: _highContrastEnabled,
                onChanged: (value) {
                  setState(() => _highContrastEnabled = value);
                  themeProvider.setHighContrast(value);
                  _saveSettings();
                },
              );
            },
          ),

          const Divider(),

          // Pricing Tiers
          const ListTile(
            leading: Icon(Icons.attach_money),
            title: Text('Pricing Tiers'),
            subtitle: Text('Configure electricity rates'),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: null, // Placeholder for future implementation
          ),

          // Data Export
          const ListTile(
            leading: Icon(Icons.download),
            title: Text('Export Data'),
            subtitle: Text('Download your data as CSV/PDF'),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: null, // Placeholder for future implementation
          ),

          // About
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('About'),
            subtitle: Text('App version and information'),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: null, // Placeholder for future implementation
          ),

          const Divider(),

          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () => _showLogoutConfirmation(),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);

    if (authProvider.currentUser == null) return;

    final settings = AppSettings(
      id: authProvider.currentUser!.id,
      userId: authProvider.currentUser!.id,
      theme: _theme,
      notificationEnabled: _notificationsEnabled,
      autoBackup: _autoBackup,
      ocrEnabled: _ocrEnabled,
      voiceOverEnabled: _voiceOverEnabled,
      highContrastEnabled: _highContrastEnabled,
    );

    await databaseProvider.saveAppSettings(settings);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  Future<void> _manualBackup() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to backup data')),
      );
      return;
    }

    setState(() => _isBackingUp = true);

    try {
      await _cloudService.manualBackup(authProvider.currentUser!.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup completed successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $e')),
      );
    } finally {
      setState(() => _isBackingUp = false);
    }
  }

  Future<void> _manualRestore() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to restore data')),
      );
      return;
    }

    // Show confirmation dialog
    final shouldRestore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from Cloud'),
        content: const Text(
          'This will restore your data from the cloud backup. '
          'Local changes may be overwritten. Continue?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
        ],
      ),
    );

    if (shouldRestore != true) return;

    setState(() => _isRestoring = true);

    try {
      await _cloudService.manualRestore(authProvider.currentUser!.id);
      // Reload settings after restore
      await _loadSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restore completed successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $e')),
      );
    } finally {
      setState(() => _isRestoring = false);
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              authProvider.logout();
              Navigator.of(context).pop();
            },
            child: const Text('Logout'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }
}