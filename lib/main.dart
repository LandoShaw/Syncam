import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:lan_scanner/lan_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';

// import 'package:network_discovery/network_discovery.dart';

// import 'package:dart_discover/dart_discover.dart';

// Future<void> main() async {
// // Ensure that plugin services are initialized so that `availableCameras()`
// // can be called before `runApp()`
// WidgetsFlutterBinding.ensureInitialized();

// // Obtain a list of the available cameras on the device.
// final cameras = await availableCameras();

// // Get a specific camera from the list of available cameras.
// final firstCamera = cameras.first;

// runApp(
//   MaterialApp(
//     theme: ThemeData.dark(),
//     home: TakePictureScreen(
//       // Pass the appropriate camera to the TakePictureScreen widget.
//       camera: firstCamera,
//     ),
//   ),
// );
// }

void main() {
  runApp(Connections());
}

// class Connections extends StatelessWidget {
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
// }

class Connections extends StatelessWidget {
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
                MyLanScannerWidget(isHost: true); // Master
              },
              child: Text('Launch as Master'),
            ),
            ElevatedButton(
              onPressed: () {
                MyLanScannerWidget(isHost: false); // Servant
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
  final bool isHost; // Add parameter to determine if it's a host or client

  const MyLanScannerWidget({
    super.key,
    required this.isHost,
  });

  @override
  MyLanScannerWidgetState createState() => MyLanScannerWidgetState(isHost);
}

class MyLanScannerWidgetState extends State<MyLanScannerWidget> {
  /* note: 
  the "@override Widget build(BuildContext context)" function below 
  has access to the variables declared here. */

  final bool isHost;
  MyLanScannerWidgetState(this.isHost);

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
          if (isHost) {
            setState(() {
              displayText = 'Running Master'; // Change this text as needed
            });
            print("Master");
          } else {
            setState(() {
              displayText = 'Running Servant'; // Change this text as needed
            });
            print("Servant");
          }

          // establishTCPClientSocket();
          // setState(() {
          //   displayText = 'Client Running'; // Change this text as needed
          // });

          //right here make an if-else statement based on the Host/Client argument.

          // setState(() {
          //   displayText =
          //       'Searching for devices.'; // Change this text as needed
          // });
          // addresses = await findLocalDevices();
          // print("Addresses: $addresses");
          // setState(() {
          //   displayText = 'Devices Found.'; // Change this text as needed
          // });
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
class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({
    super.key,
    required this.camera,
  });

  final CameraDescription camera;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    // To display the current output from the Camera,
    // create a CameraController.
    _controller = CameraController(
      // Get a specific camera from the list of available cameras.
      widget.camera,
      // Define the resolution to use.
      ResolutionPreset.medium,
    );

    // Next, initialize the controller. This returns a Future.
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Take a picture')),
      // You must wait until the controller is initialized before displaying the
      // camera preview. Use a FutureBuilder to display a loading spinner until the
      // controller has finished initializing.
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // If the Future is complete, display the preview.
            return CameraPreview(_controller);
          } else {
            // Otherwise, display a loading indicator.
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        // Provide an onPressed callback.
        onPressed: () async {
          // Take the Picture in a try / catch block. If anything goes wrong,
          // catch the error.
          try {
            // Ensure that the camera is initialized.
            await _initializeControllerFuture;

            // Attempt to take a picture and get the file `image`
            // where it was saved.
            final image = await _controller.takePicture();

            if (!mounted) return;

            // If the picture was taken, display it on a new screen.
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DisplayPictureScreen(
                  // Pass the automatically generated path to the DisplayPictureScreen widget.
                  imagePath: image.path,
                ),
              ),
            );
          } catch (e) {
            // If an error occurs, log the error to the console.
            print(e);
          }
        },
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}

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
