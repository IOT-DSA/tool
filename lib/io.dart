library ioutil;

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:archive/archive.dart";
import "package:http/http.dart" as http;
import "package:path/path.dart" as pathlib;
import "package:crypto/crypto.dart";
import "package:dslink/io.dart" as IO;

export "package:dslink/io.dart" show getRandomSocketPort;

typedef Handler<T>(T val);
typedef void ProcessHandler(Process process);
typedef void OutputHandler(String str);

Stdin get _stdin => stdin;

class BetterProcessResult extends ProcessResult {
  final String output;

  BetterProcessResult(int pid, int exitCode, stdout, stderr, this.output) :
  super(pid, exitCode, stdout, stderr);
}

class ProcessController {
  Process _process;
  Completer _readyCompleter = new Completer.sync();
  Future get onReady => _readyCompleter.future;


  bool get isReady => _readyCompleter.isCompleted;

  void kill([ProcessSignal signal]) {
    if (_process != null) {
      _process.kill(signal);
    }
  }
}

Future<String> createFileChecksum(File file) async {
  var bytes = await file.readAsBytes();
  var hash = new MD5();
  hash.add(bytes);
  var result = hash.close();
  return CryptoUtils.bytesToHex(result);
}

Future<bool> verifyFileChecksum(File file, String expected) async {
  var actual = await createFileChecksum(file);
  return expected == actual;
}

Future writeFileChecksum(File file) async {
  var path = file.path + ".md5";
  var checksumFile = new File(path);
  var checksum = await createFileChecksum(file);
  await checksumFile.writeAsString(checksum);
}

enum ChecksumState {
  CREATED, SAME, MODIFIED
}

Future<ChecksumState> doFileChecksum(String path) async {
  var file = new File(path);
  var checksumFile = new File(file.path + ".md5");

  if (!(await checksumFile.exists())) {
    await writeFileChecksum(file);
    return ChecksumState.CREATED;
  }

  var expect = (await checksumFile.readAsString()).trim();
  var result = await verifyFileChecksum(file, expect);

  if (result) {
    return ChecksumState.SAME;
  } else {
    await writeFileChecksum(file);
    return ChecksumState.MODIFIED;
  }
}

Future<BetterProcessResult> exec(
  String executable,
  {
  List<String> args: const [],
  String workingDirectory,
  Map<String, String> environment,
  bool includeParentEnvironment: true,
  bool runInShell: false,
  stdin,
  ProcessHandler handler,
  OutputHandler stdoutHandler,
  OutputHandler stderrHandler,
  OutputHandler outputHandler,
  ProcessController controller,
  File outputFile,
  Handler<int> exitHandler,
  bool inherit: false,
  bool writeToBuffer: false
  }) async {
  IOSink raf;

  if (outputFile != null) {
    if (!(await outputFile.exists())) {
      await outputFile.create(recursive: true);
    }

    raf = await outputFile.openWrite(mode: FileMode.APPEND);
  }

  if (workingDirectory == null) {
    workingDirectory = Directory.current.path;
  }

  try {
    Process process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell
    );

    if (controller != null) {
      controller._process = process;
      controller._readyCompleter.complete();
    }

    if (raf != null) {
      await raf.writeln("[${currentTimestamp}] == Executing ${executable} with arguments ${args} (pid: ${process.pid}) ==");
    }

    var buff = new StringBuffer();
    var ob = new StringBuffer();
    var eb = new StringBuffer();

    process.stdout.transform(UTF8.decoder).listen((str) async {
      if (writeToBuffer) {
        ob.write(str);
        buff.write(str);
      }

      if (stdoutHandler != null) {
        stdoutHandler(str);
      }

      if (outputHandler != null) {
        outputHandler(str);
      }

      if (inherit) {
        stdout.write(str);
      }

      try {
        if (raf != null) {
          await raf.write("[${currentTimestamp}] ${str}");
        }
      } catch (e) {}
    });

    process.stderr.transform(UTF8.decoder).listen((str) async {
      if (writeToBuffer) {
        eb.write(str);
        buff.write(str);
      }

      if (stderrHandler != null) {
        stderrHandler(str);
      }

      if (outputHandler != null) {
        outputHandler(str);
      }

      if (inherit) {
        stderr.write(str);
      }

      try {
        if (raf != null) {
          await raf.write("[${currentTimestamp}] ${str}");
        }
      } catch (e) {}
    });

    if (handler != null) {
      handler(process);
    }

    if (stdin != null) {
      if (stdin is Stream) {
        stdin.listen(process.stdin.add, onDone: process.stdin.close);
      } else if (stdin is List) {
        process.stdin.add(stdin);
      } else {
        process.stdin.write(stdin);
        await process.stdin.close();
      }
    } else if (inherit) {
      _stdin.listen(process.stdin.add, onDone: process.stdin.close);
    }

    var code = await process.exitCode;
    var pid = process.pid;

    try {
      if (raf != null) {
        await raf.writeln("[${currentTimestamp}] == Exited with status ${code} ==");
        await raf.flush();
        await raf.close();
      }
    } catch (e) {}

    if (exitHandler != null) {
      exitHandler(code);
    }

    return new BetterProcessResult(
      pid,
      code,
      ob.toString(),
      eb.toString(),
      buff.toString()
    );
  } finally {
    try {
      if (raf != null) {
        await raf.flush();
        await raf.close();
      }
    } catch (e) {}
  }
}

