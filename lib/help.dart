library dsa.tool.help;

const String HELP_COMMAND = """\
DSA Tool Help:

  Fetch a DSLink:
    dsa get dslink-java-etsdb

  Print a List of All DSLinks:
    dsa link list

  Print Simple List of DSLinks:
    dsa link list -f simple

  Print DSLink List as JSON:
    dsa link list -f json

  Print a List of Java DSLinks:
    dsa link list -t java

  Print a List of Dart DSLinks:
    dsa link list -t dart

  Run a Batch Task File:
    dsa batch run ~/Tasks/my_task.yaml

  Clone all Java DSLinks:
    dsa link list -t java -f git-clone | bash
""";
