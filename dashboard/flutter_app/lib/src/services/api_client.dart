import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;
  final http.Client _client;

  ApiClient({this.baseUrl = 'http://localhost:8888'})
      : _client = http.Client();

  Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? params}) async {
    final uri = Uri.parse('$baseUrl$path')
        .replace(queryParameters: params?.isNotEmpty == true ? params : null);
    final response = await _client.get(uri, headers: _headers);
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic>? body}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> put(String path,
      {Map<String, dynamic>? body}) async {
    final response = await _client.put(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> delete(String path,
      {Map<String, String>? params}) async {
    final uri = Uri.parse('$baseUrl$path')
        .replace(queryParameters: params?.isNotEmpty == true ? params : null);
    final response = await _client.delete(uri, headers: _headers);
    return _handleResponse(response);
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {'success': true};
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    try {
      final body = jsonDecode(response.body);
      return {'error': body['detail'] ?? response.reasonPhrase};
    } catch (_) {
      return {'error': response.reasonPhrase ?? 'Request failed'};
    }
  }
}
