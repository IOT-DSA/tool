part of dsa.tasks;

class SayTaskDefinition extends TaskDefinition {
  @override
  Future<bool> claim(EntityConfiguration config) async {
    return config.has("say");
  }

  @override
  Future execute(TaskSubject subject, EntityConfiguration config) async {
    print(config.get("say"));
  }
}
