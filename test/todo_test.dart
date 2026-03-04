import 'package:flutter_test/flutter_test.dart';
import 'package:fitness/todo_service.dart';

void main() {
  test('Adding todo increases list length', () {
    List<TodoItem> todos = [];

    todos.add(TodoItem(title: "New Task"));

    expect(todos.length, 1);
    expect(todos[0].title, "New Task");
  });
}