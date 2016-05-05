part of dsa.tasks;

class RegexReplaceTaskDefinition extends TaskDefinition {
  @override
  Future<bool> claim(EntityConfiguration config) async {
    return config.get("replace") == "regex" && config.has("regex");
  }

  @override
  Future execute(TaskSubject subject, EntityConfiguration config) async {
    RegExp regex = new RegExp(config.get("regex"));
    Map withReplacements = config.get("with");
    String inPath = config.get("in");
    File file = subject.getFile(inPath);
    var content = await file.readAsString();
    for (Match match in regex.allMatches(content)) {
      var orig = match.group(0);
      var out = orig;

      for (int k in withReplacements.keys) {
        var doReplace = match.group(k);
        var to = withReplacements[k];

        out = out.replaceAll(doReplace, to);
      }

      content = content.replaceAll(orig, out);
    }
    await file.writeAsString(content);
  }
}
