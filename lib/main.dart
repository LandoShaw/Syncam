import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:lan_scanner/lan_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'package:connectivity/connectivity.dart';

// import 'package:network_discovery/network_discovery.dart';

// import 'package:dart_discover/dart_discover.dart';

// Future<void> main() async {
// // Ensure that plugin services are initialized so that `availableCameras()`
// // can be called before `runApp()`
//   WidgetsFlutterBinding.ensureInitialized();

// // Obtain a list of the available cameras on the device.
//   final cameras = await availableCameras();

// // Get a specific camera from the list of available cameras.
//   final firstCamera = cameras.first;

//   runApp(
//     MaterialApp(
//       theme: ThemeData.dark(),
//       home: TakePictureScreen(
//         // Pass the appropriate camera to the TakePictureScreen widget.
//         camera: firstCamera,
//       ),
//     ),
//   );
// }

void main() async {
  // Ensure that plugin services are initialized so that `availableCameras()`
  // can be called before `runApp()`
  WidgetsFlutterBinding.ensureInitialized();
  // Get device's list of cameras
  final cameras = await availableCameras();
  // Grab first camera
  final firstCamera = cameras.first;
  runApp(MainScreenWidget(camera: firstCamera));
}

class MainScreenWidget extends StatefulWidget {
  const MainScreenWidget({
    super.key,
    required this.camera,
  });
  final CameraDescription camera;
  @override
  MainScreenWidgetState createState() => MainScreenWidgetState();
}

class MainScreenWidgetState extends State<MainScreenWidget> {
  late CameraController _controller; //intialize camera
  late Future<void> _initializeControllerFuture; //chech this before using cam

  @override
  void initState() {
    super.initState();
    initializeCamera();
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    _controller.dispose();
    super.dispose();
  }

