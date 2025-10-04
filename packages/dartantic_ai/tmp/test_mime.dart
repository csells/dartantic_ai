import 'dart:convert';
import 'dart:typed_data';
import 'package:mime/mime.dart';
import 'package:dartantic_interface/dartantic_interface.dart';

void main() {
  const fakeImageData = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
  final decodedBytes = Uint8List.fromList(base64Decode(fakeImageData));
  
  print('Decoded bytes length: ${decodedBytes.length}');
  print('First few bytes: ${decodedBytes.take(10).toList()}');
  
  final mimeType1 = lookupMimeType('', headerBytes: decodedBytes);
  print('lookupMimeType with empty path: $mimeType1');
  
  final mimeType2 = lookupMimeType('image.bin', headerBytes: decodedBytes);
  print('lookupMimeType with image.bin: $mimeType2');
  
  final ext1 = Part.extensionFromMimeType('image/png');
  print('Part.extensionFromMimeType(image/png): "$ext1"');
  
  final ext2 = Part.extensionFromMimeType(mimeType2 ?? 'unknown');
  print('Part.extensionFromMimeType(detected): "$ext2"');
}
