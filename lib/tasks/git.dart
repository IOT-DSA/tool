part of dsa.tasks;

class GitTaskDefinition extends ExecuteTaskDefinition {
  @override
  Future<bool> claim(EntityConfiguration config) async {
    return config.has("git");
  }

  @override
  Future execute(TaskSubject subject, EntityConfiguration config) async {
    var n = config.get("git");

    if (n is String) {
      n = n.split(" ");
    }

    List list = n;
    list.insert(0, "git");
    var a = new MapEntityConfiguration({
      "execute": list
    });

    await super.execute(subject, a);
  }
}
