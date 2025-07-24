import 'package:http/http.dart' as http;

void main() async {
  try {
    final response = await http.get(Uri.parse('http://127.0.0.1:8888/employees'));
    print(response.body);
  } catch (e) {
    print('Error: $e');
  }
}