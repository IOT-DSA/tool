part of dsa.tasks;

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
