import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';

final tools = [
  Tool(
    name: 'current-time',
    description: 'Get the current time.',
    onCall: (args) async => {'result': DateTime.now().toIso8601String()},
  ),
  Tool(
    name: 'current-date',
    description: 'Get the current date.',
    onCall: (args) async => {'result': DateTime.now().toIso8601String()},
  ),
  Tool(
    name: 'weather',
    description: 'Get the weather for a US zipcode',
    inputSchema: JsonSchema.create({
      'type': 'object',
      'properties': {
        'zipcode': {
          'type': 'string',
          'description': 'The US zipcode to get the weather for.',
        },
      },
      'required': ['zipcode'],
    }),
    onCall: (input) async {
      final zipcode = (input as Map<String, dynamic>)['zipcode'] as String;
      final url = Uri.parse('https://wttr.in/US~$zipcode?format=j1');
      final response = await http.get(url);
      if (response.statusCode != 200) {
        return {'error': 'Error getting weather: ${response.body}'};
      }

      return {'result': jsonDecode(response.body)};
    },
  ),
  Tool(
    name: 'location-lookup',
    description: 'Get location data for a given search query.',
    inputSchema: JsonSchema.create({
      'type': 'object',
      'properties': {
        'location': {
          'type': 'string',
          'description': 'The location to get the data for.',
        },
      },
      'required': ['location'],
    }),
    onCall: (input) async {
      final location = (input as Map<String, dynamic>)['location'] as String;
      try {
        final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
          'q': location,
          'format': 'jsonv2',
          'addressdetails': '1',
          'extratags': '1',
          'namedetails': '1',
        });
        final response = await http.get(uri);
        final searchResults = json.decode(response.body) as List<dynamic>;

        if (searchResults.isEmpty) {
          return {'error': 'Could not find a location for $location'};
        }

        return {'result': searchResults};
      } on Exception catch (e) {
        return {'error': 'Could not find a location for $location: $e'};
      }
    },
  ),
  Tool(
    name: 'surf-web',
    description: 'Get the content of a web page.',
    inputSchema: JsonSchema.create({
      'type': 'object',
      'properties': {
        'link': {
          'type': 'string',
          'description': 'The URL of the web page to get the content of.',
        },
      },
      'required': ['link'],
    }),
    onCall: (args) async {
      final link = (args as Map<String, dynamic>)['link'] as String?;
      if (link == null) {
        return {'error': 'link is required'};
      }
      final uri = Uri.parse(link);
      final response = await http.get(uri);
      return {'result': response.body};
    },
  ),
];
