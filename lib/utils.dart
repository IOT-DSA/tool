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

String getLinkType(String name) {
  if (!name.contains("-") || !name.startsWith("dslink-")) return "unknown";
  var parts = name.split("-");

  if (parts.length == 2) {
    return "unknown";
  }

  return parts[1];
}

Map merge(Map a, Map b, {bool uniqueCollections: true, bool allowDirectives: false}) {
  var out = {};
  for (var key in a.keys) {
    var value = a[key];

    if (allowDirectives) {
      if (b.containsKey("!remove")) {
        var rm = b["!remove"];
        if (rm is String && rm == key) {
          continue;
        } else if (rm is List && rm.contains(key)) {
          continue;
        }
      } else if (value is List && b.containsKey("${key}!remove")) {
        b["${key}!remove"].forEach((a) => value.removeWhere((x) => x == a));
      }
    }

    if (b.containsKey(key)) {
      var bval = b[key];

      if (value is Map && bval is Map) {
        value = merge(value, bval, uniqueCollections: uniqueCollections, allowDirectives: allowDirectives);
      } else if (value is List && bval is List) {
        var tmp = uniqueCollections ? new Set() : [];
        tmp.addAll(value);
        tmp.addAll(bval);

        value = tmp.toList();
      }
    }
    out[key] = value;
  }

  for (var key in b.keys) {
    var value = b[key];

    if (allowDirectives && key is String && key.endsWith("!remove"))
      continue;

    if (!a.containsKey(key)) {
      out[key] = value;
    }
  }

  return out;
}

void crawlDataAndSubstituteVariables(input, Map<String, dynamic> variables) {
  String handleString(String input) {
    for (var key in variables.keys) {
      var value = variables[key];
      input = input.replaceAll(r"${" + key + "}", value);
    }
    return input;
  }

  if (input is List) {
    for (var i = 0; i < input.length; i++) {
      var e = input[i];
      if (e is! String) {
        crawlDataAndSubstituteVariables(e, variables);
      } else {
        input[i] = handleString(e);
      }
    }
  } else if (input is Map) {
    for (var key in input.keys.toList()) {
      var value = input[key];

      if (value is! String) {
        crawlDataAndSubstituteVariables(value, variables);
      } else {
        input[key] = handleString(value);
      }
    }
  }
}