Future<String> findExecutable(String name) async {
  var paths = Platform.environment["PATH"].split(Platform.isWindows ? ";" : ":");
  var tryFiles = [name];

  if (Platform.isWindows) {
    tryFiles.addAll(["${name}.exe", "${name}.bat"]);
  }

  for (var p in paths) {
    if (p.startsWith('"') && p.endsWith('"')) {
      p = p.substring(1, p.length - 1);
    }

    if (Platform.environment.containsKey("HOME")) {
      p = p.replaceAll("~/", Platform.environment["HOME"]);
    }

    var dir = new Directory(pathlib.normalize(p));

    if (!(await dir.exists())) {
      continue;
    }

    for (var t in tryFiles) {
      var file = new File("${dir.path}/${t}");

      if (await file.exists()) {
        return file.path;
      }
    }
  }

  return null;
}

Future<bool> isPortOpen(int port, {String host: "0.0.0.0"}) async {
  try {
    ServerSocket server = await ServerSocket.bind(host, port);
    await server.close();
    return true;
  } catch (e) {
    return false;
  }
}

bool _canUseSmartUnzip;

Future<bool> canUseSmartUnzip() async {
  if (_canUseSmartUnzip != null) {
    return _canUseSmartUnzip;
  }

  _canUseSmartUnzip = (
    Platform.isLinux ||
    Platform.isMacOS
  ) && (await findExecutable("bsdtar") != null);
  return _canUseSmartUnzip;
}

Future extractUrlArchiveSmart(String url, Directory dir, {bool handleSingleDirectory: false}) async {
  if (await canUseSmartUnzip()) {
    var tmpDir = await Directory.systemTemp.createTemp("dgserver-fetch");
    var f = new File(pathlib.join(tmpDir.path, "file.tmp"));
    await f.create(recursive: true);
    HttpClient client = IO.HttpHelper.client;
    var req = await client.getUrl(Uri.parse(url));
    var resp = await req.close();
    IOSink sink = f.openWrite();
    await resp.pipe(sink);
    var cmd = await findExecutable("bsdtar");
    if (!(await dir.exists())) {
      await dir.create(recursive: true);
    }
    var args = ["-C", dir.path, "-xvf${f.path}"];

    if (handleSingleDirectory) {
      BetterProcessResult ml = await exec(cmd, args: ["-tf${f.path}"], writeToBuffer: true);
      List<String> contents = ml.stdout.split("\n");
      contents.removeWhere((x) => x == null || x.isEmpty || x.endsWith("/"));
      if (contents.every((l) => l.split("/").length > 1)) {
        args.addAll(["--strip-components", "1"]);
      }
    }

    var result = await exec(cmd, args: args, writeToBuffer: true);

    if (result.exitCode != 0) {
      await tmpDir.delete(recursive: true);
      throw new Exception("Failed to extract archive.");
    }

    await tmpDir.delete(recursive: true);
  } else {
    var bytes = await fetchUrl(url);
    await extractArchiveSmart(bytes, dir, handleSingleDirectory: handleSingleDirectory);
  }
}

Future extractArchiveSmart(List<int> bytes, Directory dir, {bool handleSingleDirectory: false}) async {
  if (await canUseSmartUnzip()) {
    var cmd = await findExecutable("bsdtar");
    if (!(await dir.exists())) {
      await dir.create(recursive: true);
    }
    var args = ["-C", dir.path, "-xvf-"];

    if (handleSingleDirectory) {
      BetterProcessResult ml = await exec(cmd, args: ["-tf-"], handler: (Process process) {
        process.stdin.add(bytes);
        process.stdin.close();
      }, writeToBuffer: true);
      List<String> contents = ml.stdout.split("\n");
      contents.removeWhere((x) => x == null || x.isEmpty || x.endsWith("/"));
      if (contents.every((l) => l.split("/").length > 1)) {
        args.addAll(["--strip-components", "1"]);
      }
    }

    var result = await exec(cmd, args: args, handler: (Process process) {
      process.stdin.add(bytes);
      process.stdin.close();
    });

    if (result.exitCode != 0) {
      throw new Exception("Failed to extract archive.");
    }
  } else {
    var files = await decompressZipFiles(bytes);
    await extractArchive(files, dir, handleSingleDirectory: handleSingleDirectory);
  }
}

