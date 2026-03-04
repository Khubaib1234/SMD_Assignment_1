class TodoItem {
  String title;
  bool isDone;

  TodoItem({required this.title, this.isDone = false});

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'isDone': isDone,
    };
  }

  factory TodoItem.fromMap(Map<String, dynamic> map) {
    return TodoItem(
      title: map['title'],
      isDone: map['isDone'],
    );
  }
}