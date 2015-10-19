library dsa.tool.help;

const String HELP_COMMAND = """\
DSA Tool Help:

  Fetch a DSLink:
    dsa get dslink-java-etsdb

  List Java DSLinks:
    dsa link list -t java

  List Dart DSLinks:
    dsa link list -t dart

  Run a Batch Task File:
    dsa batch run ~/Tasks/my_task.yaml

  Clone all Java DSLinks:
    dsa link list -t java -f git-clone | bash
""";