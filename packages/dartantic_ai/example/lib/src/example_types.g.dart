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

// **************************************************************************
// SotiSchemaGenerator
// **************************************************************************

const _$TownAndCountrySchemaMap = <String, dynamic>{
  r'''$schema''': r'''https://json-schema.org/draft/2020-12/schema''',
  r'''type''': r'''object''',
  r'''properties''': {
    r'''town''': {r'''type''': r'''string'''},
    r'''country''': {r'''type''': r'''string'''},
  },
  r'''required''': [r'''town''', r'''country'''],
  r'''$defs''': {},
};