  initializeCamera() async {
    // Create a CameraController.
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
    );
    // Init the controller. This returns a Future.
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Home Screen')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => HostWidget(
                              controller: _controller,
                              initializeControllerFuture:
                                  _initializeControllerFuture)),
                    );
                  },
                  child: Text('Launch as Host'),
                ),
              ),
              SizedBox(height: 16.0), // Optional spacing
              Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    // Handle button 1 press
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => ClientWidget(
                              controller: _controller,
                              initializeControllerFuture:
                                  _initializeControllerFuture)),
                    );
                  },
                  child: Text('Launch as Client'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HostWidget extends StatefulWidget {
  const HostWidget({
    super.key,
    required this.controller,
    required this.initializeControllerFuture,
  });
  final CameraController controller;
  final Future initializeControllerFuture;

  @override
  HostWidgetState createState() => HostWidgetState();
}

class HostWidgetState extends State<HostWidget> {
  final int portNum = 49153;
  late Future<String> ip;
  final List<Socket> clientSockets = [];
  Stopwatch rttClock = Stopwatch();
  Duration halfRTT = Duration.zero;

  late List<Duration> clockDifSamples = [];
  late List<bool> clockDifSamplesSign = [];
  late Duration clockDif;
  final clockDifReceived = StreamController<void>();

/*  Future Notes:
  in future: if 1) new client connects and 2) 'take-pic' cmd is being 
  sent out at the same time, both will be accessing clientSockets.  Possible 
  point of failure, possible semaphore needed.

  long-term additionaly functionality
  when the rttCmd is sent out, it disables the capture button,
  when it is received it renables the capture button.

  short-term:
  for now, we just give it a moment before hitting capture, after hitting sync

  the getClockDif function assumes that all samples of the clock offset will 
  be positive or negative, but not a combo of +/-
*/

  @override
  void initState() {
    super.initState();

    getLocalWifiIp().then((String ip) {
      establishTCPServerSocket(ip, portNum);
    });
  }

  @override
  void dispose() {
    super.dispose();
    //close all TCP connections
  }

  Future<String> getLocalWifiIp() async {
    /*
  returns the IP address within the local wifi hotspot.
  Note:
  'NetworkInterface.list()' gets all addresses of network interface.  This includes
  the call iP address (2 of them somehow) and the Wifi Hotspot one.  If the cellular 
  is disconnected/off, then the only one is the wifi hotspot one. Thus its handled.
  i.e. the Wifi hotspot seems to take the final location in the returned address array.
  */
    List<NetworkInterface> interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    int len = interfaces.length;
    return interfaces[len - 1].addresses[0].address;
  }

  void establishTCPServerSocket(ip, portNum) async {
    final server = await ServerSocket.bind(ip, portNum);
    print('Server listening on ${server.address}:${server.port}');
    //runs indefintely
    await for (var socket in server) {
      clientResponseHandler(socket);
    }
  }

  void sendRTTCmd(Socket client) {
    rttClock.start();
    client.write("getRTT");
  }

  void receiveRTTResponse() {
    rttClock.stop();
    int intHalfRTT = (rttClock.elapsedMilliseconds / 2).toInt();
    halfRTT = Duration(milliseconds: intHalfRTT);
    print('Elapsed time: $halfRTT');
    rttClock.reset();
  }

  void clientResponseHandler(Socket client) {
    clientSockets.add(client);
    client.listen(
      (List<int> data) async {
        String givenResponse = String.fromCharCodes(data);

        switch (givenResponse) {
          case "RTT":
            receiveRTTResponse();
          default: // clockDiffCmd received
            receiveClockDiff(givenResponse);
        }
      },
      onDone: () {
        client.destroy(); // Client closed connection
      },
      onError: (error) {
        client.destroy();
      },
      cancelOnError: true,
    );
  }

  void sendClientCaptureCmds(List<Socket> clientSockets, DateTime triggerTime) {
    String triggerString = triggerTime.toUtc().toIso8601String();

    for (var socket in clientSockets) {
      socket.write(triggerString);
    }
  }

  void takeLocalPicture() async {
    try {
      await widget.initializeControllerFuture; // camera init'd?
      final image = await widget.controller.takePicture();
      if (!mounted) return;

      await Navigator.of(context).push(
        //if captured, display
        MaterialPageRoute(
          builder: (context) => DisplayPictureScreen(
            // Pass the automatically generated path to the DisplayPictureScreen widget.
            imagePath: image.path,
          ),
        ),
      );
    } catch (e) {
      print(e);
    }
  }

  void sendClockDiffCmd(List<Socket> clientSockets) {
    /*
  samples current time and sends it to the client.
  */
    DateTime t1 = DateTime.now();
    String t1String = t1.toUtc().toIso8601String();

    for (var socket in clientSockets) {
      socket.write(t1String);
    }
  }

  Future getEightClockDifs() async {
    //has to return neg or pos
    Completer<void> done = Completer<void>();
    // this segment is just to initialize the subscription to satiate compiler
    StreamController<void> controller = StreamController<void>();
    StreamSubscription<void> difReceived = controller.stream.listen((_) {});
    int difCount = 0;

    difCount = difCount + 1;
    sendClockDiffCmd(clientSockets);

    difReceived = clockDifReceived.stream.listen((_) {
      if (difCount < 2) {
        difCount = difCount + 1;
        sendClockDiffCmd(clientSockets);
      } else {
        difReceived.cancel();
        return done.complete();
      }
    });

    await done.future;
  }

  void getClockDif() async {
    clockDifSamples = [];
    clockDifSamplesSign = [];

    await getEightClockDifs();
    clockDif = takeAverageDuration();
    print("samples, signs, average");
    print(clockDifSamples);
    print(clockDifSamplesSign);
    print(clockDif);
  }

  Duration takeAverageDuration() {
    Duration avg = Duration.zero;
    Duration total = Duration.zero;

    for (var durs in clockDifSamples) {
      total = total + durs;
    }
    avg =
        Duration(milliseconds: total.inMilliseconds ~/ clockDifSamples.length);
    return avg;
  }

  void receiveClockDiff(String givenResponse) {
    /*
      unpack t1, t2, t3 sample t4.
    */
    DateTime t4 = DateTime.now();
    List<dynamic> timeList = jsonDecode(givenResponse);
    DateTime t1 = DateTime.parse(timeList[0]).toLocal();
    DateTime t2 = DateTime.parse(timeList[1]).toLocal();
    DateTime t3 = DateTime.parse(timeList[2]).toLocal();

    // (T2 - T1)
    Duration t2_minus_t1_dif = t2.difference(t1);
    bool t2_minus_t1_pos;
    if (t1.isAfter(t2)) {
      t2_minus_t1_pos = false;
    } else {
      t2_minus_t1_pos = true;
    }

    // (T3 - T4)
    Duration t3_minus_t4_dif = t3.difference(t4);
    bool t3_minus_t4_pos;
    if (t4.isAfter(t3)) {
      t3_minus_t4_pos = false;
    } else {
      t3_minus_t4_pos = true;
    }

    bool result_pos = false; //is the clock offset pos or neg?
    Duration dif; //final clock difference

    // both pos or both neg
    if (t2_minus_t1_pos && t3_minus_t4_pos ||
        !t2_minus_t1_pos && !t3_minus_t4_pos) {
      dif = t3_minus_t4_dif + t2_minus_t1_dif;

      if (t2_minus_t1_pos) {
        result_pos = true; //positive
      } else {
        result_pos = false; //negative
      }
    } else {
      dif = t3_minus_t4_dif - t2_minus_t1_dif;

      // if T2-T1 larger and positive, result is positive
      if (t2_minus_t1_dif >= t3_minus_t4_dif && t2_minus_t1_pos) {
        result_pos = true;
      } else if (t2_minus_t1_dif >= t3_minus_t4_dif && !t2_minus_t1_pos) {
        result_pos = false;
      } else if (t2_minus_t1_dif <= t3_minus_t4_dif && t3_minus_t4_pos) {
        result_pos = true;
      } else {
        result_pos = false;
      }
    }

    int totalMilliseconds = dif.inMilliseconds ~/ 2;
    Duration offset = Duration(milliseconds: totalMilliseconds);
    // negative difference =  host is behind (slow)
    // positive difference = host is ahead (fast)
    clockDifSamples.add(offset); //add it to the current sample set of difs
    clockDifSamplesSign.add(result_pos); // corresponding pos/neg
    //in above logic, the +/- nature of ans is is saved in a global variable
    clockDifReceived.add(null); //notify getClockDif to req another dif sample
  }

  DateTime getCaptureTime() {
    /*
      takes the current time, adds halfRTT and returns that.
    */
    DateTime now = DateTime.now();
    DateTime withDelay = now.add(halfRTT);
    DateTime withDelayDelay = withDelay.add(Duration(milliseconds: 1000));
    return withDelayDelay;
  }

  void waitUntilCaptureTime(DateTime triggerTime) {
    /*
      takes triggerTime and waits until that time has passed before returning. 
      make sure you have used the sync button at least once.
      make a version that uses future completion? Because this is synchronous code.
    */

    DateTime newNow = DateTime.now();
    print("begin waiting");
    while (triggerTime.isAfter(newNow)) {
      print("waiting");
      newNow = DateTime.now();
    }
    return;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Host Launch')),
        body: FutureBuilder<void>(
          future: widget.initializeControllerFuture,
          builder: (context, snapshot) {
            //display preview when done loading
            if (snapshot.connectionState == ConnectionState.done) {
              return CameraPreview(widget.controller);
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'captureButton', // Unique tag for the first button
              onPressed: () async {
                getClockDif();

                //start here, use global variables to act accordingly
                // TEST FIRST THOUGH.

                // DateTime triggerTime = getCaptureTime();
                // sendClientCaptureCmds(clientSockets, triggerTime);
                // triggerTime = triggerTime.subtract(Duration(milliseconds: 840));
                // // remove some delay time to account for the capture mechanism. Make a function later.
                // waitUntilCaptureTime(triggerTime);
                // takeLocalPicture();
              },
              child: const Icon(Icons.camera_alt),
            ),
            FloatingActionButton(
              heroTag: 'syncButton', // Unique tag for the second button
              onPressed: () {
                sendRTTCmd(clientSockets[0]);
              },
              child: const Icon(Icons.sync_alt),
            ),
          ],
        ),
      ),
    );
  }
}

