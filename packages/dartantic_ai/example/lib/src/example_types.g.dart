// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'example_types.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TownAndCountry _$TownAndCountryFromJson(Map<String, dynamic> json) =>
    TownAndCountry(
      town: json['town'] as String,
      country: json['country'] as String,
    );

Map<String, dynamic> _$TownAndCountryToJson(TownAndCountry instance) =>
    <String, dynamic>{'town': instance.town, 'country': instance.country};

TimeAndTemperature _$TimeAndTemperatureFromJson(Map<String, dynamic> json) =>
    TimeAndTemperature(
      time: DateTime.parse(json['time'] as String),
      temperature: (json['temperature'] as num).toDouble(),
    );

Map<String, dynamic> _$TimeAndTemperatureToJson(TimeAndTemperature instance) =>
    <String, dynamic>{
      'time': instance.time.toIso8601String(),
      'temperature': instance.temperature,
    };
