import 'remote/response/category_response.dart';
import 'remote/response/movie_response.dart';
import 'remote/response/person_response.dart';
import '../domain/model/age_type.dart';
import '../domain/model/category.dart';
import '../domain/model/movie.dart';
import '../domain/model/person.dart';

import '../domain/model/location.dart';
import '../domain/model/user.dart';
import 'local/user_local.dart';
import 'remote/response/user_response.dart';

UserLocal userResponseToUserLocal(UserResponse response) {
  return UserLocal(
      uid: response.uid,
      email: response.email,
      phone_number: response.phone_number,
      full_name: response.full_name,
      gender: response.gender,
      avatar: response.avatar,
      address: response.address,
      birthday: response.birthday,
      location: response.location == null
          ? null
          : LocationLocal(
              latitude: response.location.latitude,
              longitude: response.location.longitude,
            ),
      is_completed: response.is_completed,
      is_active: response.is_active ?? true,
      role: response.role);
}

User userLocalToUserDomain(UserLocal local) {
  return User(
      uid: local.uid,
      email: local.email,
      phoneNumber: local.phone_number,
      fullName: local.full_name,
      gender: stringToGender(local.gender),
      avatar: local.avatar,
      address: local.address,
      birthday: local.birthday,
      location: local.location == null
          ? null
          : Location(
              latitude: local.location.latitude,
              longitude: local.location.longitude,
            ),
      isCompleted: local.is_completed,
      isActive: local.is_active ?? true,
      role: local.role.parseToRole());
}

Gender stringToGender(String s) {
  if (s == 'MALE') {
    return Gender.MALE;
  }
  if (s == 'FEMALE') {
    return Gender.FEMALE;
  }
  throw Exception("Cannot convert string '$s' to gender");
}

extension RoleResponse on String {
  Role parseToRole() {
    return this == 'ADMIN'
        ? Role.ADMIN
        : this == 'STAFF'
            ? Role.STAFF
            : Role.USER;
  }
}

User userResponseToUserDomain(UserResponse response) {
  return User(
    uid: response.uid,
    email: response.email,
    phoneNumber: response.phone_number,
    fullName: response.full_name,
    gender: stringToGender(response.gender),
    avatar: response.avatar,
    address: response.address,
    birthday: response.birthday,
    location: response.location == null
        ? null
        : Location(
            latitude: response.location.latitude,
            longitude: response.location.longitude,
          ),
    isCompleted: response.is_completed,
    isActive: response.is_active ?? true,
    role: response.role.parseToRole(),
  );
}

Movie movieRemoteToDomain(MovieResponse response) {
  return Movie(
    id: response.id,
    isActive: response.isActive,
    title: response.title,
    trailerVideoUrl: response.trailerVideoUrl,
    posterUrl: response.posterUrl,
    overview: response.overview,
    releasedDate: response.releasedDate,
    duration: response.duration,
    originalLanguage: response.originalLanguage,
    createdAt: response.createdAt,
    updatedAt: response.updatedAt,
    ageType: response.ageType.ageType(),
    actors: response.actors.map((e) => personResponseToPerson(e)).toList(),
    directors:
        response.directors.map((e) => personResponseToPerson(e)).toList(),
    categories:
        response.categories.map((e) => categoryResponseToCategory(e)).toList(),
    rateStar: response.rateStar,
    totalFavorite: response.totalFavorite,
    totalRate: response.totalRate,
  );
}

Category categoryResponseToCategory(CategoryResponse response) {
  return Category(
    id: response.id,
    name: response.name,
    createdAt: response.createdAt,
    updatedAt: response.updatedAt,
    is_active: true,
  );
}

Person personResponseToPerson(PersonResponse response) {
  return Person(
    is_active: response.isActive ?? true,
    id: response.id,
    avatar: response.avatar,
    full_name: response.fullName,
    createdAt: response.createdAt,
    updatedAt: response.updatedAt,
  );
}

extension AgeTypeExtension on String {
  AgeType ageType() => this == 'P'
      ? AgeType.P
      : this == 'C13'
          ? AgeType.C13
          : this == 'C16'
              ? AgeType.C16
              : AgeType.C18;
}
