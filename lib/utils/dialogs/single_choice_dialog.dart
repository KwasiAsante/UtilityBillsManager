import 'package:flutter/material.dart';

/// A simple radio-list dialog for picking one value out of [options].
///
/// Used to move less-common actions (filter / sort selection) into an
/// overflow menu on narrow screens, where they no longer fit as standalone
/// app-bar icons.
class SingleChoiceDialog {
  SingleChoiceDialog._();

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required List<T> options,
    required T current,
    required String Function(T) labelBuilder,
  }) {
    return showDialog<T>(
      context: context,
      builder:
          (context) => SimpleDialog(
            title: Text(title),
            children: [
              RadioGroup<T>(
                groupValue: current,
                onChanged: (value) => Navigator.pop(context, value),
                child: Column(
                  children:
                      options
                          .map(
                            (option) => RadioListTile<T>(
                              value: option,
                              title: Text(labelBuilder(option)),
                            ),
                          )
                          .toList(),
                ),
              ),
            ],
          ),
    );
  }
}
