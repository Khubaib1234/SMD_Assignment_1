import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;


// ─────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────

class Todo {
  final int? id;
  final String title;
  final String description;
  final bool isDone;
  final DateTime? createdAt;
  final int? userId;

  Todo({
    this.id,
    required this.title,
    required this.description,
    this.isDone = false,
    this.createdAt,
    this.userId,
  });

  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: json['id'] as int?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isDone: json['completed'] as bool? ?? json['isDone'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      userId: json['userId'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'title': title,
        if (description.isNotEmpty) 'description': description,
        'completed': isDone,
        if (userId != null) 'userId': userId,
      };

  Todo copyWith({int? id, String? title, String? description, bool? isDone, DateTime? createdAt, int? userId}) {
    return Todo(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isDone: isDone ?? this.isDone,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
    );
  }
}

class PaginatedResponse {
  final List<Todo> todos;
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;

  PaginatedResponse({
    required this.todos,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  factory PaginatedResponse.fromJson(Map<String, dynamic> json, int page, int pageSize) {
    final List<dynamic> data = json['data'] as List<dynamic>? ?? [];
    final todos = data.map((e) => Todo.fromJson(e as Map<String, dynamic>)).toList();
    // API returns pagination nested under 'pagination' key
    final pag = json['pagination'] as Map<String, dynamic>?;
    final bool hasNext = pag?['hasNext'] as bool? ?? false;
    final int total = pag?['total'] as int? ?? todos.length;
    return PaginatedResponse(
      todos: todos,
      total: total,
      page: page,
      pageSize: pageSize,
      hasMore: hasNext,
    );
  }
}

// ─────────────────────────────────────────────
// API SERVICE
// ─────────────────────────────────────────────

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class TodoApiService {
  static const String _baseUrl = 'https://apimocker.com/todos';
  static const int _pageSize = 10;
  final http.Client _client = http.Client();

  static const List<String> _proxies = [
    'https://corsproxy.io/?',
    'https://api.allorigins.win/raw?url=',
  ];

  String _p(String url) {
    if (!kIsWeb) return url;
    return '${_proxies[0]}${Uri.encodeFull(url)}';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // Single-item responses are wrapped as { "data": {...} } — unwrap them
  Map<String, dynamic> _unwrap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('data') && decoded['data'] is Map<String, dynamic>) {
        return decoded['data'] as Map<String, dynamic>;
      }
      return decoded;
    }
    throw ApiException('Unexpected response format');
  }

