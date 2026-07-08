import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:smart_launcher_app/features/search/domain/entities/search_result.dart';

class SearchState extends Equatable {
  final String query;
  final List<SearchResult> results;
  final bool loading;

  const SearchState({
    this.query = '',
    this.results = const [],
    this.loading = false,
  });

  SearchState copyWith({
    String? query,
    List<SearchResult>? results,
    bool? loading,
  }) =>
      SearchState(
        query: query ?? this.query,
        results: results ?? this.results,
        loading: loading ?? this.loading,
      );

  @override
  List<Object?> get props => [query, results, loading];
}

class SearchCubit extends Cubit<SearchState> {
  SearchCubit() : super(const SearchState());

  void setQuery(String query) {
    emit(state.copyWith(query: query, loading: query.isNotEmpty));
  }

  void setResults(List<SearchResult> results) {
    emit(state.copyWith(results: results, loading: false));
  }

  void clearQuery() {
    emit(const SearchState());
  }
}
