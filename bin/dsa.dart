import "dart:convert";
import "dart:io";

import "package:args/args.dart";
import "package:dslink/utils.dart" show DSLinkJSON;
import "package:dsa_tool/github.dart";
import "package:dsa_tool/cfg.dart";
import "package:dsa_tool/utils.dart";
import "package:legit/legit.dart";
import "package:dsa_tool/io.dart";
import "package:dsa_tool/tasks.dart";
import "package:console/console.dart";
import "package:dsa_tool/help.dart";
import "package:dsa_tool/globals.dart";

ArgParser topLevelParser;

usage({String message, String command}) {
  if (message != null) {
    print("ERROR: ${message}");
  }

  print("Usage: dsa ${command != null ? command : "<command>"} [options]");

  if (command == null) {
    print("Commands: ${topLevelParser.commands.keys.join(", ")}");
    if (topLevelParser.usage.isNotEmpty) {
      print(topLevelParser.usage);
    }
  } else {
    var p = topLevelParser;

    var split = command.split(" ");
    for (var i = 0; i < split.length; i++) {
      p = p.commands[split[i]];
    }

    if (p.commands.isNotEmpty) {
      print("Commands: ${p.commands.keys.join(", ")}");
    }

    if (p.usage.isNotEmpty) {
      print(p.usage);
    }
  }

  exit(1);
}

main(List<String> args) async {
  var argp = new ArgParser(allowTrailingOptions: true);
  topLevelParser = argp;

  argp.addCommand("link", createLinkParser());
  argp.addCommand("setup", createSetupParser());
  argp.addCommand("get-dist", createGetDistParser());
  argp.addCommand("get", createGetParser());
  argp.addCommand("batch", createBatchParser());
  argp.addCommand("help", createHelpParser());
  var opts = argp.parse(args);

  if (opts.command == null) {
    usage(message: "No Command Specified");
  }

  config = await readConfigFile();

  if (opts.command.name == "link") {
    await handleLinkCommand(opts.command);
  } else if (opts.command.name == "setup") {
    await handleSetupCommand(opts.command);
  } else if (opts.command.name == "get-dist") {
    await handleGetDistCommand(opts.command);
  } else if (opts.command.name == "get") {
    await handleGetCommand(opts.command);
  } else if (opts.command.name == "batch") {
    await handleBatchCommand(opts.command);
  } else if (opts.command.name == "help") {
    await handleHelpCommand(opts.command);
  } else {
    usage(message: "Unknown Command");
  }

  if (autoExit) {
    github.dispose();
    exit(0);
  }
}

handleHelpCommand(ArgResults opts) async {
  print(HELP_COMMAND.trim());
}

bool autoExit = true;

handleBatchRunCommand(ArgResults opts) async {
  if (opts.rest.length != 1) {
    usage(message: "Task file not specified", command: "batch");
  }

  var file = new File(opts.rest[0]);
  if (!(await file.exists())) {
    print("ERROR: ${file.path} does not exist.");
    exit(1);
  }
  await executeBatchFile(file.path);
}

handleGetDistCommand(ArgResults opts) async {
  if (opts.rest.length < 1) {
    usage(command: "get-dist", message: "No Distribution Specified");
  }

  var dn = opts.rest[0];

  if (dn == "dglux-server") {
    dn = "dglux_server";
  }

  var dists = (await fetchDistributionData())["dists"];
  var dist = dists[dn];

  if (dist == null) {
    print("ERROR: No Such Distribution: ${dn}");
    exit(1);
    return;
  }

  var buildNumber = dist["latest"];
  var file = dist["file"];

  var rp = opts.rest.length > 1 ? opts.rest.skip(1).join(" ") : (dist["directoryName"] != null ? dist["directoryName"] : dn);

  print("Fetching Distribution...");
  var bytes = await fetchUrl("https://raw.githubusercontent.com/IOT-DSA/dists/gh-pages/${dn}/${buildNumber}/${file}");
  print("Extracting Distribution...");
  await extractArchiveSmart(bytes, new Directory(rp), handleSingleDirectory: true);
  print("Complete.");
}

handleGetCommand(ArgResults opts) async {
  if (opts.rest.length < 1) {
    usage(message: "Repository not specified", command: "get");
  }

  var name = opts.rest[0];
  var target = opts.rest.length == 1 ? name : opts.rest.skip(1).join(" ");

  var dir = new Directory(target);

  if (!(await dir.exists())) {
    await dir.create(recursive: true);
  }

  Repository repo = await listDsaRepositories()
      .firstWhere((repo) => repo.name == name || repo.fullName == name);

  await GitClient.handleConfigure(() async {
    GitClient git = new GitClient.forDirectory(new Directory(target));
    var result = await git.clone(repo.cloneUrls.https, recursive: true);

    if (!result) {
      print("Failed to get ${name}!");
      exit(1);
    } else {
      print("Success.");
    }
  }, inherit: true);
}

