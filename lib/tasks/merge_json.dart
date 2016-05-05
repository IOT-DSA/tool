part of dsa.tasks;

class MergeJsonTaskDefinition extends TaskDefinition {
  @override
  Future<bool> claim(EntityConfiguration config) async {
    return config.has("merge");
  }

  @override
  Future execute(TaskSubject subject, EntityConfiguration config) async {
    String inPath = config.get("into");
    File file = subject.getFile(inPath);
    var content = await file.readAsString();
    var json = JSON.decode(content);
    json = merge(json, config.get("merge"));
    await file.writeAsString(
      const JsonEncoder.withIndent("  ").convert(json) +
        "\n"
    );
  }
}
