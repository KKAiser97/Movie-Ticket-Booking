import 'package:built_collection/built_collection.dart';
import 'package:meta/meta.dart';

import '../model/location.dart';
import '../model/movie.dart';
import '../model/theatre_and_show_times.dart';

abstract class MovieRepository {
  Stream<BuiltList<Movie>> getNowPlayingMovies({
    Location location,
    @required int page,
    @required int perPage,
  });

  Stream<BuiltList<Movie>> getComingSoonMovies({
    @required int page,
    @required int perPage,
  });

  Stream<BuiltMap<DateTime, BuiltList<TheatreAndShowTimes>>> getShowTimes({
    @required String movieId,
    Location location,
  });
}