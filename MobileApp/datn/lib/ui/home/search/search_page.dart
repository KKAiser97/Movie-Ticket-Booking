import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:distinct_value_connectable_stream/distinct_value_connectable_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc_pattern/flutter_bloc_pattern.dart';
import 'package:flutter_disposebag/flutter_disposebag.dart';
import 'package:flutter_provider/flutter_provider.dart';
import 'package:intl/intl.dart';
import 'package:loading_indicator/loading_indicator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:stream_loader/stream_loader.dart';

import '../../../domain/model/category.dart';
import '../../../domain/model/movie.dart';
import '../../../domain/repository/city_repository.dart';
import '../../../domain/repository/movie_repository.dart';
import '../../../utils/error.dart';
import '../../../utils/snackbar.dart';
import '../../../utils/streams.dart';
import '../../widgets/empty_widget.dart';
import '../../widgets/error_widget.dart';
import '../view_all/list_item.dart';

class SearchPage extends StatefulWidget {
  static const routeName = '/home/search';

  final String query;

  const SearchPage({Key key, @required this.query}) : super(key: key);

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with DisposeBagMixin {
  final showtimeStartTimeS = StreamController<DateTime>();
  final showtimeEndTimeS = StreamController<DateTime>();
  final minReleasedDateS = StreamController<DateTime>();
  final maxReleasedDateS = StreamController<DateTime>();
  final minDurationS = StreamController<int>();
  final maxDurationS = StreamController<int>();
  final ageTypeS = StreamController<AgeType>();

  DistinctValueStream<DateTime> showtimeStartTime$;
  DistinctValueStream<DateTime> showtimeEndTime$;
  DistinctValueStream<DateTime> minReleasedDate$;
  DistinctValueStream<DateTime> maxReleasedDate$;
  DistinctValueStream<int> minDuration$;
  DistinctValueStream<int> maxDuration$;
  DistinctValueStream<AgeType> ageType$;

  LoaderBloc<BuiltList<Movie>> bloc;
  BuiltList<Category> cats;
  BuiltSet<String> selectedCatIds;

  @override
  void initState() {
    super.initState();

    [
      showtimeStartTimeS,
      showtimeEndTimeS,
      minReleasedDateS,
      maxReleasedDateS,
      minDurationS,
      maxDurationS,
      ageTypeS
    ].disposedBy(bag);

    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 30));
    final end = now.add(const Duration(days: 30));

    showtimeStartTime$ = showtimeStartTimeS.stream
        .shareValueDistinct(start, sync: true)
          ..listenNull().disposedBy(bag);
    showtimeEndTime$ = showtimeEndTimeS.stream
        .shareValueDistinct(end, sync: true)
          ..listenNull().disposedBy(bag);

    minReleasedDate$ = minReleasedDateS.stream
        .shareValueDistinct(start, sync: true)
          ..listenNull().disposedBy(bag);
    maxReleasedDate$ = maxReleasedDateS.stream
        .shareValueDistinct(end, sync: true)
          ..listenNull().disposedBy(bag);

    minDuration$ = minDurationS.stream.shareValueDistinct(30, sync: true)
      ..listenNull().disposedBy(bag);
    maxDuration$ = maxDurationS.stream.shareValueDistinct(60 * 3, sync: true)
      ..listenNull().disposedBy(bag);

