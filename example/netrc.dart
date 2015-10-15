import "package:dsa_tool/netrc.dart";

const String TEST_INPUT = """
default
  login test
  password x
machine github.com
  login test
  password test
machine golang.org
  login test
  password goodbye
""";

main() async {
  var grammar = new NetrcParser();
  var result = grammar.parse(TEST_INPUT);
  for (var n in result.value) {
    print(n);
  }
}
