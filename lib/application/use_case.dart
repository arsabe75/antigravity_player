/// Base class for all use cases in the application layer.
///
/// Use cases encapsulate business logic and orchestrate operations
/// between repositories and services.
abstract class UseCase<Output, Params> {
  Future<Output> call(Params params);
}

/// For use cases that don't require parameters.
class NoParams {
  const NoParams();
}
