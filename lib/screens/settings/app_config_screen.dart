import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../data/models/app_configuration.dart';
import '../../widgets/responsive_constraint.dart';

/// Settings form for [AppConfig] — exposes the API base URL and the bill
/// summary message template.
class AppConfigScreen extends StatefulWidget {
  const AppConfigScreen({super.key});

  @override
  State<AppConfigScreen> createState() => _AppConfigScreenState();
}

class _AppConfigScreenState extends State<AppConfigScreen> {
  static const _templateVariables = [
    '{{greeting}}',
    '{{firstName}}',
    '{{fullName}}',
    '{{billSummary}}',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _apiUrlController;
  late final TextEditingController _templateController;
  String _previewText = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController(text: AppConfig.apiBaseUrl);
    _templateController = TextEditingController(text: AppConfig.messageTemplate);
    _templateController.addListener(_updatePreview);
    _updatePreview();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _templateController.dispose();
    super.dispose();
  }

  void _updatePreview() {
    final preview = _templateController.text
        .replaceAll('{{greeting}}', 'Good morning')
        .replaceAll('{{firstName}}', 'Alex')
        .replaceAll('{{fullName}}', 'Alex Johnson')
        .replaceAll('{{billSummary}}', 'the electric bill is \$45.00 due April 15th.');
    setState(() => _previewText = preview);
  }

  void _insertVariable(String variable) {
    final controller = _templateController;
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final newText = text.replaceRange(start, end, variable);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + variable.length),
    );
  }

  void _resetTemplate() {
    _templateController.text = AppConfiguration.defaultMessageTemplate;
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AppConfig.setApiBaseUrl(_apiUrlController.text.trim());
      await AppConfig.setMessageTemplate(_templateController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App configuration saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('App Configuration')),
      body: ResponsiveConstraint(
        maxWidth: 560,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('General', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextFormField(
                      controller: _apiUrlController,
                      decoration: const InputDecoration(
                        labelText: 'API Base URL',
                        hintText: 'http://127.0.0.1:8080',
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'API Base URL is required';
                        }
                        final uri = Uri.tryParse(value.trim());
                        if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                          return 'Enter a valid URL (e.g. http://127.0.0.1:8080)';
                        }
                        if (uri.scheme != 'http' && uri.scheme != 'https') {
                          return 'URL must use http or https';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Message Template', style: theme.textTheme.titleMedium),
                    TextButton(
                      onPressed: _resetTemplate,
                      child: const Text('Reset to default'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _templateController,
                          decoration: const InputDecoration(
                            labelText: 'Template',
                            hintText: '{{greeting}} {{firstName}}, {{billSummary}}',
                            alignLabelWithHint: true,
                          ),
                          maxLines: 3,
                          autocorrect: false,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Template cannot be empty';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Text('Insert variable:', style: theme.textTheme.labelMedium),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _templateVariables
                              .map((v) => ActionChip(
                                    label: Text(v),
                                    onPressed: () => _insertVariable(v),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                        Text('Preview:', style: theme.textTheme.labelMedium),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _previewText,
                            style: theme.textTheme.bodyMedium,
                          ),
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
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
