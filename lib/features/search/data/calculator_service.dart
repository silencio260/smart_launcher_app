import 'package:smart_launcher_app/features/search/domain/entities/search_result.dart';

class CalculatorService {
  static final _pattern = RegExp(r'^[\d\s\+\-\*\/\.\(\)]+$');

  SearchResult? evaluate(String query) {
    if (!_pattern.hasMatch(query.trim())) return null;
    try {
      final result = _eval(query.trim());
      if (result == null) return null;
      final display = result == result.truncateToDouble()
          ? result.toInt().toString()
          : result
              .toStringAsFixed(6)
              .replaceAll(RegExp(r'0+$'), '')
              .replaceAll(RegExp(r'\.$'), '');
      return SearchResult(
        type: SearchResultType.calculator,
        title: '$query = $display',
        score: 1.0,
      );
    } catch (_) {
      return null;
    }
  }

  // Minimal recursive descent evaluator
  double? _eval(String expr) {
    try {
      return _Parser(expr).parse();
    } catch (_) {
      return null;
    }
  }
}

class _Parser {
  final String _input;
  int _pos = 0;

  _Parser(this._input);

  double parse() {
    final result = _expr();
    if (_pos != _input.replaceAll(' ', '').length)
      throw FormatException('leftover');
    return result;
  }

  double _expr() {
    var result = _term();
    while (_pos < _input.length) {
      final c = _input[_pos];
      if (c == '+') {
        _pos++;
        result += _term();
      } else if (c == '-') {
        _pos++;
        result -= _term();
      } else {
        break;
      }
    }
    return result;
  }

  double _term() {
    var result = _factor();
    while (_pos < _input.length) {
      final c = _input[_pos];
      if (c == '*') {
        _pos++;
        result *= _factor();
      } else if (c == '/') {
        _pos++;
        result /= _factor();
      } else {
        break;
      }
    }
    return result;
  }

  double _factor() {
    while (_pos < _input.length && _input[_pos] == ' ') {
      _pos++;
    }
    if (_pos < _input.length && _input[_pos] == '(') {
      _pos++;
      final result = _expr();
      if (_pos < _input.length && _input[_pos] == ')') {
        _pos++;
      }
      return result;
    }
    if (_pos < _input.length && _input[_pos] == '-') {
      _pos++;
      return -_factor();
    }
    final start = _pos;
    while (_pos < _input.length && (_input[_pos].contains(RegExp(r'[\d\.]')))) {
      _pos++;
    }
    return double.parse(_input.substring(start, _pos));
  }
}