  Future<PaginatedResponse> fetchTodos({int page = 1}) async {
    return _tryWithProxies((proxyUrl) async {
      final rawUrl = Uri.parse(_baseUrl).replace(queryParameters: {
        'page': page.toString(),
        'limit': _pageSize.toString(),
        '_sort': 'id',
        '_order': 'desc',
      }).toString();
      final url = kIsWeb ? '$proxyUrl${Uri.encodeFull(rawUrl)}' : rawUrl;
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is List) {
          final todos = decoded.map((e) => Todo.fromJson(e as Map<String, dynamic>)).toList();
          return PaginatedResponse(
            todos: todos, total: todos.length, page: page,
            pageSize: _pageSize, hasMore: todos.length == _pageSize,
          );
        } else if (decoded is Map<String, dynamic>) {
          return PaginatedResponse.fromJson(decoded, page, _pageSize);
        }
        throw ApiException('Unexpected response format');
      }
      throw ApiException(
        _parseError(response.body) ?? 'Failed to load todos (${response.statusCode})',
        statusCode: response.statusCode,
      );
    });
  }

  Future<Todo> createTodo(String title, String description) async {
    return _tryWithProxies((proxyUrl) async {
      final url = kIsWeb ? '$proxyUrl${Uri.encodeFull(_baseUrl)}' : _baseUrl;
      // Send all fields the API might require
      final desc = description.trim();
      final body = jsonEncode({
        'title': title.trim(),
        if (desc.isNotEmpty) 'description': desc,
        'completed': false,
        'userId': 1,
      });
      final response = await _client
          .post(Uri.parse(url), headers: _headers, body: body)
          .timeout(const Duration(seconds: 15));

      // Log raw response for debugging
      debugPrint('[CREATE] status=${response.statusCode} body=${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        // If server returns the created object, parse it; otherwise build a local one
        if (decoded is Map<String, dynamic>) {
          return Todo.fromJson(_unwrap(decoded));
        }
        // Fallback: return a local Todo so the UI still updates
        return Todo(
          title: title.trim(),
          description: description.trim(),
          isDone: false,
          createdAt: DateTime.now(),
        );
      }
      // 429 = rate limit exceeded (apimocker allows 100 writes/day per IP)
      if (response.statusCode == 429) {
        throw ApiException('Daily write limit reached (100/day). Try again tomorrow.', statusCode: 429);
      }
      throw ApiException(
        _parseError(response.body) ?? 'Failed to create todo (${response.statusCode})',
        statusCode: response.statusCode,
      );
    });
  }

  Future<Todo> updateTodo(Todo todo) async {
    if (todo.id == null) throw ApiException('Todo ID required');
    return _tryWithProxies((proxyUrl) async {
      final rawUrl = '$_baseUrl/${todo.id}';
      final url = kIsWeb ? '$proxyUrl${Uri.encodeFull(rawUrl)}' : rawUrl;
      final body = jsonEncode(todo.toJson());
      final response = await _client
          .patch(Uri.parse(url), headers: _headers, body: body)
          .timeout(const Duration(seconds: 15));

      // Log raw response for debugging
      debugPrint('[UPDATE] status=${response.statusCode} body=${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return Todo.fromJson(_unwrap(decoded));
        }
        // Fallback: return the optimistically-updated todo
        return todo;
      }
      throw ApiException(
        _parseError(response.body) ?? 'Failed to update todo (${response.statusCode})',
        statusCode: response.statusCode,
      );
    });
  }

  Future<T> _tryWithProxies<T>(Future<T> Function(String proxyUrl) fn) async {
    if (!kIsWeb) {
      try {
        return await fn('');
      } catch (e) {
        throw e is ApiException ? e : ApiException('Network error: $e');
      }
    }
    ApiException? lastError;
    for (final proxy in _proxies) {
      try {
        return await fn(proxy);
      } on ApiException catch (e) {
        lastError = e;
        if (e.statusCode != null) rethrow;
      } catch (e) {
        lastError = ApiException('Request failed: $e');
      }
    }
    throw lastError ?? ApiException('All proxy attempts failed.');
  }

  String? _parseError(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) {
        final msg = d['message'] as String? ?? d['error'] as String?;
        // "Database operation failed" = apimocker daily write limit reached (100/day per IP)
        if (msg != null && msg.toLowerCase().contains('database operation failed')) {
          return 'API daily write limit reached (100/day). Resets at midnight UTC (5:00 AM PKT). Please try again later.';
        }
        final details = d['details'] as List<dynamic>?;
        if (details != null && details.isNotEmpty) {
          final detailMsgs = details
              .map((e) => e is Map ? e['message'] as String? : null)
              .whereType<String>()
              .join(', ');
          return detailMsgs.isNotEmpty ? detailMsgs : msg;
        }
        return msg;
      }
    } catch (_) {}
    return null;
  }

  void dispose() => _client.close();
}

// ─────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────

void main() => runApp(const TodoApp());

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todo App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A6CF7)),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF4A6CF7),
          foregroundColor: Colors.white,
          centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4A6CF7), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: const TodoListScreen(),
    );
  }
}

// ─────────────────────────────────────────────
// TODO LIST SCREEN
// ─────────────────────────────────────────────

