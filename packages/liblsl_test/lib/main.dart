import 'package:flutter/material.dart';
import 'package:liblsl/native_liblsl.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Test App', home: MyApp2());
  }
}

class MyApp2 extends StatefulWidget {
  const MyApp2({super.key});

  @override
  State<MyApp2> createState() => _MyApp2State();
}

class _MyApp2State extends State<MyApp2> {
  late Future<int> _lslver;

  @override
  void initState() {
    super.initState();
    _lslver = setupLSL();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        FutureBuilder<int>(
          future: _lslver,
          builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
            if (snapshot.hasData) {
              return Text(
                'LSL Version ${snapshot.data}',
                overflow: TextOverflow.visible,
                textScaler: TextScaler.linear(0.5),
              );
            } else if (snapshot.hasError) {
              return Text(
                'Error: ${snapshot.error}',
                overflow: TextOverflow.visible,
                textScaler: TextScaler.linear(0.5),
              );
            } else {
              return Text(
                'Calculating answer...',
                overflow: TextOverflow.visible,
                textScaler: TextScaler.linear(0.5),
              );
            }
          },
        ),
      ],
    );
  }
}

Future<int> setupLSL() async {
  return lsl_library_version();
}
