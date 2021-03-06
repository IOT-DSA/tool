library dsa.cfg;

import "dart:async";
import "dart:io";
import "dart:convert";

String _cfgFilePath = _getConfigFilePath();

String _getConfigFilePath() {
  if (Platform.isWindows) {
    return "${Platform.environment['HOMEPATH']}/DSA/Tool/config.json";
  } else {
    return "${Platform.environment['HOME']}/.dsa/tool/config.json";
  }
}

Future<Map<String, dynamic>> readConfigFile() async {
  File file = new File(_cfgFilePath);

  if (!(await file.exists())) {
    await file.create(recursive: true);
    await file.writeAsString("{}");
  }

  var content = await file.readAsString();

  return JSON.decode(content);
}

Future writeConfigFile(json) async {
  File file = new File(_cfgFilePath);

  if (!(await file.exists())) {
    await file.create(recursive: true);
  }

  await file.writeAsString(new JsonEncoder.withIndent("  ").convert(json) + "\n");
}