class ClientWidget extends StatefulWidget {
  const ClientWidget({
    super.key,
    required this.controller,
    required this.initializeControllerFuture,
  });
  final CameraController controller;
  final Future initializeControllerFuture;
  @override
  ClientWidgetState createState() => ClientWidgetState();
}

class ClientWidgetState extends State<ClientWidget> {
  late Future<String> defaultGateway;
  final int serverPort = 49153;
  late Socket? hostSocket;

  @override
  void initState() {
    super.initState();
    defaultGateway = getGateway(); //needs async eventually
    establishTCPClientSocket().then((Socket? host) {
      if (host != null) {
        hostSocket = host; //necessary? not right now
        listenForHostCmds(host);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    //close all TCP connections
  }

  Future<String> getGateway() async {
    //finding the default gateway requires native android code (kotlin)
    //to save time, we are manually coding the default gateway
    return "192.168.21.117";
  }

  void handleHostCaptureCmd(DateTime triggerTime) async {
    waitUntilCaptureTime(triggerTime);
    takeLocalPicture();
  }

  void waitUntilCaptureTime(DateTime triggerTime) {
    /*
      takes triggerTime and waits until that time has passed before returning. 
      make sure you have used the sync button at least once.
      make a version that uses future completion? Because this is synchronous code.
    */
    DateTime newNow = DateTime.now();
    print("begin waiting");
    while (triggerTime.isAfter(newNow)) {
      print("waiting");
      newNow = DateTime.now();
    }
    return;
  }

  /*
track when the message arrives, before or after the trigger time

We are using external stopwatch to verify, how can we automate this process?

basic counter and some image recog software to do the math automatically. 

Find the necessary timing difference maximum time precision needed for moca.

Whats the sync level required for good mocap.

Whats the standard?

Google precision requried betweeen cameras in mocap.

find somebodies work. 

Future work:
Automatic verification of accuracy

Algortithm: increaset he number of phones
              pi precision

VERIFICATION:
NEEEDED BEFORE PRESENTATION
What is the minimum required/usbale precision for a given applcaiton:
casual photography?
mocap?



Name of the text?
Dis System MArtin VAnstin



We using NTP algortithm:


  */

  void takeLocalPicture() async {
    try {
      await widget.initializeControllerFuture; // camera init'd?
      final image = await widget.controller.takePicture();
      if (!mounted) return;

      await Navigator.of(context).push(
        //if captured, display
        MaterialPageRoute(
          builder: (context) => DisplayPictureScreen(
            // Pass the automatically generated path to the DisplayPictureScreen widget.
            imagePath: image.path,
          ),
        ),
      );
    } catch (e) {
      print(e);
    }
  }

  void handleHostRTTCmd(Socket socket) async {
    // returns message as soon as one is received.
    socket.write("RTT");
  }

  void handleClockDiffCmd(Socket hostSocket, String t1) {
    DateTime t2 = DateTime.now(); //time of reception

    List<String> times = [];
    times.add(t1); //return t1 as is
    times.add(t2.toUtc().toIso8601String()); //convert t2 to string

    times.add(DateTime.now().toUtc().toIso8601String()); //sample, convert, add
    String timesString = jsonEncode(times);
    hostSocket.write(timesString);
  }

  void listenForHostCmds(Socket hostSocket) {
    hostSocket.listen(
      (List<int> data) async {
        String givenCmd = utf8.decode(data);
        switch (givenCmd) {
          case "getRTT":
            handleHostRTTCmd(hostSocket);
          default:
            // here put: if single time, take pic,
            //might need to change this to JSON.parse
            // then if its an array of string vs one string we branch accordngly
            handleClockDiffCmd(hostSocket, givenCmd);

          // DateTime triggerTime = DateTime.parse(givenCmd).toLocal();
          // print(triggerTime);
          // handleHostCaptureCmd(triggerTime);
        }
      },
      onDone: () {
        hostSocket.destroy(); // Host closed connection
      },
      onError: (error) {
        print('Error: $error');
        hostSocket.destroy();
      },
      cancelOnError: true,
    );
  }

  Future<Socket?> establishTCPClientSocket() async {
    try {
      Socket hostSocket = await Socket.connect(defaultGateway, serverPort);
      print("client socket created");
      return hostSocket;
    } catch (e) {
      print('Error connecting to the server: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Client Launch')),
        body: FutureBuilder<void>(
          future: widget.initializeControllerFuture,
          builder: (context, snapshot) {
            //display when preview done loading
            if (snapshot.connectionState == ConnectionState.done) {
              return CameraPreview(widget.controller);
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),
      ),
    );
  }
}
//
//
///
//////
///
/////
////
////
////
////
///
///
///
///
///
//Basic Version (works)
// class MainScreen extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       home: Scaffold(
//         appBar: AppBar(
//           title: Text('LanScanner Example'),
//         ),
//         body:
//             MyLanScannerWidget(), //add parameters that specifies which subroutine to run (Servant or Host)
//       ),
//     );
//   }
// }  //make stateful

class connections extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('LanScanner Example'),
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                // MyLanScannerWidget(isHost: true); // Master
              },
              child: Text('Launch as Master'),
            ),
            ElevatedButton(
              onPressed: () {
                // MyLanScannerWidget(isHost: false); // Servant
              },
              child: Text('Launch as Servant'),
            ),
          ],
        ),
      ),
    );
  }
}

