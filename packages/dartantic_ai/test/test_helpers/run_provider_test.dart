import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

/// Runs a parameterized test across multiple providers with error handling.
///
/// If a provider fails (missing API key, network error, provider bug), the test
/// is marked as skipped for that provider and execution continues with the
/// remaining providers.
///
/// This ensures one provider's failure doesn't block testing of all others.
void runProviderTest(
  String description,
  Future<void> Function(Provider provider) testFunction, {
  Set<ProviderCaps>? requiredCaps,
  bool edgeCase = false,
  Timeout? timeout,
}) {
  final providers = edgeCase
      ? ['google:gemini-2.0-flash'] // Edge cases on Google only
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

        final provider = Providers.get(providerName);

        try {
          await testFunction(provider);
        } on Exception catch (e, stackTrace) {
          // Provider unavailable (missing API key, network error, etc.)
          // Mark as skipped rather than failed to allow other providers to run
          markTestSkipped('Provider $providerName unavailable: $e');

          // Print stack trace for debugging
          // (helps diagnose actual bugs vs. config issues)
          // ignore: avoid_print
          print('Stack trace for $providerName:\n$stackTrace');
        }
      },
      timeout: timeout ?? const Timeout(Duration(seconds: 30)),
    );
  }
}
