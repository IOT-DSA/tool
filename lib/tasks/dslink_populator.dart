part of dsa.tasks;

class DSLinkTaskSubjectPopulator extends TaskSubjectPopulator {
  @override
  Future populate(TaskSubject subject) async {
    if (await subject.hasFile("dslink.json")) {
      var json = await subject.readJsonFile("dslink.json");

      String name = json["name"];
      List<String> parts = name.split("-");
      String type = "unknown";
      if (parts.length > 1) {
        type = parts[1];
      }
      subject.setAttribute("link.name", name);
      subject.setAttribute("link.type", type);
      subject.setAttribute("link.description", json["description"]);
      subject.setAttribute("link.version", json["version"]);
    }
  }
}