class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  final TodoApiService _api = TodoApiService();
  final ScrollController _scrollController = ScrollController();

  final List<Todo> _todos = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _api.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) _loadMore();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
      if (refresh) { _todos.clear(); _currentPage = 1; _hasMore = true; }
    });
    try {
      final result = await _api.fetchTodos(page: 1);
      setState(() { _todos.addAll(result.todos); _hasMore = result.hasMore; });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _api.fetchTodos(page: _currentPage + 1);
      setState(() { _todos.addAll(result.todos); _currentPage++; _hasMore = result.hasMore; });
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _toggle(Todo todo) async {
    final updated = todo.copyWith(isDone: !todo.isDone);
    final index = _todos.indexWhere((t) => t.id == todo.id);
    if (index == -1) return;
    setState(() => _todos[index] = updated);
    try {
      final result = await _api.updateTodo(updated);
      setState(() => _todos[index] = result);
    } on ApiException catch (e) {
      setState(() => _todos[index] = todo);
      _showSnack(e.message, isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _goToAdd() async {
    final result = await Navigator.push<Todo>(
      context,
      MaterialPageRoute(builder: (_) => AddTodoScreen(api: _api)),
    );
    if (result != null) setState(() => _todos.insert(0, result));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Todo List'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goToAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add Todo'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _todos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _todos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _load(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: Column(children: [
        if (_error != null)
          _ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
        Expanded(
          child: _todos.isEmpty
              ? _EmptyState(onRefresh: () => _load(refresh: true))
              : ListView.separated(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                  itemCount: _todos.length + (_isLoadingMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == _todos.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _TodoTile(todo: _todos[index], onToggle: () => _toggle(_todos[index]));
                  },
                ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// ADD TODO SCREEN
// ─────────────────────────────────────────────

class AddTodoScreen extends StatefulWidget {
  final TodoApiService api;
  const AddTodoScreen({super.key, required this.api});

  @override
  State<AddTodoScreen> createState() => _AddTodoScreenState();
}

class _AddTodoScreenState extends State<AddTodoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _titleFocus = FocusNode();
  final _descFocus = FocusNode();
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _titleFocus.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isSubmitting = true; _submitError = null; });
    try {
      final todo = await widget.api.createTodo(_titleCtrl.text.trim(), _descCtrl.text.trim());
      if (mounted) Navigator.pop(context, todo);
    } on ApiException catch (e) {
      setState(() => _submitError = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Todo'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.add_task_rounded, size: 56, color: cs.primary),
              const SizedBox(height: 8),
              Text('Create a new task', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
              const SizedBox(height: 32),

              if (_submitError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.error_outline, color: cs.onErrorContainer, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_submitError!,
                        style: TextStyle(color: cs.onErrorContainer, fontSize: 14))),
                    GestureDetector(
                      onTap: () => setState(() => _submitError = null),
                      child: Icon(Icons.close, color: cs.onErrorContainer, size: 18),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              TextFormField(
                controller: _titleCtrl,
                focusNode: _titleFocus,
                enabled: !_isSubmitting,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                maxLength: 100,
                onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_descFocus),
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  hintText: 'Enter todo title',
                  prefixIcon: Icon(Icons.title_rounded),
                  helperText: 'Required',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Title is required';
                  if (v.trim().length < 3) return 'At least 3 characters';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _descCtrl,
                focusNode: _descFocus,
                enabled: !_isSubmitting,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  hintText: 'Enter todo description',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 60),
                    child: Icon(Icons.description_rounded),
                  ),
                  helperText: 'Required',
                  alignLabelWithHint: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Description is required';
                  if (v.trim().length < 5) return 'At least 5 characters';
                  return null;
                },
              ),
              const SizedBox(height: 32),

              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded),
                  label: Text(_isSubmitting ? 'Adding...' : 'Add Todo',
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────

class _TodoTile extends StatelessWidget {
  final Todo todo;
  final VoidCallback onToggle;

  const _TodoTile({required this.todo, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = todo.isDone;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: done ? cs.outlineVariant.withOpacity(0.4) : cs.outlineVariant,
        ),
      ),
      color: done ? cs.surfaceVariant.withOpacity(0.4) : cs.surface,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? cs.primary : Colors.transparent,
                  border: done ? null : Border.all(color: cs.outline, width: 1.5),
                ),
                child: done ? Icon(Icons.check_rounded, size: 16, color: cs.onPrimary) : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  todo.title,
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: done ? cs.onSurface.withOpacity(0.4) : cs.onSurface,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: cs.onSurface.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  todo.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: done ? cs.onSurface.withOpacity(0.3) : cs.onSurface.withOpacity(0.6),
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: cs.onSurface.withOpacity(0.3),
                  ),
                ),
                if (todo.createdAt != null) ...[
                  const SizedBox(height: 6),
                  Text(_formatDate(todo.createdAt!),
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.4))),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: done ? cs.primaryContainer : cs.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                done ? 'Done' : 'Pending',
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w500,
                  color: done ? cs.onPrimaryContainer : cs.onSecondaryContainer,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: TextStyle(color: cs.onErrorContainer, fontSize: 13))),
        GestureDetector(onTap: onDismiss,
            child: Icon(Icons.close, color: cs.onErrorContainer, size: 18)),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.checklist_rounded, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No todos yet!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            Text('Tap the button below to add your first todo.',
                style: TextStyle(color: Colors.grey.shade400)),
          ]),
        ),
      ],
    );
  }
}