handleSetupCommand(ArgResults opts) async {
  if ((config["github_username"] == null ||
    config["github_password"] == null) ||
    await new Prompter("You have already logged into GitHub. Would you like to do it again? (Y/n) ").ask()) {
    var username = await new Prompter("GitHub Username: ").prompt();
    var password = await new Prompter("GitHub Password: ", secret: true).prompt();
    print("");

    github.auth = new Authentication.basic(username, password);
    try {
      var user = await github.users.getCurrentUser();
      print("Hello, ${user.name == null ? user.login : user.name}!");
      config["github_username"] = encodeBase64(username);
      config["github_password"] = encodeBase64(password);
    } catch (e) {
      print("ERROR: Failed to login to GitHub.");
      exit(1);
    }
  }

  await writeConfigFile(config);
  print("Setup Completed.");
}

loginToGitHub() async {
  var username = config["github_username"];
  var password = config["github_password"];

  if (username == null || password == null) {
    print("ERROR: Please run 'dsa setup' to setup your GitHub credentials.");
    exit(1);
  }

  github.auth = new Authentication.basic(decodeBase64(username), decodeBase64(password));

  try {
    await github.users.getCurrentUser();
  } catch (e) {
    print("Failed to login to GitHub.");
    exit(1);
  }
}

handleBatchCommand(ArgResults opts) async {
  if (opts.command == null) {
    usage(command: "batch");
  }

  if (opts.command.name == "run") {
    await handleBatchRunCommand(opts.command);
  }
}

handleLinkCommand(ArgResults opts) async {
  if (opts.command == null) {
    usage(command: "link");
  }

  if (opts.command.name == "list") {
    await handleLinkListCommand(opts.command);
  }
}

handleLinkListCommand(ArgResults opts) async {
  await loginToGitHub();

  var format = opts["format"];
  var typeFilter = opts["type"];
  var out = [];

  await for (Repository repo in listLinkRepositories()) {

    try {
      var json = await fetchRepositoryJsonFile(repo, "dslink.json");
      var l = new DSLinkJSON.from(json);

      if (l.name == null) {
        continue;
      }

      var type = getLinkType(l.name);
      if (typeFilter != "any" && typeFilter != type) {
        continue;
      }

      if (format == "detailed") {
        print("- ${l.name}:");
        if (repo.description != null && repo.description.isNotEmpty) {
          print("  Description: ${repo.description}");
        }

        print("  Url: ${repo.htmlUrl}");
        print("  Clone Url: ${repo.cloneUrls.https}");
      } else if (format == "simple") {
        print(l.name);
      } else if (format == "git-clone") {
        print("git clone ${repo.cloneUrls.https}");
      } else if (format == "json") {
        var m = {
          "name": l.name,
          "url": repo.htmlUrl,
          "cloneUrl": repo.cloneUrls.https
        };

        if (repo.description != null && repo.description.isNotEmpty) {
          m["description"] = repo.description;
        }

        out.add(m);
      }
    } catch (e) {
    }
  }

  if (format == "json") {
    print(const JsonEncoder.withIndent("  ").convert(out));
  }
}

ArgParser createLinkParser() {
  var argp = new ArgParser(allowTrailingOptions: true);

  argp.addCommand("list", createListLinkParser());

  return argp;
}

ArgParser createGetParser() {
  var argp = new ArgParser(allowTrailingOptions: true);
  return argp;
}

ArgParser createGetDistParser() {
  var argp = new ArgParser(allowTrailingOptions: true);
  return argp;
}

ArgParser createSetupParser() {
  var argp = new ArgParser(allowTrailingOptions: true);
  return argp;
}

ArgParser createListLinkParser() {
  var argp = new ArgParser(allowTrailingOptions: true);
  argp.addOption("format", abbr: "f", help: "Output Format", allowed: [
    "detailed",
    "simple",
    "json",
    "git-clone"
  ], defaultsTo: "detailed");

  argp.addOption("type", abbr: "t", help: "Link Type", defaultsTo: "any");
  return argp;
}

ArgParser createHelpParser() {
  var argp = new ArgParser(allowTrailingOptions: true);
  return argp;
}

ArgParser createBatchParser() {
  var argp = new ArgParser(allowTrailingOptions: true);
  argp.addCommand("run", createBatchRunParser());
  return argp;
}

ArgParser createBatchRunParser() {
  var argp = new ArgParser(allowTrailingOptions: true);
  return argp;
}
