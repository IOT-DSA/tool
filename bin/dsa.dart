import "dart:io";

import "package:args/args.dart";
import "package:dslink/utils.dart" show DSLinkJSON;
import "package:dsa_tool/github.dart";
import "package:dsa_tool/cfg.dart";
import "package:dsa_tool/utils.dart";
import "package:console/console.dart";
import "package:crypto/crypto.dart";
import "package:legit/legit.dart";
import "package:dsa_tool/io.dart";

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
    ArgParser cmd;

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
  var opts = argp.parse(args);

  if (opts.command == null) {
    usage(message: "No Command Specified");
  }

  if (opts.command.name == "link") {
    await handleLinkCommand(opts.command);
  } else if (opts.command.name == "setup") {
    await handleSetupCommand(opts.command);
  } else if (opts.command.name == "get-dist") {
    await handleGetDistCommand(opts.command);
  } else if (opts.command.name == "get") {
    await handleGetCommand(opts.command);
  } else {
    usage(message: "Unknown Command");
  }

  if (autoExit) {
    github.dispose();
    exit(0);
  }
}

bool autoExit = true;

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

  GitClient git = new GitClient(new Directory(target));
  git.quiet = false;
  var result = await git.clone("https://github.com/IOT-DSA/${name}.git", recursive: true);

  if (!result) {
    print("Failed to get ${name}!");
    exit(1);
  } else {
    print("Success.");
  }
}

handleSetupCommand(ArgResults opts) async {
  var config = await readConfigFile();

  if ((config["github_username"] == null ||
    config["github_password"] == null) ||
    await new Prompter("You have already logged into GitHub. Would you like to do it again?").ask()) {
    var username = await new Prompter("GitHub Username: ").prompt();
    var password = await new Prompter("GitHub Password: ", secret: true).prompt();
    print("");

    github.auth = new Authentication.basic(username, password);
    try {
      var user = await github.users.getCurrentUser();
      print("Hello, ${user.name}!");
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
  var config = await readConfigFile();

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

handleLinkCommand(ArgResults opts) async {
  if (opts.command == null) {
    usage(command: "link");
  }

  if (opts.command.name == "list") {
    await handleLinkListCommand(opts);
  }
}

handleLinkListCommand(ArgResults opts) async {
  await loginToGitHub();
  await for (Repository repo in listLinkRepositories()) {
    try {
      var json = await fetchRepositoryJsonFile(repo, "dslink.json");
      var l = new DSLinkJSON.from(json);

      if (l.name == null) {
        continue;
      }

      print("- ${l.name}:");
      if (repo.description != null && repo.description.isNotEmpty) {
        print("  Description: ${repo.description}");
      }

      print("  Url: ${repo.htmlUrl}");
      print("  Clone Url: ${repo.cloneUrls.https}");
    } catch (e) {
    }
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
  return argp;
}
