import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/server_configuration.dart';

/// Settings form for [ServerConfiguration] — email credentials, IMAP settings,
/// and sync scheduling.
class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _emailAddressController;
  late final TextEditingController _emailPasswordController;
  late final TextEditingController _imapServerController;
  late final TextEditingController _imapPortController;
  late final TextEditingController _earliestDateController;
  late final TextEditingController _syncDelayController;
  late final TextEditingController _syncIntervalController;

  bool _imapSecure = true;
  bool _passwordVisible = false;
  bool _saving = false;

  late DateTime _earliestDate;
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _emailAddressController = TextEditingController(
      text: ServerConfiguration.emailAddress,
    );
    _emailPasswordController = TextEditingController(
      text: ServerConfiguration.emailPassword,
    );
    _imapServerController = TextEditingController(
      text: ServerConfiguration.emailImapServer,
    );
    _imapPortController = TextEditingController(
      text: ServerConfiguration.emailImapPort.toString(),
    );
    _imapSecure = ServerConfiguration.emailImapSecure;
    _earliestDate = ServerConfiguration.emailEarliestDate;
    _earliestDateController = TextEditingController(
      text: _dateFormat.format(_earliestDate),
    );
    _syncDelayController = TextEditingController(
      text: ServerConfiguration.emailSyncDelayDuration.inSeconds.toString(),
    );
    _syncIntervalController = TextEditingController(
      text: ServerConfiguration.emailSyncInterval.inSeconds.toString(),
    );
  }

  @override
  void dispose() {
    _emailAddressController.dispose();
    _emailPasswordController.dispose();
    _imapServerController.dispose();
    _imapPortController.dispose();
    _earliestDateController.dispose();
    _syncDelayController.dispose();
    _syncIntervalController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _earliestDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _earliestDate = picked;
        _earliestDateController.text = _dateFormat.format(picked);
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ServerConfiguration.setEmailAddress(
        _emailAddressController.text.trim(),
      );
      await ServerConfiguration.setEmailPassword(
        _emailPasswordController.text,
      );
      await ServerConfiguration.setEmailImapServer(
        _imapServerController.text.trim(),
      );
      await ServerConfiguration.setEmailImapPort(
        int.parse(_imapPortController.text.trim()),
      );
      await ServerConfiguration.setEmailImapSecure(_imapSecure);
      await ServerConfiguration.setEmailEarliestDate(_earliestDate);
      await ServerConfiguration.setEmailSyncDelayDuration(
        Duration(seconds: int.parse(_syncDelayController.text.trim())),
      );
      await ServerConfiguration.setEmailSyncInterval(
        Duration(seconds: int.parse(_syncIntervalController.text.trim())),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server configuration saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateInt(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    if (int.tryParse(value.trim()) == null) {
      return '$fieldName must be a whole number';
    }
    return null;
  }

  String? _validatePort(String? value) {
    final base = _validateInt(value, 'IMAP Port');
    if (base != null) return base;
    final port = int.parse(value!.trim());
    if (port < 1 || port > 65535) return 'IMAP Port must be between 1 and 65535';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server Configuration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Email credentials ──────────────────────────────────────────
              Text(
                'Email Account',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _emailAddressController,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Email address is required';
                          if (!value.contains('@')) return 'Enter a valid email address';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Email Password',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () => setState(
                              () => _passwordVisible = !_passwordVisible,
                            ),
                          ),
                        ),
                        obscureText: !_passwordVisible,
                        autocorrect: false,
                        enableSuggestions: false,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── IMAP settings ──────────────────────────────────────────────
              Text(
                'IMAP Settings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _imapServerController,
                        decoration: const InputDecoration(
                          labelText: 'IMAP Server',
                          hintText: 'imap.gmail.com',
                        ),
                        autocorrect: false,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'IMAP server is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _imapPortController,
                        decoration: const InputDecoration(
                          labelText: 'IMAP Port',
                          hintText: '993',
                        ),
                        keyboardType: TextInputType.number,
                        validator: _validatePort,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use Secure Connection (TLS)'),
                        value: _imapSecure,
                        onChanged: (v) => setState(() => _imapSecure = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Sync settings ──────────────────────────────────────────────
              Text(
                'Sync Settings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _earliestDateController,
                        decoration: InputDecoration(
                          labelText: 'Earliest Email Date',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_today_outlined),
                            onPressed: _pickDate,
                          ),
                        ),
                        readOnly: true,
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _syncDelayController,
                        decoration: const InputDecoration(
                          labelText: 'Sync Delay (seconds)',
                          hintText: '30',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) => _validateInt(v, 'Sync Delay'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _syncIntervalController,
                        decoration: const InputDecoration(
                          labelText: 'Sync Interval (seconds)',
                          hintText: '900',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) => _validateInt(v, 'Sync Interval'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              FilledButton(
                onPressed: _saving ? null : _saveSettings,
                child: _saving
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Text('Save'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
