import 'dart:async';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:cron/cron.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int? _stepNow;
  int? _oldStep;
  late Stream<StepCount> stepCountStream;

  var _stepList = [];
  var _dateList = [];
  var _locationList = [];

  @override
  void initState() {
    super.initState();
    initAll();
    autoRefreshScrean();
  }

  initAll() async {
    // await test();
    await permissionInit();
    await initHive();
    await initBackground();
    initPedometer();
  }

  test() async {
    Hive.init((await getApplicationDocumentsDirectory()).path);
    (await Hive.openBox('oldStep')).clear();
    (await Hive.openBox('steps')).clear();
    (await Hive.openBox('locations')).clear();
  }

  permissionInit() async {
    if (!(await Permission.activityRecognition.isGranted)) {
      Permission.activityRecognition.request();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (await Geolocator.checkPermission() != 'alway') {
      Permission.locationAlways.request();
    }
  }

  void initPedometer() {
    stepCountStream = Pedometer.stepCountStream;
    stepCountStream.listen((s) {
      _stepNow = s.steps.toInt();
      setState(() {});
    });
    if (!mounted) return;
  }

  initHive() async {
    Hive.init((await getApplicationDocumentsDirectory()).path);
    var oldStepBox = await Hive.openBox('oldStep');
    var stepsBox = await Hive.openBox('steps');

    if (oldStepBox.isEmpty) {
      oldStepBox.put('data', (await Pedometer.stepCountStream.first).steps);
    }
    _stepNow = (await Pedometer.stepCountStream.first).steps;
    _oldStep = oldStepBox.get('data');

    _stepList = stepsBox.values.toList().reversed.map((e) => e['steps']).toList();
    _dateList = stepsBox.values.toList().reversed.toList().map((e) => dateTimeToYYYYMMDD(e['date'])).toList();

    setState(() {});
  }

  autoRefreshScrean() async {
    Hive.init((await getApplicationDocumentsDirectory()).path);
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      var locationBox = await Hive.openBox('locations');
      var oldStepBox = await Hive.openBox('oldStep');
      var stepsBox = await Hive.openBox('steps');

      _oldStep = oldStepBox.get('data');
      _locationList = locationBox.values.toList().reversed.toList();
      _stepList = stepsBox.values.toList().reversed.map((e) => e['steps']).toList();
      _dateList = stepsBox.values.toList().reversed.toList().map((e) => dateTimeToYYYYMMDD(e['date'])).toList();

      await locationBox.close();
      await oldStepBox.close();
      await stepsBox.close();
      setState(() {});
    });
  }

  dateTimeToYYYYMMDD(DateTime date) {
    String Y = date.year.toString();
    String M = date.month.toString().padLeft(2, '0');
    String D = date.day.toString().padLeft(2, '0');
    return '$Y:$M:$D';
  }

  formatLocationData(Map data, [Map? data2]) {
    DateTime d = data['time'];
    double log = data['longitude'];
    double lat = data['latitude'];
    double log2 = data2!['longitude'];
    double lat2 = data2['latitude'];
    String distance = Geolocator.distanceBetween(lat, log, lat2, log2).toStringAsFixed(2);

    String h = d.hour.toString().padLeft(2, '0');
    String m = d.minute.toString().padLeft(2, '0');
    String s = d.second.toString().padLeft(2, '0');

    String res = '시간:$h:$m:$s 경도:$log 위도:$lat 이동거리:$distance미터';

    return res;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 50,
            ),
            Text('_stepNow:${_stepNow ?? 0}'),
            Text('_stepInDB:${_oldStep ?? 0}'),
            Text('today steps:${(_stepNow ?? 0) - (_oldStep ?? 0)}'),
            SizedBox(
              height: 150,
              child: ListView.builder(
                itemCount: _stepList.length,
                itemBuilder: (context, index) => Text(
                  '${_dateList[index]}:${_stepList[index]}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _locationList.length,
                itemBuilder: (context, index) => Text(
                  formatLocationData(_locationList[index],
                      _locationList[index + 1 >= _locationList.length ? _locationList.length - 1 : index + 1]),
                  textAlign: TextAlign.left,
                  style: const TextStyle(fontSize: 17),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

initBackground() async {
  final service = FlutterBackgroundService();
  if (!await service.isRunning()) {
    var androidConfig = AndroidConfiguration(onStart: onStart, autoStart: true, isForegroundMode: true);
    var iosConfig = IosConfiguration(autoStart: false, onForeground: onStart, onBackground: (a) => false);
    await service.configure(androidConfiguration: androidConfig, iosConfiguration: iosConfig);
    await service.startService();
  }
}

onStart(ServiceInstance s) async {
  WidgetsFlutterBinding.ensureInitialized();
  String path = (await getApplicationDocumentsDirectory()).path;
  Hive.init(path);

  saveGeoLocationDAta();
  saveTodaysStepData();
}

saveTodaysStepData() async {
  final cron = Cron();
  var everyDay = Schedule.parse('0 0 * * *');
  var stepsBox = await Hive.openBox('steps');
  var oldStepBox = await Hive.openBox('oldStep');

  cron.schedule(everyDay, () async {
    int newStepCounterData = (await Pedometer.stepCountStream.first).steps;
    int oldStepCounterData = oldStepBox.get('data');
    int todayStep = newStepCounterData - oldStepCounterData;

    stepsBox.add({'date': DateTime.now().add(const Duration(days: -1)), 'steps': todayStep});
    oldStepBox.put('data', newStepCounterData);
  });
}

saveGeoLocationDAta() async {
  late LocationSettings locationSettings;
  var locationBox = await Hive.openBox('locations');

  if (defaultTargetPlatform == TargetPlatform.android) {
    locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 3,
      forceLocationManager: false,
      intervalDuration: const Duration(seconds: 1),
    );
  }

  Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position? position) async {
    if (position != null) {
      locationBox.add({
        'time': DateTime.now(),
        'latitude': position.latitude,
        'longitude': position.longitude,
      });
    }
  });

  // Timer.periodic(const Duration(seconds: 1), (timer) async {
  //   var location = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);

  //   locationBox.add({
  //     'time': DateTime.now(),
  //     'latitude': location.latitude,
  //     'longitude': location.longitude,
  //   });
  // });
}
