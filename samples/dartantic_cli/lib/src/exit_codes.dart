/// Exit codes per CLI specification
abstract final class ExitCodes {
  static const int success = 0;
  static const int generalError = 1;
  static const int invalidArguments = 2;
  static const int configurationError = 3;
  static const int apiError = 4;
  static const int networkError = 5;
}
