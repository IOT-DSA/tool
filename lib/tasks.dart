library dsa.tasks;

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:path/path.dart" as pathlib;
import "package:yaml/yaml.dart" show loadYaml;

class TaskSubject {
  final Directory directory;

  TaskSubject(this.directory);

  Future<bool> hasFile(String path) async {
    return await getFile(path).exists();
  }

  Future<dynamic> readJsonFile(String path) async {
    var file = getFile(path);
    return const JsonDecoder().convert(await file.readAsString());
  }

  File getFile(String path) {
    return new File(pathlib.join(directory.path, path));
  }

  bool hasAttribute(String key) => attributes.containsKey(key);
  getAttribute(String key) => attributes[key];
  void setAttribute(String key, value) => attributes[key] = value;

  Map<String, dynamic> attributes = {};

  @override
  String toString() => "TaskSubject(${directory.path})";
}

abstract class TaskSubjectPopulator {
  Future populate(TaskSubject subject);
}

abstract class EntityConfiguration {
  dynamic get(String key);
  bool has(String key);
}

class MapEntityConfiguration extends EntityConfiguration {
  final Map<String, dynamic> config;

  MapEntityConfiguration(this.config);

  @override
  get(String key) => config[key];

  @override
  bool has(String key) => config.containsKey(key);
}

abstract class TaskFilter {
  Future<bool> accept(TaskSubject subject, EntityConfiguration config);
}

class FilterEvaluator {
  final Map<String, TaskFilter> filterTypes;

  FilterEvaluator(this.filterTypes);

  Future<List<TaskSubject>> evaluate(List<EntityConfiguration> filters, List<TaskSubject> subjects) async {
    var out = <TaskSubject>[];
    subjectLoop: for (TaskSubject subject in subjects) {
      filterLoop: for (EntityConfiguration c in filters) {
        String where = c.get("where");

        bool pass = true;
        if (filterTypes.containsKey(where)) {
          pass = await filterTypes[where].accept(subject, c);
        } else {
          var value = subject.getAttribute(where);
          var isEqual = c.get("is");
          var isNotEqual = c.get("is_not");
          List<dynamic> isIn = c.get("is_in");

          if (isEqual != null) {
            pass = value == isEqual;
          } else if (isNotEqual != null) {
            pass = value != isNotEqual;
          } else if (isIn != null) {
            pass = isIn.contains(value);
          }
        }

        if (!pass) {
          continue subjectLoop;
        }
      }

      out.add(subject);
    }
    return out;
  }
}

abstract class TaskDefinition {
  Future<bool> claim(EntityConfiguration config);
  Future execute(TaskSubject subject, EntityConfiguration config);
}

class TaskEvaluator {
  final List<TaskDefinition> tasks;

  TaskEvaluator(this.tasks);

  run(TaskSubject subject, List<EntityConfiguration> configs) async {
    for (var c in configs) {
      TaskDefinition task;
      taskLoop: for (task in tasks) {
        if (await task.claim(c)) {
          break taskLoop;
        }
      }

      if (task != null) {
        await task.execute(subject, c);
      }
    }
  }
}

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

class FileExistsFilter extends TaskFilter {
  @override
  Future<bool> accept(TaskSubject subject, EntityConfiguration config) async =>
    await subject.hasFile(config.get("file"));
}

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
    }
  }
}

executeBatchFile(String path) async {
  var file = new File(path);
  var content = await file.readAsString();
  var json = loadYaml(content);

  var filterConfigurations = json["filters"];
  var taskConfigurations = json["execute"];

  var dirs = await Directory.current.list().where((x) => x is Directory).toList();
  dirs = dirs.where((x) => new File("${x.path}/dslink.json").existsSync()).toList();
  List<TaskSubject> subjects = dirs.map((x) => new TaskSubject(x)).toList();
  List<TaskSubjectPopulator> populators = [
    new DSLinkTaskSubjectPopulator()
  ];

  for (var p in populators) {
    for (var subject in subjects) {
      await p.populate(subject);
    }
  }

  var filterEvaluator = new FilterEvaluator({
    "file.exists": new FileExistsFilter()
  });

  var fconfigs = filterConfigurations.map((x) => new MapEntityConfiguration(x)).toList();
  var tconfigs = taskConfigurations.map((x) => new MapEntityConfiguration(x)).toList();
  subjects = await filterEvaluator.evaluate(fconfigs, subjects);

  var evaluator = new TaskEvaluator([new RegexReplaceTaskDefinition()]);
  for (var subject in subjects) {
    await evaluator.run(subject, tconfigs);
  }
}