Future extractArchive(Stream<ArchiveFile> files, Directory dir, {bool handleSingleDirectory: false}) async {
  var allFiles = await files.toList();

  if (handleSingleDirectory && allFiles.every((f) => f.name.split("/").length >= 2)) {
    allFiles.forEach((file) {
      file.name = file.name.split("/").skip(1).join("/");
    });

    allFiles.removeWhere((x) => x.name == "" || x.name == "/");
  }

  for (ArchiveFile f in allFiles) {
    if (!f.isFile || f.name.endsWith("/")) continue;

    var file = new File(pathlib.join(dir.path, f.name));
    if (!(await file.exists())) {
      await file.create(recursive: true);
    }

    await file.writeAsBytes(f.content);
  }
}

Stream<ArchiveFile> decompressZipFiles(List<int> data) async* {
  var decoder = new ZipDecoder();
  var archive = decoder.decodeBytes(data);
  for (var file in archive.files) {
    if (file.isCompressed) {
      file.decompress();
    }
    yield file;
  }
}

Stream<ArchiveFile> decompressTarFiles(List<int> data) async* {
  var decoder = new TarDecoder();
  var archive = decoder.decodeBytes(data);
  for (var file in archive.files) {
    if (file.isCompressed) {
      file.decompress();
    }
    yield file;
  }
}

Future generateSnapshotFile(String target, String input) async {
  var result = await Process.run(getDartExecutable(), [
    "--snapshot=${target}",
    input
  ]);

  if (result.exitCode != 0) {
    throw new Exception("Failed to generate snapshot for ${input}.");
  }
}

String getDartExecutable() {
  String dartExe;
  try {
    dartExe = Platform.resolvedExecutable;
  } catch (e) {
    dartExe = Platform.executable.isNotEmpty ? Platform.executable : "dart";
  }
  return dartExe;
}

Future<dynamic> fetchJSON(String url) async {
  http.Response response = await _http.get(url);
  if (response.statusCode != 200) {
    throw new Exception("Failed to fetch url: got status code ${response.statusCode}");
  }
  return JSON.decode(response.body);
}

download(String url, String path, {String message: "Downloading {file.name}"}) async {
  var file = new File(path);
  var parent = file.parent;
  if (!(await parent.exists())) {
    await parent.create(recursive: true);
  }

  var name = file.path.split("/").last;

  message = message.replaceAll("{file.name}", name);

  var uri = Uri.parse(url);
  HttpClient client = new HttpClient();
  var request = await client.getUrl(uri);
  var response = await request.close();
  if (response.statusCode != 200) {
    client.close(force: true);
    throw new HttpException("Bad Status Code: ${response.statusCode}", uri: uri);
  }

  var progress = 0;
  var r = file.openWrite();
  var last = "";
  stdout.write("${message}: ");
  await response.listen((data) {
    progress += data.length;
    r.add(data);
    stdout.write("\b" * last.length);
    var percent = ((progress / response.contentLength) * 100).clamp(0, 100);
    last = "${percent.toStringAsFixed(2)}%";
    stdout.write(last);
  }).asFuture();
  await r.close();
  stdout.writeln();
  client.close(force: true);
}

Future<List<int>> fetchBytes(String url, {String message: "Downloading {file.name}"}) async {
  var uri = Uri.parse(url);

  var name = uri.pathSegments.last;
  message = message.replaceAll("{file.name}", name);

  HttpClient client = new HttpClient();
  var request = await client.getUrl(uri);
  var response = await request.close();
  if (response.statusCode != 200) {
    client.close(force: true);
    throw new HttpException("Bad Status Code: ${response.statusCode}", uri: uri);
  }

  var progress = 0;
  var last = "";
  var bytes = [];
  stdout.write("${message}: ");
  await response.listen((data) {
    progress += data.length;
    bytes.addAll(data);
    stdout.write("\b" * last.length);
    var percent = ((progress / response.contentLength) * 100).clamp(0, 100);
    last = "${percent.toStringAsFixed(2)}%";
    stdout.write(last);
  }).asFuture();
  stdout.writeln();
  client.close(force: true);
  return bytes;
}

Future<List<int>> fetchUrl(String url) async {
  http.Response response = await _http.get(url);
  if (response.statusCode != 200) {
    throw new Exception("Failed to fetch url: got status code ${response.statusCode}");
  }
  return response.bodyBytes;
}

http.Client _http = new http.Client();

String get currentTimestamp {
  return new DateTime.now().toString();
}
