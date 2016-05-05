part of dsa.tasks;

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

          if (isEqual != null) {
            if (isEqual is List) {
              pass = isEqual.contains(value);
            } else {
              pass = value == isEqual;
            }
          }
          if (pass && isNotEqual != null) {
            if (isNotEqual is List) {
              pass = !isNotEqual.contains(value);
            } else {
              pass = value != isNotEqual;
            }
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
