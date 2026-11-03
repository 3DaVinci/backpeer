import 'package:core/src/errors.dart';
import 'package:meta/meta.dart';

/// Версия продукта `X.Y.Z` (SemVer без пререлизного суффикса; docs/spec/
/// updates.md, раздел 7). Одна на все пакеты (режим `fixed` в `melos.yaml`).
@immutable
final class ProductVersion implements Comparable<ProductVersion> {
  const new(this.major, this.minor, this.patch);

  /// Разбирает `X.Y.Z`; иначе [DataFormatException] (`object`: `version`).
  factory parse(String text) {
    final parts = text.split('.');
    if (parts.length != 3) {
      throw DataFormatException(
        object: 'version',
        problem: FormatProblem.invalidField,
        detail: text,
      );
    }
    final nums = <int>[];
    for (final part in parts) {
      if (part.isEmpty || !RegExp(r'^\d+$').hasMatch(part)) {
        throw DataFormatException(
          object: 'version',
          problem: FormatProblem.invalidField,
          detail: text,
        );
      }
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 0xFFFF) {
        throw DataFormatException(
          object: 'version',
          problem: FormatProblem.invalidField,
          detail: text,
        );
      }
      nums.add(value);
    }
    return ProductVersion(nums[0], nums[1], nums[2]);
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(ProductVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(ProductVersion other) => compareTo(other) > 0;

  bool operator <(ProductVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is ProductVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
