import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/app_configuration.dart';

void main() {
  group('AppConfiguration', () {
    test('toJson omits id and includes configId and baseWebAPI', () {
      final config = AppConfiguration(
        id: 1,
        configId: 'test-uuid',
        baseWebAPI: 'http://example.com',
      );
      final json = config.toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json['configId'], equals('test-uuid'));
      expect(json['baseWebAPI'], equals('http://example.com'));
    });

    test('fromJson round-trips a full config', () {
      final map = {
        'id': 1,
        'configId': 'test-uuid',
        'baseWebAPI': 'http://example.com',
      };
      final config = AppConfiguration.fromJson(map);
      expect(config.id, equals(1));
      expect(config.configId, equals('test-uuid'));
      expect(config.baseWebAPI, equals('http://example.com'));
    });

    test('fromJson with all null fields', () {
      final config = AppConfiguration.fromJson({
        'id': null,
        'configId': null,
        'baseWebAPI': null,
      });
      expect(config.id, isNull);
      expect(config.configId, isNull);
      expect(config.baseWebAPI, isNull);
    });

    test('fromJson with missing keys returns nulls', () {
      final config = AppConfiguration.fromJson({});
      expect(config.id, isNull);
      expect(config.configId, isNull);
      expect(config.baseWebAPI, isNull);
    });
  });
}