class MyLanScannerWidget extends StatefulWidget {
  // final bool isHost; // Add parameter to determine if it's a host or client

  const MyLanScannerWidget({
    super.key,
    // required this.isHost,
  });

  @override
  MyLanScannerWidgetState createState() =>
      MyLanScannerWidgetState(); //(isHost);
}

class MyLanScannerWidgetState extends State<MyLanScannerWidget> {
  /* note: 
  the "@override Widget build(BuildContext context)" function below 
  has access to the variables declared here. */

  // final bool isHost;
  // MyLanScannerWidgetState(this.isHost);

  final port = 80;
  int iPinitial = 1;
  int iPfinal = 255; // will check  up until this address
  final scanner = LanScanner();
  List<String> addresses = [];

  String displayText =
      "1) Manually connect to Host's Wi-Fi hotspot 2) Click button to scan local network devices"; // Variable to store the text to be displayed

  // Get WiFi IP subnet
  Future<String?> getSubnetIP() async {
    final wifiIP = await NetworkInfo().getWifiIP();
    if (wifiIP != null) {
      return ipToSubnet(wifiIP);
    } else {
      return null; // Return null if wifiIP is null.
    }
  }

  // Get this device's IP address
  Future<String?> getIP() async {
    final wifiIP = await NetworkInfo().getWifiIP();
    if (wifiIP != null) {
      return wifiIP;
    } else {
      return null; // Return null if wifiIP is null.
    }
  }

