import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

/// Runs a parameterized test across every provider selected by the filters.
void runProviderTest(
  String description,
  Future<void> Function(Provider provider) testFunction, {
  Set<ProviderCaps>? requiredCaps,
  bool edgeCase = false,
  Timeout? timeout,
  Set<String>? skipProviders,
  String Function(Provider provider, String defaultLabel)? labelBuilder,
}) {
  final normalizedSkips =
      skipProviders?.map((name) => name.toLowerCase()).toSet() ?? const {};

  final providerEntries = edgeCase
      ? <({Provider provider, String defaultLabel})>[
          (
            provider: Providers.get('google'),
            defaultLabel: 'google:gemini-2.5-flash',
          ),
        ]
      : Providers.all
            .where(
              (p) =>
                  requiredCaps == null ||
                  requiredCaps.every((cap) => p.caps.contains(cap)),
            )
            .map(
              (p) => (
                provider: p,
                defaultLabel:
                    '${p.name}:${p.defaultModelNames[ModelKind.chat]}',
              ),
            );

  for (final entry in providerEntries) {
    final provider = entry.provider;
    final providerName = provider.name.toLowerCase();
    final isSkipped = normalizedSkips.contains(providerName);
    final label =
        labelBuilder?.call(provider, entry.defaultLabel) ?? entry.defaultLabel;

    test(
      '$label: $description',
      () async {
        await testFunction(provider);
      },
      timeout: timeout,
      skip: isSkipped,
    );
  }
}
