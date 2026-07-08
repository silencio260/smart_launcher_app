import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/features/search/presentation/bloc/search_cubit.dart';

class AllAppsSearchBar extends StatefulWidget {
  const AllAppsSearchBar({super.key});

  @override
  State<AllAppsSearchBar> createState() => _AllAppsSearchBarState();
}

class _AllAppsSearchBarState extends State<AllAppsSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search apps…',
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          suffixIcon: BlocBuilder<SearchCubit, SearchState>(
            builder: (context, state) => state.query.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white54),
                    onPressed: () {
                      _controller.clear();
                      context.read<SearchCubit>().clearQuery();
                    },
                  ),
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (q) => context.read<SearchCubit>().setQuery(q),
      ),
    );
  }
}
