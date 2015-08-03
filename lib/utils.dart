library dsa.utils;

import "dart:async";
import "dart:convert";

import "package:crypto/crypto.dart";
import "io.dart";

String encodeBase64(String input) {
  var bytes = UTF8.encode(input);

  return CryptoUtils.bytesToBase64(bytes);
}

String decodeBase64(String input) {
  return UTF8.decode(CryptoUtils.base64StringToBytes(input));
}

Future<Map<String, dynamic>> fetchDistributionData() async {
  return await fetchJSON("https://raw.githubusercontent.com/IOT-DSA/dists/gh-pages/dists.json");
}
