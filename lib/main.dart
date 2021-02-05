import 'dart:async';
import 'dart:convert';

import 'package:background_fetch/background_fetch.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event.dart';

const kEventKey = 'fetch_events';

// for debugging
Future<void> logging(String message) async {
  // 삼성: 7777 or 화웨이: 8888 or 애플: 9999
  final port = '9999';
  try {
    await http.get('http://192.168.0.45:$port/fetch?$message').timeout(Duration(seconds: 3));
  } catch (e) {
    print(e);
  }
}

// for debugging
Future<void> addEventInSharedPreferences(Event event) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String json = prefs.getString(kEventKey) ?? '[]';
  final List events = jsonDecode(json)..add(event.toJson());
  prefs.setString(kEventKey, jsonEncode(events));
}

/// This "Headless Task" is run when app is terminated.
Future<void> headlessTask(String taskId) async {
  Event event = Event(title: 'headlessTask');
  await addEventInSharedPreferences(event);
  await logging(event.title);
  // IMPORTANT:  You must signal completion of your fetch task or the OS can punish your app
  // for taking too long in the background.
  BackgroundFetch.finish(taskId);
}

void main() {
  initializeDateFormatting();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(home: TestScreen());
}

class TestScreen extends StatefulWidget {
  @override
  _TestScreenState createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> with WidgetsBindingObserver {
  String _status = '';
  List<Event> _events = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _onLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onLoad();
  }

  Future<void> _onLoad() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String json = prefs.getString(kEventKey) ?? '[]';
    _events = jsonDecode(json).map<Event>((v) => Event.fromJson(v)).toList();
    final int status = await BackgroundFetch.status;
    _status = _statusToString(status);
    print('current status: $_status, events: $_events');
    setState(() {});
    if (!mounted) return;
  }

  Future<void> _onConfigure() async {
    final success = await BackgroundFetch.registerHeadlessTask(headlessTask);
    if (!success) throw Exception('fail: register headless task');
    final int status = await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval: 15,
        forceAlarmManager: false,
        stopOnTerminate: false,
        startOnBoot: true,
        enableHeadless: true,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresStorageNotLow: false,
        requiresDeviceIdle: false,
        requiredNetworkType: NetworkType.ANY,
      ),
      _task,
    );
    _status = _statusToString(status);
    await addEventInSharedPreferences(Event(title: '# configure: $_status'));
  }

  Future<void> _onStart() async {
    final int status = await BackgroundFetch.start();
    _status = _statusToString(status);
    await addEventInSharedPreferences(Event(title: '# start: $_status'));
  }

  Future<void> _onStopAll() async {
    final int status = await BackgroundFetch.stop();
    _status = _statusToString(status);
    await addEventInSharedPreferences(Event(title: '# stop: $_status'));
  }

  Future<void> _onClear() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.remove(kEventKey);
    setState(() => _events = []);
  }

  Future<void> _task(String taskId) async {
    Event event = Event(title: 'task');
    await addEventInSharedPreferences(event);
    await logging(event.title);
    // IMPORTANT:  You must signal completion of your fetch task or the OS can punish your app
    // for taking too long in the background.
    BackgroundFetch.finish(taskId);
    _onLoad();
  }

  /// [BackgroundFetch]의 status 관련 static 상수 참고
  String _statusToString(int status) {
    switch (status) {
      case 0:
        return 'restricted';
      case 1:
        return 'denied';
      case 2:
        return 'available';
      default:
        return 'invalid';
    }
  }

  void showError(String errorMessage) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) {
        return Container(
          height: 200,
          child: Center(
            child: ListView(
              padding: EdgeInsets.all(15),
              children: <Widget>[Text(errorMessage)],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('BackgroundFetch Example'),
        actions: [IconButton(icon: Icon(Icons.refresh), onPressed: _onLoad)],
        backgroundColor: Colors.green,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            title: Text('Status'),
            trailing: Text('$_status'),
          ),
          RaisedButton(
            child: Text('configure & start'),
            onPressed: _onConfigure,
          ),
          RaisedButton(
            child: Text('start'),
            onPressed: _onStart,
          ),
          RaisedButton(
            child: Text('stop'),
            onPressed: _onStopAll,
          ),
          RaisedButton(
            child: Text('clear'),
            onPressed: _onClear,
          ),
          SizedBox(height: 10),
          if (_events.isEmpty)
            Center(child: Text('이벤트 없음'))
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onLoad,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _events.length,
                  itemBuilder: (_, i) {
                    final Event event = _events[i];
                    final bool hasError = event.error.isNotEmpty;
                    final Color textColors = hasError ? Colors.blue : Colors.black87;
                    String logTimeIntervalMinutes = '';
                    if (i != 0) {
                      final DateTime previousEventTime = _events[i - 1].logTime;
                      final int interval =
                          event.logTime.difference(previousEventTime).inMinutes.abs();
                      if (interval != 0) logTimeIntervalMinutes = ' ($interval분)';
                    }
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(
                        event.title + logTimeIntervalMinutes,
                        style: TextStyle(color: textColors),
                      ),
                      trailing: Text(
                        DateFormat('M/d a H:mm:ss', 'ko').format(event.logTime),
                        style: TextStyle(color: textColors),
                      ),
                      onTap: hasError ? () => showError(event.error) : null,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