  Future<List<String>> findLocalDevices() async {
    Completer<List<String>> completer = Completer<List<String>>();
    int addrCount = 0;
    // StreamSubscription<DeviceModel> sub;

    try {
      String? currIP = await getIP();
      String? subnet = await getSubnetIP();

      // Scan Local Network
      if (subnet != null) {
        Stream<DeviceModel> possibleStream = scanner.preciseScan(
          subnet,
          firstIP: iPinitial,
          lastIP: iPfinal,
          progressCallback: (ProgressModel progress) {
            addrCount = addrCount + 1;
            /* preciseScan seems to fail to properly close the stream, thus we use the progress function and a 'completer'  
            to manually 'complete the 'Future'.  This method might fail for the final IP address (not sure about this either way) */
            if (addrCount == iPfinal) {
              addresses.remove(
                  currIP); // removes its own IP address from scan results
              completer.complete(addresses);
            }
            print(
                '${(progress.percent * 100).toStringAsFixed(2)}% $subnet.${progress.currIP}');
          },
        );
        // Callback function that is called every time a new device is found
        possibleStream.listen((DeviceModel device) {
          if (device.exists && device.ip != null) {
            print("Found device on ${device.ip}");
            addresses.add(device.ip.toString());
          }
        });
      } else {
        completer.completeError("Subnet not found");
      }
    } catch (e) {
      completer.completeError(e);
    }
    return completer.future;
  }

  @override
  void initState() {
    super.initState();
  }

