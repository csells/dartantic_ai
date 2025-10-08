import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

/// Runs a parameterized test across every provider selected by the filters.
void runProviderTest(
  String description,
  Future<void> Function(Provider provider) testFunction, {
  Set<ProviderCaps>? requiredCaps,
  bool edgeCase = false,
  Timeout? timeout,
  Set<String>? skipProviders,
}) {
  final normalizedSkips =
      skipProviders?.map((name) => name.toLowerCase()).toSet() ?? const {};

  final providers = edgeCase
      ? ['google:gemini-2.5-flash'] // Edge cases on Google only
      : Providers.all
            .where(
              (p) =>
                  requiredCaps == null ||
                  requiredCaps.every((cap) => p.caps.contains(cap)),
            )
            .map((p) => '${p.name}:${p.defaultModelNames[ModelKind.chat]}');

  for (final providerModel in providers) {
    test(
      '$providerModel: $description',
      () async {
        final parts = providerModel.split(':');
        final providerName = parts[0];

        if (normalizedSkips.contains(providerName.toLowerCase())) {
          return;
        }

        final provider = Providers.get(providerName);

        await testFunction(provider);
      },
      timeout: timeout ?? const Timeout(Duration(seconds: 30)),
    );
  }
}
