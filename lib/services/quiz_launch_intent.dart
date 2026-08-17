import '../models/quiz_round.dart';

/// One-shot handoff for opening the Quiz Arena *at a mode* rather than at
/// the lobby.
///
/// Mirrors [LibraryLaunchIntent], which solves the same problem for the
/// Library: the `/quiz` route carries nothing but itself, and it is fronted
/// by `QuizBootScreen` — a warming gate that crossfades into the lobby in
/// place — so threading an argument through go_router would mean reshaping
/// the route and the gate for one caller.
///
/// ## Why the lobby still runs the round
///
/// The founder's Home decision (17 Aug) was that the Daily Challenge card
/// taps "straight into the questions, skipping the lobby". That is what the
/// member sees — but the round is still STARTED by the lobby, deliberately.
/// `QuizLobbyScreen` owns round → results → play-again, the challenge
/// submit/send, the streak write and the pending-opponent claim. A second
/// copy of that flow on Home would drift from it, and the bugs would be the
/// quiet kind: a streak that does not advance, a challenge that is never
/// sent.
///
/// So Home sets the intent and pushes `/quiz`; the lobby consumes it on
/// mount and plays immediately.
class QuizLaunchIntent {
  QuizLaunchIntent._();

  /// Mode to start the moment the lobby is ready, if any.
  static QuizMode? mode;

  /// Reads and clears the pending mode.
  ///
  /// Clearing on read is what stops the round replaying every time the
  /// member comes back to the lobby from the results screen.
  static QuizMode? take() {
    final m = mode;
    mode = null;
    return m;
  }

  static void clear() => mode = null;
}
