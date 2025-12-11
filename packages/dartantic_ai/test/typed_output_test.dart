// CRITICAL TEST FAILURE INVESTIGATION PROCESS: When a test fails for a provider
// capability:
// 1. NEVER immediately disable the capability in provider definitions
// 2. ALWAYS investigate at the API level first:
//    - Test with curl to verify if the feature works at the raw API level
//    - Check the provider's official documentation
//    - Look for differences between our implementation and the API requirements
// 3. ONLY disable a capability after confirming:
//    - The API itself doesn't support the feature, OR
//    - The API has a fundamental limitation (like Together's streaming tool
//      format)
// 4. If the API supports it but our code doesn't: FIX THE IMPLEMENTATION
// 5. LET EXCEPTIONS BUBBLE UP: Do not add defensive checks or try-catch blocks.
//    Missing API keys, network errors, and provider issues should fail loudly
//    so they can be identified and fixed immediately.

// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:json_schema/json_schema.dart' as js;
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';

/// First provider that supports typed output (for single-provider tests)
Provider get _typedOutputProvider => Agent.allProviders.firstWhere(
  (p) => providerHasTestCaps(p.name, {ProviderTestCaps.typedOutput}),
);

void main() {
  group('Typed Output', timeout: const Timeout(Duration(minutes: 5)), () {
    group('basic structured output', () {
      runProviderTest(
        'returns simple JSON object',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'age': {'type': 'integer'},
            },
            'required': ['name', 'age'],
          });

          final agent = Agent(provider.name);
          final result = await agent.send(
            'Generate a person with name "John" and age 30',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['name'], isA<String>());
          expect(json['age'], isA<int>());
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );

      runProviderTest(
        'handles nested objects',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'user': {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string'},
                  'email': {'type': 'string'},
                },
                'required': ['name', 'email'],
              },
              'settings': {
                'type': 'object',
                'properties': {
                  'theme': {'type': 'string'},
                  'notifications': {'type': 'boolean'},
                },
              },
            },
            'required': ['user', 'settings'],
          });

          final agent = Agent(provider.name);
          final result = await agent.send(
            'Create a user object with name "Alice", '
            'email "alice@example.com", '
            'theme "dark", and notifications enabled',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['user'], isA<Map<String, dynamic>>());
          expect(json['user']['name'], isA<String>());
          expect(json['user']['email'], isA<String>());

          if (json['settings'] != null) {
            expect(json['settings']['theme'], isA<String>());
            expect(json['settings']['notifications'], isA<bool>());
          }
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );

      runProviderTest(
        'returns arrays when specified',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'items': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'integer'},
                    'name': {'type': 'string'},
                  },
                  'required': ['id', 'name'],
                },
              },
            },
            'required': ['items'],
          });

          final agent = Agent(provider.name);
          final result = await agent.send(
            'Create an array of 3 items with sequential IDs starting at 1 '
            'and names "Apple", "Banana", "Cherry"',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['items'], isA<List>());
          expect(json['items'], hasLength(3));
          expect(json['items'][0]['id'], equals(1));
          expect(json['items'][0]['name'], equals('Apple'));
          expect(json['items'][2]['name'], equals('Cherry'));
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );

      runProviderTest(
        'handle structured output correctly',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'result': {'type': 'string'},
              'count': {'type': 'integer'},
              'success': {'type': 'boolean'},
            },
            'required': ['result', 'count', 'success'],
          });

          final agent = Agent(provider.name);

          final result = await agent.send(
            'Produce a JSON status summary for order processing. '
            'Set "result" to the sentence '
            '"Order processed for ${provider.name}". '
            'Set "count" to 42 and "success" to true.',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(
            json['result'].toString().toLowerCase().startsWith(
              'order processed for ${provider.name}'.toLowerCase(),
            ),
            isTrue,
            reason: 'Provider ${provider.name} should generate correct string',
          );
          expect(
            json['count'],
            equals(42),
            reason: 'Provider ${provider.name} should generate correct integer',
          );
          expect(
            json['success'],
            isTrue,
            reason: 'Provider ${provider.name} should generate correct boolean',
          );
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        timeout: const Timeout(Duration(minutes: 3)),
        skipProviders: {'together'},
      );
    });

    group('data types', () {
      runProviderTest(
        'handles all primitive types',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'string_field': {'type': 'string'},
              'integer_field': {'type': 'integer'},
              'number_field': {'type': 'number'},
              'boolean_field': {'type': 'boolean'},
              // 'null_field': {'type': 'null'}, // not all providers support
              // this, e.g. google
            },
            'required': [
              'string_field',
              'integer_field',
              'number_field',
              'boolean_field',
            ],
          });

          final agent = Agent(provider.name);
          final result = await agent.send(
            'Create object with: string_field="test", integer_field=42, '
            'number_field=3.14, boolean_field=true, null_field=null',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['string_field'], contains('test'));
          expect(json['integer_field'], equals(42));
          // Some models may return more precision than requested
          expect(
            json['number_field'],
            anyOf(equals(3.14), closeTo(3.14, 0.01)),
          );
          expect(json['boolean_field'], isTrue);
          // Google returns "null" as a string instead of actual null
          expect(json['null_field'], anyOf(isNull, equals('null')));
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );

      runProviderTest(
        'respects enum constraints',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'status': {
                'type': 'string',
                'enum': ['pending', 'approved', 'rejected'],
              },
              'priority': {
                'type': 'string',
                'enum': ['low', 'medium', 'high'],
              },
            },
            'required': ['status', 'priority'],
          });

          final agent = Agent(provider.name);
          final result = await agent.send(
            'Create object with status "approved" and priority "high"',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['status'], equals('approved'));
          expect(json['priority'], equals('high'));
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );

      runProviderTest(
        'handles numeric constraints',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'age': {'type': 'integer', 'minimum': 0, 'maximum': 150},
              'score': {'type': 'number', 'minimum': 0.0, 'maximum': 100.0},
            },
            'required': ['age', 'score'],
          });

          final agent = Agent(provider.name);

          final result = await agent.send(
            'Create a JSON record for customer Alex Rivera. '
            'The field "age" must be 25 (an integer between 0 and 150) and the '
            'field "score" must be 87.5 (a number between 0.0 and 100.0).',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['age'], equals(25));
          expect(json['age'], greaterThanOrEqualTo(0));
          expect(json['age'], lessThanOrEqualTo(150));
          expect(json['score'], equals(87.5));
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'cohere', 'together'},
      );
    });

    group('complex schemas', () {
      runProviderTest(
        'generates valid recursive structures',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'children': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                    'age': {'type': 'integer'},
                  },
                  'required': ['name'],
                },
              },
            },
            'required': ['name'],
          });

          final agent = Agent(provider.name);
          final result = await agent.send(
            'Create a parent named "John" with two children: "Alice" age 10 '
            'and "Bob" age 8',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['name'], isA<String>());
          expect(json['children'], isA<List>());
          expect(json['children'], isNotEmpty);
          if ((json['children'] as List).isNotEmpty) {
            expect(json['children'][0]['name'], isA<String>());
            expect(json['children'][0]['age'], isA<int>());
          }
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );

      runProviderTest(
        'handles union types with anyOf',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'value': {
                'anyOf': [
                  {'type': 'string'},
                  {'type': 'number'},
                  {'type': 'boolean'},
                ],
              },
            },
            'required': ['value'],
          });

          final agent = Agent(provider.name);

          // Test with string
          var result = await agent.send(
            'Create object with value "hello"',
            outputSchema: schema,
          );
          var json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['value'], equals('hello'));

          // Test with number
          result = await agent.send(
            'Create object with value 42',
            outputSchema: schema,
          );
          json = jsonDecode(result.output) as Map<String, dynamic>;
          // Providers may return numbers as strings for anyOf types - both are
          // valid
          expect(json['value'], anyOf(equals(42), equals('42')));
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'google', 'google-openai', 'together'},
      );
    });

    // Error cases moved to dedicated edge cases section

    group('provider differences', () {
      runProviderTest(
        'handles provider-specific formats',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'message': {'type': 'string'},
            },
            'required': ['message'],
          });

          // Different providers handle schemas differently internally but all
          // should produce valid JSON output through Agent
          final agent = Agent(provider.name);
          final result = await agent.send(
            'Create object with message "${provider.name} test"',
            outputSchema: schema,
          );
          expect(() => jsonDecode(result.output), returnsNormally);

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          // Models may change capitalization - check case-insensitively
          expect(
            json['message'].toString().toLowerCase(),
            equals('${provider.name} test'.toLowerCase()),
          );
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );
    });

    group('all providers - typed output', () {
      runProviderTest(
        'structured output works across supporting providers',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'value': {'type': 'integer'},
            },
            'required': ['name', 'value'],
          });

          final agent = Agent(provider.name);
          final result = await agent.send(
            'Create object with name "test" and value 123',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;

          expect(
            json['name'],
            equals('test'),
            reason: 'Provider ${provider.name} should return correct name',
          );
          expect(
            json['value'],
            equals(123),
            reason: 'Provider ${provider.name} should return correct value',
          );
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );
    });

    group('edge cases (limited providers)', () {
      runProviderTest(
        'handles schema validation errors',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'required_field': {'type': 'string'},
            },
            'required': ['required_field', 'another_required_field'], // Invalid
          });

          final agent = Agent(provider.name);

          final result = await agent.send(
            'Produce any JSON payload that satisfies the required fields of '
            'this schema. Use placeholder values if needed to keep the object '
            'valid.',
            outputSchema: schema,
          );

          expect(result.output, isNotEmpty);
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'google', 'google-openai', 'together'},
        edgeCase: true,
      );

      runProviderTest(
        'handles conflicting instructions',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'number': {'type': 'integer', 'minimum': 10, 'maximum': 20},
            },
            'required': ['number'],
          });

          final agent = Agent(provider.name);
          final result = await agent.send(
            'Finance requested a reminder. '
            'Return a JSON object where "number" respects the schema '
            '(between 10 and 20) even if someone insisted on setting it to 50.',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          final number = json['number'] as int?;
          expect(number, isNotNull);
          expect(number, lessThanOrEqualTo(20));
          expect(number, greaterThanOrEqualTo(10));
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        edgeCase: true,
      );
    });

    group('streaming typed output', () {
      runProviderTest(
        'streams JSON output correctly',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'message': {'type': 'string'},
              'count': {'type': 'integer'},
            },
            'required': ['message', 'count'],
          });

          final agent = Agent(provider.name);

          final buffer = StringBuffer();
          final messages = <ChatMessage>[];

          await for (final chunk in agent.sendStream(
            'Generate JSON with message "Hello from ${provider.name}" '
            'and count 42',
            outputSchema: schema,
          )) {
            buffer.write(chunk.output);
            messages.addAll(chunk.messages);
          }

          // Streaming only surfaces the JSON through chunk.output. Once the
          // stream ends we concatenate what we captured and decode it; the
          // final assistant message never restates the JSON for us.
          final json = jsonDecode(buffer.toString()) as Map<String, dynamic>;
          // Check case-insensitively as models may change capitalization
          expect(
            json['message'].toString().toLowerCase(),
            contains(provider.name.toLowerCase()),
          );
          expect(json['count'], equals(42));
          expect(messages, isNotEmpty);
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );

      runProviderTest(
        'handles complex schema in streaming',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'users': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'integer'},
                    'name': {'type': 'string'},
                    'active': {'type': 'boolean'},
                  },
                  'required': ['id', 'name', 'active'],
                },
              },
              'total': {'type': 'integer'},
            },
            'required': ['users', 'total'],
          });

          final agent = Agent(provider.name);

          final buffer = StringBuffer();

          await for (final chunk in agent.sendStream(
            'Create 2 users: Alice (id 1, active) and Bob (id 2, inactive). '
            'Include total count.',
            outputSchema: schema,
          )) {
            buffer.write(chunk.output);
          }

          final json = jsonDecode(buffer.toString()) as Map<String, dynamic>;
          expect(json['users'], hasLength(2));
          expect(json['users'][0]['name'], equals('Alice'));
          expect(json['users'][0]['active'], isTrue);
          expect(
            json['users'][1]['name'],
            anyOf(equals('Bob'), equals('Jones')),
          );
          expect(json['users'][1]['active'], isFalse);
          expect(json['total'], equals(2));
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );
    });

    group('runFor<T>() typed output', () {
      runProviderTest(
        'returns typed Map<String, dynamic>',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
              'country': {'type': 'string'},
            },
            'required': ['city', 'country'],
          });

          final agent = Agent(provider.name);

          final result = await agent.sendFor<Map<String, dynamic>>(
            'What is the capital of France? Return as city and country.',
            outputSchema: schema,
          );

          expect(result.output, isA<Map<String, dynamic>>());
          expect(result.output['city'], equals('Paris'));
          expect(result.output['country'], equals('France'));
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );

      test('returns custom typed objects - single provider', () async {
        // Test with just one provider to save time
        final provider = _typedOutputProvider;

        final agent = Agent(provider.name);

        final result = await agent.sendFor<WeatherReport>(
          'Create a weather report for London: 15C, cloudy, 70% humidity',
          outputSchema: WeatherReport.schema,
          outputFromJson: WeatherReport.fromJson,
        );

        expect(result.output, isA<WeatherReport>());
        expect(result.output.location, contains('London'));
        expect(result.output.temperature, equals(15));
        expect(result.output.conditions.toLowerCase(), equals('cloudy'));
        expect(result.output.humidity, equals(70));
      });

      runProviderTest(
        'handles nested custom types',
        (provider) async {
          final agent = Agent(provider.name);

          final result = await agent.sendFor<UserProfile>(
            'Create a user profile for John Doe, age 30, with email '
            '"john@example.com", dark theme preference, notifications on',
            outputSchema: UserProfile.schema,
            outputFromJson: UserProfile.fromJson,
          );

          expect(result.output, isA<UserProfile>());
          expect(result.output.name, equals('John Doe'));
          expect(result.output.age, equals(30));
          expect(result.output.email, equals('john@example.com'));
          expect(result.output.preferences.theme, contains('dark'));
          expect(result.output.preferences.notifications, isTrue);
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'together'},
      );
    });

    group('complex real-world schemas', () {
      // Tests nested schemas (4 levels deep to stay within provider limits)
      runProviderTest(
        'handles API response schema',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'success': {'type': 'boolean'},
              'users': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string'},
                    'username': {'type': 'string'},
                    'firstName': {'type': 'string'},
                    'lastName': {'type': 'string'},
                  },
                  'required': ['id', 'username', 'firstName', 'lastName'],
                },
              },
              'pagination': {
                'type': 'object',
                'properties': {
                  'page': {'type': 'integer'},
                  'perPage': {'type': 'integer'},
                  'total': {'type': 'integer'},
                  'totalPages': {'type': 'integer'},
                },
                'required': ['page', 'perPage', 'total', 'totalPages'],
              },
              'version': {'type': 'string'},
            },
            'required': ['success', 'users', 'pagination', 'version'],
          });

          final agent = Agent(provider.name);

          final result = await agent.send(
            'Return a JSON payload for GET /api/users. '
            'Mark "success" as true and include exactly two users: '
            'Alice Smith (id "1", username "alice") and '
            'Bob Jones (id "2", username "bob"). '
            'Set pagination to page 1 of 5 with perPage 10 and total 50. '
            'Set version to "1.0".',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['success'], isTrue);
          expect(json['users'], hasLength(2));
          expect(
            json['users'][0]['firstName'],
            anyOf(equals('Alice'), equals('Smith')),
          );
          expect(json['users'][1]['firstName'], equals('Bob'));
          expect(json['pagination']['page'], equals(1));
          expect(json['pagination']['totalPages'], equals(5));
          expect(json['version'], isNotEmpty);
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'google-openai', 'together'},
      );

      // Tests nested object schemas (4 levels deep to stay within provider
      // limits)
      runProviderTest(
        'handles nested configuration',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'version': {'type': 'string'},
              'authentication': {
                'type': 'object',
                'properties': {
                  'enabled': {'type': 'boolean'},
                  'providers': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                  'sessionTimeout': {'type': 'integer'},
                  'requireMFA': {'type': 'boolean'},
                },
                'required': ['enabled', 'providers', 'sessionTimeout'],
              },
            },
            'required': ['name', 'version', 'authentication'],
          });

          final agent = Agent(provider.name);

          final result = await agent.send(
            'Generate a JSON configuration for the SaaS product "MyApp". '
            'Set version to "1.0.0". '
            'In authentication, mark enabled=true, list '
            '["Google","GitHub"] as providers, and sessionTimeout=30.',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['name'], equals('MyApp'));
          // Some models prefix version with 'v'
          expect(json['version'], anyOf(equals('1.0.0'), equals('v1.0.0')));

          final auth = json['authentication'] as Map<String, dynamic>;
          expect(auth['enabled'], isTrue);
          // Some models return lowercase provider names
          final providers = (auth['providers'] as List)
              .map((p) => p.toString().toLowerCase())
              .toList();
          expect(providers, containsAll(['google', 'github']));
          // Some models interpret "30min" as 30, others as 1800 seconds
          expect(
            auth['sessionTimeout'],
            anyOf(equals(30), equals(1800), equals(1800000)),
          );
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        skipProviders: {'google-openai', 'together'},
      );
    });

    group('provider edge cases', () {
      runProviderTest(
        'handles unicode and special characters',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'message': {'type': 'string'},
              'emoji': {'type': 'string'},
              'special': {'type': 'string'},
            },
            'required': ['message', 'emoji', 'special'],
          });

          final agent = Agent(provider.name);

          final result = await agent.send(
            'Create object with message "Hello 世界", emoji "🌍", '
            'and special characters "<>&\'"',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['message'], contains('世界'));
          expect(json['emoji'], equals('🌍'));
          expect(json['special'], contains('&'));
          expect(json['special'], contains('<>'));
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        edgeCase: true,
        skipProviders: {'together'},
      );

      runProviderTest(
        'handles empty collections',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'emptyArray': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'emptyObject': {'type': 'object'},
              'nullableField': {
                'type': ['string', 'null'],
              },
            },
            'required': ['emptyArray', 'emptyObject'],
          });

          final agent = Agent(provider.name);

          final result = await agent.send(
            'Create object with empty array, empty object, and null for '
            'nullable field',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['emptyArray'], isEmpty);
          expect(json['emptyObject'], isA<Map>());
          expect(json['emptyObject'], isEmpty);
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        edgeCase: true,
        skipProviders: {'google', 'google-openai', 'together'},
      );

      runProviderTest(
        'handles large numeric values',
        (provider) async {
          final schema = js.JsonSchema.create({
            'type': 'object',
            'properties': {
              'largeInt': {'type': 'integer'},
              'preciseFloat': {'type': 'number'},
              'scientificNotation': {'type': 'number'},
            },
            'required': ['largeInt', 'preciseFloat', 'scientificNotation'],
          });

          final agent = Agent(provider.name);

          final result = await agent.send(
            'Create object with largeInt: 9007199254740991, '
            'preciseFloat: 3.141592653589793, scientificNotation: 6.022e23',
            outputSchema: schema,
          );

          final json = jsonDecode(result.output) as Map<String, dynamic>;
          expect(json['largeInt'], greaterThan(1000000));
          expect(json['preciseFloat'].toString(), contains('3.14'));
          expect(json['scientificNotation'], greaterThan(1e20));
        },
        requiredCaps: {ProviderTestCaps.typedOutput},
        edgeCase: true,
        skipProviders: {'together'},
      );
    });
  });
}

