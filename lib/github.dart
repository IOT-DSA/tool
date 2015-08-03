library dsa.github;

import "dart:async";
import "dart:convert";

import "package:github/server.dart";

export "package:github/server.dart" show Repository, Authentication;

const String DSA_GITHUB_ORG = "IOT-DSA";

final GitHub github = createGitHubClient();

Stream<Repository> listDsaRepositories() {
  return github.repositories.listUserRepositories(DSA_GITHUB_ORG);
}

Stream<Repository> listLinkRepositories() {
  return listDsaRepositories().where((repo) {
    var success = repo.name.startsWith("dslink-") && !repo.name.endsWith("-template");
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
