library dsa.github;

import "dart:async";
import "dart:convert";

import "globals.dart";

import "package:github/server.dart";
export "package:github/server.dart" show Repository, Authentication;

const String DSA_GITHUB_ORG = "IOT-DSA";

final GitHub github = createGitHubClient();

Stream<Repository> listDsaRepositories() async* {
  var users = [DSA_GITHUB_ORG];
  users.addAll(config["dsa_users"] == null ? [] : config["dsa_users"]);

  for (var user in users) {
    yield* github.repositories.listUserRepositories(user);
  }
}

Stream<Repository> listLinkRepositories() {
  return listDsaRepositories().where((repo) {
    var success = repo.name.startsWith("dslink-") &&
        !repo.name.endsWith("-template") &&
        !repo.name.contains("-template-");
    return success;
  });
}

Stream<Repository> listSdkRepositories() {
  return listDsaRepositories().where((repo) {
    return repo.name.startsWith("sdk-dslink-");
  });
}

Future<dynamic> fetchRepositoryJsonFile(Repository repo, String path) async {
  var c = await github.repositories.getContents(repo.slug(), path);
  return JSON.decode(c.file.text);
}