  void establishTCPClientSocket() async {
    // List<String> addresses    (the eventual parameter)
    const String serverIp = '192.168.102.251';
    const int serverPort = 49153;

    // Create a TCP socket connection
    try {
      Socket socket = await Socket.connect(serverIp, serverPort);

      // Handle data received from the server
      socket.listen(
        (List<int> data) {
          String receivedData = String.fromCharCodes(data);
          print('Received data: $receivedData');
        },
        onDone: () {
          print('Connection closed by the server');
          socket.destroy();
        },
        onError: (error) {
          print('Error: $error');
          socket.destroy();
        },
        cancelOnError: true,
      );

      // Send data to the server
      String message = 'Hello, server!';
      socket.write(message);

      // Close the connection after sending the message
      // await socket.flush();
      // socket.close();
    } catch (e) {
      print('Error connecting to the server: $e');
    }
  }

  void establishTCPServerSocket() async {
    final server = await ServerSocket.bind('192.168.102.251', 49153);
    print('Server listening on ${server.address}:${server.port}');
    //runs indefintely
    await for (var socket in server) {
      //white board here

      handleClient(socket);
    }
  }

  void handleClient(Socket client) {
    print('Client connected: ${client.remoteAddress}:${client.remotePort}');

    client.listen(
      (List<int> data) {
        String message = utf8.decode(data);
        print('Received message: $message');

        // Process the received data or send a response
        // For example, echoing the message back to the client:
        print('Replied: SUCCESS');
        client.write('SUCCESS');
      },
      onDone: () {
        print(
            'Client disconnected: ${client.remoteAddress}:${client.remotePort}');
        client.close();
      },
      onError: (error) {
        print('Error: $error');
        client.close();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Local Network Devices')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // if (isHost) {
          //   setState(() {
          //     displayText = 'Running Master'; // Change this text as needed
          //   });
          //   print("Master");
          // } else {
          //   setState(() {
          //     displayText = 'Running Servant'; // Change this text as needed
          //   });
          //   print("Servant");
          // }

          establishTCPClientSocket();
          setState(() {
            displayText = 'Client Running'; // Change this text as needed
          });

          //right here make an if-else statement based on the Host/Client argument.

          setState(() {
            displayText =
                'Searching for devices.'; // Change this text as needed
          });
          addresses = await findLocalDevices();
          print("Addresses: $addresses");
          setState(() {
            displayText = 'Devices Found.'; // Change this text as needed
          });
        },
        child: const Icon(Icons.wifi_calling_3_sharp),
      ),
      body: Center(
        child: Text(displayText),
      ),
    );
  }
}

// A screen that allows users to take a picture using a given camera.
// class TakePictureScreen extends StatefulWidget {
//   const TakePictureScreen({
//     super.key,
//     required this.camera,
//   });

//   final CameraDescription camera;

//   @override
//   TakePictureScreenState createState() => TakePictureScreenState();
// }

// class TakePictureScreenState extends State<TakePictureScreen> {
//   late CameraController _controller;
//   late Future<void> _initializeControllerFuture;

//   @override
//   void initState() {
//     super.initState();
//     // To display the current output from the Camera,
//     // create a CameraController.
//     _controller = CameraController(
//       // Get a specific camera from the list of available cameras.
//       widget.camera,
//       ResolutionPreset.medium, // Define the resolution to use.
//     );

//     // Next, initialize the controller. This returns a Future.
//     _initializeControllerFuture = _controller.initialize();
//   }

