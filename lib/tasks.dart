library dsa.tasks;

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:path/path.dart" as pathlib;
import "package:yaml/yaml.dart" show loadYaml;

import "utils.dart";
import "io.dart";

part "tasks/base.dart";
part "tasks/execute.dart";
part "tasks/file_exists.dart";
part "tasks/merge_json.dart";
part "tasks/regex.dart";
part "tasks/say.dart";
part "tasks/git.dart";
part "tasks/dslink_populator.dart";

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
