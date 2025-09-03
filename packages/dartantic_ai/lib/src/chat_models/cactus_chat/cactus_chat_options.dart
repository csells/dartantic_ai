import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:meta/meta.dart';

/// Options to pass into Cactus.
@immutable
class CactusChatOptions extends ChatModelOptions {
  /// Creates a new Cactus chat options instance.
  const CactusChatOptions({
    this.maxTokens,
  });

  /// The maximum number of tokens to generate before stopping.
  ///
  /// Note that our models may stop _before_ reaching this maximum. This
  /// parameter only specifies the absolute maximum number of tokens to
  /// generate.
  final int? maxTokens;
}