//   @override
//   void dispose() {
//     // Dispose of the controller when the widget is disposed.
//     _controller.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Take a picture')),
//       // You must wait until the controller is initialized before displaying the
//       // camera preview. Use a FutureBuilder to display a loading spinner until the
//       // controller has finished initializing.
//       body: FutureBuilder<void>(
//         future: _initializeControllerFuture,
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.done) {
//             // If the Future is complete, display the preview.
//             return CameraPreview(_controller);
//           } else {
//             // Otherwise, display a loading indicator.
//             return const Center(child: CircularProgressIndicator());
//           }
//         },
//       ),
//       floatingActionButton: FloatingActionButton(
//         // Provide an onPressed callback.
//         onPressed: () async {
//           // Take the Picture in a try / catch block. If anything goes wrong,
//           // catch the error.
//           try {
//             // Ensure that the camera is initialized.
//             await _initializeControllerFuture;

//             // Attempt to take a picture and get the file `image`
//             // where it was saved.
//             final image = await _controller.takePicture();

//             if (!mounted) return;

//             // If the picture was taken, display it on a new screen.
//             await Navigator.of(context).push(
//               MaterialPageRoute(
//                 builder: (context) => DisplayPictureScreen(
//                   // Pass the automatically generated path to the DisplayPictureScreen widget.
//                   imagePath: image.path,
//                 ),
//               ),
//             );
//           } catch (e) {
//             // If an error occurs, log the error to the console.
//             print(e);
//           }
//         },
//         child: const Icon(Icons.camera_alt),
//       ),
//     );
//   }
// }

// A widget that displays the picture taken by the user.
class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;

  const DisplayPictureScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      // The image is stored as a file on the device. Use the `Image.file`
      // constructor with the given path to display the image.
      body: Image.file(File(imagePath)),
    );
  }
}

// class MyLanScannerWidgetState extends State<MyLanScannerWidget> {
//   final port = 80;
//   final scanner = LanScanner();
//   List<String> addresses = [];

//   // Asynchronous method to get WiFi IP
//   Future<String?> getSubnetIP() async {
//     final wifiIP = await NetworkInfo().getWifiIP();
//     if (wifiIP != null) {
//       return ipToSubnet(wifiIP);
//     } else {
//       return null; // Return null if wifiIP is null.
//     }
//   }

//   List<String> findLocalDevices() {
//     Stream<DeviceModel> possibleStream;
//     List<String> addresses = [];

//     try {
//       getSubnetIP().then((result) {
//         print(result);
//         possibleStream = scanner.preciseScan(
//           result,
//           progressCallback: (ProgressModel progress) {
//             String logMessage =
//                 '${(progress.percent * 100).toStringAsFixed(2)}% $result${progress.currIP}';
//             print(logMessage);
//           },
//         );

//         // Callback function that is called every time a new device is found
//         possibleStream.listen((DeviceModel device) {
//           if (device.exists && device.ip != null) {
//             // addresses.add(device.ip);
//             print("Found device on ${device.ip}");
//             addresses.add(device.ip.toString());
//           }
//         });
//       });
//     } catch (e) {
//       print("getSubnetIP or preciseScan has failed");
//     }
//     print("Here");

//     return addresses;
//   }

//   @override
//   void initState() {
//     super.initState();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Find Local Network Devices')),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () {
//           addresses = findLocalDevices();
//         },
//         child: const Icon(Icons.wifi_calling_3_sharp),
//       ),
//       body: const Center(
//         child: Text("Click the Button to Begin Scanning for Devices"),
//       ),
//     );
//   }
// }

//   @override  // working button version
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Find Local Network Devices')),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () {
//           findLocalDevices();
//         },
//         child: const Icon(Icons.wifi_calling_3_sharp),
//       ),
//     );
//   }

// streamBuilder does not work properly
// @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//         appBar: AppBar(title: const Text('Find Local Network Devices')),
//         body: Center(
//           child: StreamBuilder<DeviceModel>(
//             stream: findLocalDevices(),
//             builder: (context, snapshot) {
//               if (snapshot.hasData) {
//                 print('Data from Stream: ${snapshot.data}');
//                 return Text('Data from Stream: ${snapshot.data}');
//               } else if (snapshot.hasError) {
//                 return Text('Error: ${snapshot.error}');
//               } else {
//                 return CircularProgressIndicator();
//               }
//             },
//           ),
//         ));
//   }

//   @override  // working button version
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Find Local Network Devices')),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () {
//           findLocalDevices();
//         },
//         child: const Icon(Icons.wifi_calling_3_sharp),
//       ),
//     );
//   }
// }

// @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Find Local Network Devices')),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () {
//           setState(() {
//             // Step 2 (Trigger the asynchronous operation)
//             devicesFuture = findLocalDevices();
//           });
//         },
//         child: const Icon(Icons.wifi_1_bar),
//       ),
//       body: Center(
//         child: FutureBuilder<List<String?>>(
//           // Step 3 (Use FutureBuilder)
//           future: devicesFuture,
//           builder: (context, snapshot) {
//             if (snapshot.connectionState == ConnectionState.waiting) {
//               return CircularProgressIndicator();
//             } else if (snapshot.hasError) {
//               return Text('Error: ${snapshot.error}');
//             } else {
//               List<String?> devices = snapshot.data ?? [];
//               return Text('Devices: ${devices.join(', ')}');
//             }
//           },
//         ),
//       ),
//     );
//   }

