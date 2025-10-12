/// Shared helpers for Google Gemini provider and models.
class GoogleApiConfig {
  GoogleApiConfig._();

  /// Default base URL for the Google Gemini API.
  static final Uri defaultBaseUrl = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta',
  );
}

/// Normalizes a Google model name to include the required `models/` prefix.
String normalizeGoogleModelName(String model) =>
    model.contains('/') ? model : 'models/$model';
