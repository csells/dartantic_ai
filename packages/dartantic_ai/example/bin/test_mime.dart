import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:dartantic_interface/dartantic_interface.dart';

void main() async {
  const path = 'bin/files/bio.txt';
  final file = XFile.fromData(await File(path).readAsBytes(), path: path);
  final part = await DataPart.fromFile(file);
  print('File: $path');
  print('MimeType: ${part.mimeType}');
  print('Name: ${part.name}');
}
