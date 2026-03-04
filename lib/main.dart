import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fitness/todo_service.dart';

void main() {
  runApp(const HelloWorld());
}

class HelloWorld extends StatelessWidget {
  const HelloWorld({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: TodoScreen(),
    );
  }
}

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  List<TodoItem> todos = [];
  final TextEditingController controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadTodos();
  }

  Future<void> loadTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('todos');

    if (data != null) {
      List decoded = jsonDecode(data);
      setState(() {
        todos = decoded.map((e) => TodoItem.fromMap(e)).toList();
      });
    }
  }

  Future<void> saveTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded =
        jsonEncode(todos.map((e) => e.toMap()).toList());
    await prefs.setString('todos', encoded);
  }

  void addTodo(String title) {
    if (title.isEmpty) return;

    setState(() {
      todos.add(TodoItem(title: title));
    });

    controller.clear();
    saveTodos();
  }

  void toggleTodo(int index, bool? value) {
    setState(() {
      todos[index].isDone = value ?? false;
    });
    saveTodos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('To Do List')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: todos.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(
                    todos[index].title,
                    style: TextStyle(
                      decoration: todos[index].isDone
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  trailing: Checkbox(
                    value: todos[index].isDone,
                    onChanged: (value) =>
                        toggleTodo(index, value),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(child: TextField(controller: controller)),
                TextButton(
                  onPressed: () => addTodo(controller.text),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}