//   body: FutureBuilder<void>(
//   future: _initializeControllerFuture,
//   builder: (context, snapshot) {
//     if (snapshot.connectionState == ConnectionState.done) {
//       // If the Future is complete, display the preview.
//       return CameraPreview(_controller);
//     } else {
//       // Otherwise, display a loading indicator.
//       return const Center(child: CircularProgressIndicator());
//     }
//   },
// ),

// @override
// Widget build(BuildContext context) {
//   return Scaffold(
//     appBar: AppBar(title: const Text('Find Local Network Devices')),
//     floatingActionButton: FloatingActionButton(
//       // Provide an onPressed callback.
//       onPressed: startScanning,
//       child: const Icon(Icons.camera_alt),
//     ),
//   );
// }

// List<String?> devices = [];

// try {
//   String? subNet = await getSubnetIP(); // Await here

//   if (subNet != null) {
//     Stream<DeviceModel> stream = scanner.preciseScan(subNet);

//     stream.listen((DeviceModel device) {
//       // Callback function that is called every time a new device is found
//       if (device.exists && device.ip != null) {
//         devices.add(device.ip);
//       }
//     });
//   } else {
//     print("Subnet not found");
//   }
// } catch (e) {
//   print(e);
// }

// return devices;

// if (subNet != null) {
//         final stream = scanner.preciseScan(
//           subNet,
//           progressCallback: (ProgressModel progress) {
//             String logMessage =
//                 '${(progress.percent * 100).toStringAsFixed(2)}% $subNet${progress.currIP}';
//             print(logMessage);
//           },
//         );

//         stream.listen((DeviceModel device) {
//           //is a callback function, will be called everytime a new device is found
//           if (device.exists) {
//             String logMessage =
//                 "Found device on ${device.ip}:${device.port}"; //Does not return port, just IP, so device.prot is NULL
//             print(logMessage);
//           }
//         });
//       } else {
//         // Handle the case where subnet is null.
//         print("Subnet not found");
//       }

// quicScan version, odes not get any results.
//   getSubnetIP().then((subNet) {
//     if (subNet != null) {
//       // If subnet is not null, use it for preciseScan.
//       final stream = scanner.quickScan(subnet: subNet);
//       print("stream created");

//       stream.listen((DeviceModel device) {
//         //is a callback function, will be called everytime a new device is found
//         if (device.exists) {
//           print("Found device on ${device.ip}:${device.port}");
//         }
//       });
//     } else {
//       // Handle the case where subnet is null.
//       print("Subnet not found");
//     }
//   });
// }

// probably destroy
// class CheckConnectionsScreen extends StatefulWidget {
//   @override
//   CheckConnectionsScreenState createState() => CheckConnectionsScreenState();
// }

// class CheckConnectionsScreenState extends State<CheckConnectionsScreen> {
//   @override
//   void initState() {
//     super.initState();
//   }

//   @override
//   void dispose() {
//     super.dispose();
//   }

//   Widget build(BuildContext context) {
//     return Scaffold(appBar: AppBar(title: const Text('Take a picture')));
//   }
// }

// void main() async {
//   // Ensure that plugin services are initialized so that `availableCameras()` can be called before `runApp()`
//   WidgetsFlutterBinding.ensureInitialized();

//   // Obtain a list of the available cameras on the device.
//   final cameras = await availableCameras();

//   // Get a specific camera from the list of available cameras.
//   // final firstCamera = cameras.first;

//   runApp(MyApp());
// }

// class MyApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     // Define your app's UI here
//     return MaterialApp(
//       home: Scaffold(
//         appBar: AppBar(
//           title: Text('Camera App'),
//         ),
//         body: Center(
//           child: Text('Camera is ready!'),
//         ),
//       ),
//     );
//   }
// }