    ageType$ = ageTypeS.stream.shareValueDistinct(AgeType.P, sync: true)
      ..listenNull().disposedBy(bag);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    bloc ??= () {
      final movieRepo = Provider.of<MovieRepository>(context);
      final cityRepo = Provider.of<CityRepository>(context);

      final loaderFunction = () => Rx.defer(
            () {
              print('>>>> FETCH ${ageType$.value}');
              print('>>>> FETCH ${minDuration$.value}');
              print('>>>> FETCH ${maxDuration$.value}');
              print('>>>> FETCH ${showtimeStartTime$.value}');
              print('>>>> FETCH ${showtimeEndTime$.value}');
              print('>>>> FETCH ${minReleasedDate$.value}');
              print('>>>> FETCH ${maxReleasedDate$.value}');
              print('>>>> FETCH ${selectedCatIds.length}');

              return movieRepo.search(
                query: widget.query,
                showtimeStartTime: showtimeStartTime$.value,
                showtimeEndTime: showtimeEndTime$.value,
                minReleasedDate: minReleasedDate$.value,
                maxReleasedDate: maxReleasedDate$.value,
                minDuration: minDuration$.value,
                maxDuration: maxDuration$.value,
                ageType: ageType$.value,
                location: cityRepo.selectedCity$.value.location,
                selectedCategoryIds: selectedCatIds,
              );
            },
          );

      final _bloc = LoaderBloc<BuiltList<Movie>>(
        loaderFunction: loaderFunction,
        refresherFunction: loaderFunction,
        initialContent: const <Movie>[].build(),
        enableLogger: true,
      );

      movieRepo.getCategories().listen((event) {
        cats = event;
        selectedCatIds = event.map((c) => c.id).toBuiltSet();
        bloc.fetch();
      }).disposedBy(bag);

      return _bloc;
    }();
  }

  @override
  Widget build(BuildContext context) {
    final movieRepo = Provider.of<MovieRepository>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.query),
        actions: [
          RxStreamBuilder<LoaderState<BuiltList<Movie>>>(
            stream: bloc.state$,
            builder: (context, snapshot) {
              final state = snapshot.data;
              if (state.isLoading) {
                return const SizedBox();
              }

              return IconButton(
                icon: Icon(Icons.filter_alt_outlined),
                onPressed: () => showFilterSheet(movieRepo),
              );
            },
          ),
        ],
      ),
      body: RxStreamBuilder<LoaderState<BuiltList<Movie>>>(
        stream: bloc.state$,
        builder: (context, snapshot) {
          final state = snapshot.data;

          if (state.isLoading) {
            return Center(
              child: SizedBox(
                width: 56,
                height: 56,
                child: LoadingIndicator(
                  color: Theme.of(context).accentColor,
                  indicatorType: Indicator.ballScaleMultiple,
                ),
              ),
            );
          }

          if (state.error != null) {
            return Center(
              child: MyErrorWidget(
                errorText: 'Error: ${getErrorMessage(state.error)}',
                onPressed: bloc.fetch,
              ),
            );
          }

          final items = state.content;

          if (items.isEmpty) {
            return Center(
              child: EmptyWidget(
                message: 'Empty search result',
              ),
            );
          }

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                // margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 2,
                    ),
                  ],
                ),
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Text(
                      '${items.length} movie${items.length > 1 ? 's' : ''}',
                      style: Theme.of(context).textTheme.headline6.copyWith(
                            fontSize: 16,
                            color: const Color(0xff687189),
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: state.isLoading ? null : bloc.refresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: items.length,
                    itemBuilder: (context, index) => ViewAllListItem(
                      item: items[index],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void showFilterSheet(MovieRepository movieRepo) async {
    if (cats == null) {
      await movieRepo.getCategories().forEach((event) => cats = event);
      selectedCatIds = cats.map((c) => c.id).toBuiltSet();
    }
    if (!mounted) {
      return;
    }

    final apply = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => _FilterBottomSheet(this),
    );

    if (identical(apply, true)) {
      print('>>>> ${ageType$.value}');
      print('>>>> ${minDuration$.value}');
      print('>>>> ${maxDuration$.value}');
      print('>>>> ${showtimeStartTime$.value}');
      print('>>>> ${showtimeEndTime$.value}');
      print('>>>> ${minReleasedDate$.value}');
      print('>>>> ${maxReleasedDate$.value}');
      print('>>>> ${selectedCatIds.length}');

      bloc.fetch();
    }
  }
}

class _FilterBottomSheet extends StatefulWidget {
  final _SearchPageState searchPageState;

  _FilterBottomSheet(this.searchPageState);

  @override
  __FilterBottomSheetState createState() => __FilterBottomSheetState();
}

class __FilterBottomSheetState extends State<_FilterBottomSheet> {
  AgeType ageType;
  int minDuration;
  int maxDuration;
  DateTime showtimeStartTime;
  DateTime showtimeEndTime;
  DateTime minReleasedDate;
  DateTime maxReleasedDate;

  List<DropdownMenuItem<int>> durations;
  List<DropdownMenuItem<AgeType>> ageTypes;

  final dateFormat = DateFormat('dd/MM/yy, hh:mm a');

  Set<String> selectedCatIds;
  BuiltList<Category> cats;

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() {
    final state = widget.searchPageState;

    ageType = state.ageType$.value;
    minDuration = state.minDuration$.value;
    maxDuration = state.maxDuration$.value;
    showtimeStartTime = state.showtimeStartTime$.value;
    showtimeEndTime = state.showtimeEndTime$.value;
    minReleasedDate = state.minReleasedDate$.value;
    maxReleasedDate = state.maxReleasedDate$.value;
    selectedCatIds = state.selectedCatIds.toSet();
    cats = widget.searchPageState.cats;
  }

  @override
  void didUpdateWidget(_FilterBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    init();
  }

  @override
  Widget build(BuildContext context) {
    durations ??= [
      for (var d = 30; d <= 12 * 60; d += 10)
        DropdownMenuItem(
          child: Text(d.toString()),
          value: d,
        ),
    ];
    ageTypes ??= [
      for (final t in AgeType.values)
        DropdownMenuItem(
          child: Text(t.toString().split('.')[1]),
          value: t,
        ),
    ];
    const visualDensity = VisualDensity(horizontal: -3, vertical: -3);
    const divider = Divider(height: 0);
    const divider2 = Divider(height: 8);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Search filter',
                        style: Theme.of(context).textTheme.headline6.copyWith(
                              fontSize: 18,
                              color: const Color(0xff687189),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                  Center(
                    child: Row(
                      children: [
                        const Spacer(),
                        const Text('Age type'),
                        const SizedBox(width: 16),
                        DropdownButton<AgeType>(
                          value: ageType,
                          items: ageTypes,
                          onChanged: (val) => setState(() => ageType = val),
                          underline: divider,
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const Text('Duration (mins) from '),
                      DropdownButton<int>(
                        value: minDuration,
                        items: durations,
                        onChanged: (val) {
                          if (val > maxDuration) {
                            return context.showSnackBar(
                                'Must be less than or equal to max duration');
                          }
                          setState(() => minDuration = val);
                        },
                        underline: divider,
                      ),
                      const Text(' to '),
                      DropdownButton<int>(
                        value: maxDuration,
                        items: durations,
                        onChanged: (val) {
                          if (val < minDuration) {
                            return context.showSnackBar(
                                'Must be greater than or equal to min duration');
                          }
                          setState(() => maxDuration = val);
                        },
                        underline: divider,
                      ),
                    ],
                  ),
                  divider2,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const Text('Showtime start from '),
                      FlatButton(
                        onPressed: () async {
                          final newStart =
                              await pickDateTime(showtimeStartTime);
                          if (newStart == null) {
                            return;
                          }
                          if (!newStart.isBefore(showtimeEndTime)) {
                            return context.showSnackBar(
                                'Showtime start time must be before end time');
                          }
                          setState(() => showtimeStartTime = newStart);
                        },
                        child: Text(dateFormat.format(showtimeStartTime)),
                        visualDensity: visualDensity,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const Text(' to '),
                      FlatButton(
                        onPressed: () async {
                          final newEnd = await pickDateTime(showtimeEndTime);
                          if (newEnd == null) {
                            return;
                          }
                          if (!newEnd.isAfter(showtimeStartTime)) {
                            return context.showSnackBar(
                                'Showtime end time must be after start time');
                          }
                          setState(() => showtimeEndTime = newEnd);
                        },
                        child: Text(dateFormat.format(showtimeEndTime)),
                        visualDensity: visualDensity,
                      ),
                    ],
                  ),
                  ////////////////////////
                  divider2,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const Text('Released date from '),
                      FlatButton(
                        onPressed: () async {
                          final newStart = await pickDateTime(minReleasedDate);
                          if (newStart == null) {
                            return;
                          }
                          if (!newStart.isBefore(maxReleasedDate)) {
                            return context.showSnackBar(
                                'Must be before max released date');
                          }
                          setState(() => minReleasedDate = newStart);
                        },
                        child: Text(dateFormat.format(minReleasedDate)),
                        visualDensity: visualDensity,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const Text(' to '),
                      FlatButton(
                        onPressed: () async {
                          final newEnd = await pickDateTime(maxReleasedDate);
                          if (newEnd == null) {
                            return;
                          }
                          if (!newEnd.isAfter(minReleasedDate)) {
                            return context.showSnackBar(
                                'Must be after min released date');
                          }
                          setState(() => maxReleasedDate = newEnd);
                        },
                        child: Text(dateFormat.format(maxReleasedDate)),
                        visualDensity: visualDensity,
                      ),
                    ],
                  ),
                  divider2,
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final cat in cats)
                        FilterChip(
                          selectedColor:
                              Theme.of(context).accentColor.withOpacity(0.3),
                          label: Text(cat.name),
                          labelStyle: ChipTheme.of(context).labelStyle.copyWith(
                                fontSize: 11,
                              ),
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                selectedCatIds.add(cat.id);
                              } else {
                                selectedCatIds.remove(cat.id);
                              }
                            });
                          },
                          selected: selectedCatIds.contains(cat.id),
                        ),
                    ],
                  )
                ],
              ),
            ),
          ),
          Container(
            color: Colors.white,
            child: ButtonTheme(
              height: 38,
              child: Row(
                children: [
                  const SizedBox(width: 32),
                  Expanded(
                    child: FlatButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('Cancel'),
                      color: Theme.of(context).disabledColor,
                      textTheme: ButtonTextTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(38 / 2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: FlatButton(
                      onPressed: () {
                        apply();
                        Navigator.of(context).pop(true);
                      },
                      child: Text('Apply'),
                      color: Theme.of(context).primaryColor,
                      textTheme: ButtonTextTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(38 / 2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void apply() {
    final state = widget.searchPageState;

    state.ageTypeS.add(ageType);

    state.minDurationS.add(minDuration);
    state.maxDurationS.add(maxDuration);

    state.showtimeStartTimeS.add(showtimeStartTime);
    state.showtimeEndTimeS.add(showtimeEndTime);

    state.minReleasedDateS.add(minReleasedDate);
    state.maxReleasedDateS.add(maxReleasedDate);

    state.selectedCatIds = selectedCatIds.build();
  }

  Future<DateTime> pickDateTime(DateTime initialDate) async {
    const sixMonths = Duration(days: 30 * 6);
    final now = DateTime.now();

    final date = await showDatePicker(
      initialDate: initialDate,
      context: context,
      firstDate: now.subtract(sixMonths),
      lastDate: now.add(sixMonths),
    );

    if (date == null) {
      return null;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(date),
    );

    if (time == null) {
      return null;
    }

    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }
}
