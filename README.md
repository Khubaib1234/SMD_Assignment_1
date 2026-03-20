# 📱 Todo List App (Flutter)

A Flutter-based Todo List application that integrates with a backend using REST APIs and JSON.

---

## 👨‍💻 Group 3 Members

* 22K-4376 Khubaib Ahmed Jamil
* 22K-4367 Ayan Hasan
* 22K-4482 Muhammad Ahmed

---

## 🚀 Features

* 📥 Fetch Todos from Server (with pagination)
* 🔄 Lazy Loading (infinite scroll)
* ➕ Add New Todo (title + description)
* ✅ Mark Todo as Done / Undo
* 🔃 Pull to Refresh
* ⚠️ Error Handling (API + UI feedback)
* 🎨 Modern UI (Material 3, responsive design)

---

## 🛠️ Tech Stack

* Flutter
* Dart
* HTTP package (only external dependency)
* REST APIs (JSON format)

---

## 🌐 API Integration

Base URL:

```
https://apimocker.com/todos
```

### Endpoints Used

| Method | Endpoint     | Description              |
| ------ | ------------ | ------------------------ |
| GET    | `/todos`     | Fetch paginated todos    |
| POST   | `/todos`     | Create new todo          |
| PATCH  | `/todos/:id` | Update completion status |

---

## 📦 Project Structure

```
lib/
│── main.dart              # Main application + UI + API logic
│── todo_service.dart      # Basic Todo model
```

---

## ⚙️ How to Run

1. Clone the repository:

```
git clone https://github.com/Khubaib1234/SMD_Assignment_1.git
cd SMD_Assignment_1
```

2. Install dependencies:

```
flutter pub get
```

3. Run the app:

```
flutter run
```

---

## ⚠️ Notes / Limitations

* API has a daily write limit (100 requests/day)
* CORS handled via proxy for web
* Some responses depend on mock API behavior

---

## Screenshots

### To-Do Screen

![To-Do List](images/todo screen.png)

### To-Do Screen

![Add Task](images/add-task-screen.png)