// Custom classes for typed output tests
class WeatherReport {
  const WeatherReport({
    required this.location,
    required this.temperature,
    required this.conditions,
    required this.humidity,
  });

  factory WeatherReport.fromJson(Map<String, dynamic> json) => WeatherReport(
    location: json['location'] as String,
    temperature: json['temperature'] as int,
    conditions: json['conditions'] as String,
    humidity: json['humidity'] as int,
  );

  static final schema = js.JsonSchema.create({
    'type': 'object',
    'properties': {
      'location': {'type': 'string'},
      'temperature': {'type': 'integer'},
      'conditions': {'type': 'string'},
      'humidity': {'type': 'integer'},
    },
    'required': ['location', 'temperature', 'conditions', 'humidity'],
  });

  final String location;
  final int temperature;
  final String conditions;
  final int humidity;
}

class UserPreferences {
  const UserPreferences({required this.theme, required this.notifications});

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        theme: json['theme'] as String,
        notifications: json['notifications'] as bool,
      );

  final String theme;
  final bool notifications;
}

class UserProfile {
  const UserProfile({
    required this.name,
    required this.age,
    required this.email,
    required this.preferences,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'] as String,
    age: json['age'] as int,
    email: json['email'] as String,
    preferences: UserPreferences.fromJson(
      json['preferences'] as Map<String, dynamic>,
    ),
  );

  static final schema = js.JsonSchema.create({
    'type': 'object',
    'properties': {
      'name': {'type': 'string'},
      'age': {'type': 'integer'},
      'email': {'type': 'string'},
      'preferences': {
        'type': 'object',
        'properties': {
          'theme': {'type': 'string'},
          'notifications': {'type': 'boolean'},
        },
        'required': ['theme', 'notifications'],
      },
    },
    'required': ['name', 'age', 'email', 'preferences'],
  });

  final String name;
  final int age;
  final String email;
  final UserPreferences preferences;
}
