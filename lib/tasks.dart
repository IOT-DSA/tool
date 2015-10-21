library dsa.tasks;

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:path/path.dart" as pathlib;
import "package:yaml/yaml.dart" show loadYaml;

import "utils.dart";
import "io.dart";

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

  void populateVariables(Map<String, dynamic> variables);
}

class MapEntityConfiguration extends EntityConfiguration {
  final Map<String, dynamic> config;

  Map _cachedConfig;

  MapEntityConfiguration(this.config) {
    _cachedConfig = new Map.from(config);
  }

  @override
  get(String key) => config[key];

  @override
  bool has(String key) => config.containsKey(key);

  @override
  void populateVariables(Map<String, dynamic> variables) {
    config.clear();
    config.addAll(_cachedConfig);
    crawlDataAndSubstituteVariables(config, variables);
  }
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
        c.populateVariables(subject.attributes);
        var dir = Directory.current;
        Directory.current = subject.directory;
        await task.execute(subject, c);
        Directory.current = dir;
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

class ExecuteTaskDefinition extends TaskDefinition {
  @override
  Future<bool> claim(EntityConfiguration config) async {
    return config.has("execute");
  }

  @override
  Future execute(TaskSubject subject, EntityConfiguration config) async {
    var cmd = config.get("execute");
    if (cmd is List) {
      cmd = cmd.join(" ");
    }
    var exe = Platform.isWindows ? "cmd.exe" : "bash";
    var args = [Platform.isWindows ? "/C" : "-c", cmd];

    var env = {};

    if (config.has("env")) {
      var e = config.get("env");
      if (e is List) {
        for (String x in e) {
          var p = x.split("=");
          var k = p[0];
          var v = p.skip(1).join("=");
          env[k] = v;
        }
      } else {
        env = e;
      }
    }

    var inheritStdin = config.get("stdin") == true;

    await exec(exe, args: args, inherit: true, inheritStdin: inheritStdin, environment: env);
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
      subject.setAttribute("link.description", json["description"]);
      subject.setAttribute("link.version", json["version"]);
    }
  }
}

executeBatchFile(String path, [Map<String, dynamic> arguments]) async {
  var file = new File(path);
  var content = await file.readAsString();
  var json = deepCopy(loadYaml(content));

  var filterConfigurations = json["filters"];
  var taskConfigurations = json["execute"];

  if (filterConfigurations == null) {
    filterConfigurations = [];
  }

  if (taskConfigurations == null) {
    taskConfigurations = json["tasks"];
  }

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

  List<EntityConfiguration> fconfigs =
    filterConfigurations.map((x) => new MapEntityConfiguration(x)).toList();
  List<EntityConfiguration> tconfigs =
    taskConfigurations.map((x) => new MapEntityConfiguration(x)).toList();
  subjects = await filterEvaluator.evaluate(fconfigs, subjects);

  var evaluator = new TaskEvaluator([
    new RegexReplaceTaskDefinition(),
    new MergeJsonTaskDefinition(),
    new ExecuteTaskDefinition(),
    new SayTaskDefinition(),
    new GitTaskDefinition()
  ]);

  for (var subject in subjects) {
    await evaluator.run(subject, tconfigs);
  }
}

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

dynamic deepCopy(input) {
  if (input is Map) {
    var out = {};
    for (var key in input.keys) {
      out[deepCopy(key)] = deepCopy(input[key]);
    }
    return out;
  } else if (input is List) {
    var out = [];
    for (var e in input) {
      out.add(deepCopy(e));
    }
    return out;
  } else {
    return input;
  }
}