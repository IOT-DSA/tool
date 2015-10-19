library netrc;

import "package:petitparser/petitparser.dart";

class Netrc {
  NetrcMachine defaultMachine;
  List<NetrcMachine> machines = [];
}

class NetrcMachine {
  bool isDefault = false;
  String name;
  String login;
  String password;
  String account;

  @override
  String toString() {
    var lines = [];
    if (isDefault) {
      lines.add("default");
    } else {
      lines.add("machine ${name}");
    }

    if (login != null) {
      lines.add("  login ${login}");
    }

    if (password != null) {
      lines.add("  password ${password}");
    }

    if (account != null) {
      lines.add("  account ${account}");
    }

    return lines.join("\n");
  }
}

class NetrcGrammarDefinition extends GrammarDefinition {
  @override
  start() => (ref(whitespace).star().flatten() & (
    ref(machine).separatedBy(ref(whitespace), includeSeparators: false) &
    ref(whitespace).star().flatten()
  ).pick(0).end()).pick(1);

  machine() =>
    ((tokenWithValue(ref(MACHINE)) | ref(DEFAULT)) & ref(whitespace).plus().flatten() & (
      ref(login) |
      ref(password)
    ).separatedBy(ref(whitespace).plus().flatten(), includeSeparators: false)).permute(const [0, 2]);

  login() => tokenWithValue(ref(LOGIN));
  password() => tokenWithValue(ref(PASSWORD));

  tokenWithValue(Parser token) => (token &
    ref(whitespace).plus().flatten() &
    ref(value)).permute(const [0, 2]);

  value() => ref(whitespace).neg().plus().flatten();

  MACHINE() => string("machine").flatten();
  DEFAULT() => string("default").flatten();
  LOGIN() => string("login").flatten();
  PASSWORD() => string("password").flatten();
}

class NetrcGrammar extends GrammarParser {
  NetrcGrammar() : super(new NetrcGrammarDefinition());
}

class NetrcParserDefinition extends NetrcGrammarDefinition {
  @override
  machine() => super.machine().map((object) {
    var m = new NetrcMachine();
    if (object[0] is String) {
      m.isDefault = true;
    } else {
      m.name = object[0][1];
    }
    for (List x in object[1]) {
      if (x.length != 2) {
        continue;
      }

      String key = x[0];
      String value = x[1];

      if (key == "login") {
        m.login = value;
      } else if (key == "password") {
        m.password = value;
      } else if (key == "account") {
        m.account = value;
      }
    }
    return m;
  });
}

class NetrcParser extends GrammarParser {
  NetrcParser() : super(new NetrcParserDefinition());
}
