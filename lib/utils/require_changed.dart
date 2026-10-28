/// Throws unless an update/delete that selected its rows back touched one.
///
/// When RLS refuses a write, or the id doesn't match, PostgREST changes
/// zero rows and returns no error. Without this check the screen said
/// "Deleted" or "Saved" for something that never changed. Pair it with
/// `.select('id')` on the write.
void requireChanged(Object? rows, String what) {
  if (rows is! List || rows.isEmpty) {
    throw StateError('$what was not changed');
  }
}
