part of dsa.tasks;

class FileExistsFilter extends TaskFilter {
  @override
  Future<bool> accept(TaskSubject subject, EntityConfiguration config) async =>
    await subject.hasFile(config.get("file"));
}
