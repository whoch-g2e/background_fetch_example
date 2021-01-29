class Event {
  String title;
  String error;
  DateTime logTime;

  Event({this.title = '', this.error = '', DateTime logTime})
      : this.logTime = logTime ?? DateTime.now();

  factory Event.fromJson(Map json) => Event(
      title: json['title'] ?? '',
      error: json['error'] ?? '',
      logTime: DateTime.tryParse(json['logTime']));

  Map toJson() => {
        'title': title,
        if (error.isNotEmpty) 'error': error,
        'logTime': '$logTime',
      };

  @override
  String toString() => '${toJson()}';
}
