package tink.core;

using tink.CoreApi;

#if js
import js.lib.Error as JsError;
import js.lib.Promise as JsPromise;
#end

@:forward(handle, eager)
abstract Future<T>(FutureObject<T>) from FutureObject<T> to FutureObject<T> {

  public static var NULL:Future<Dynamic> = Future.sync(null);
  public static var NOISE:Future<Noise> = Future.sync(Noise);
  public static var NEVER:Future<Dynamic> = (NeverFuture.inst:FutureObject<Dynamic>);

  public inline function new(f:Callback<T>->CallbackLink)
    this = new SuspendableFuture(f);

  /**
   *  Creates a future that contains the first result from `this` or `other`
   */
  public function first(that:Future<T>):Future<T>
    return new SuspendableFuture<T>(
      yield -> this.handle(yield) & that.handle(yield)
    );

  /**
   *  Creates a new future by applying a transform function to the result.
   *  Different from `flatMap`, the transform function of `map` returns a sync value
   */
  public inline function map<A>(f:T->A):Future<A>
    return this.map(f);

  /**
   *  Creates a new future by applying a transform function to the result.
   *  Different from `map`, the transform function of `flatMap` returns a `Future`
   */
  public inline function flatMap<A>(next:T->Future<A>):Future<A>
    return this.flatMap(next);

  /**
   *  Like `map` and `flatMap` but with a polymorphic transformer and return a `Promise`
   *  @see `Next`
   */
  public function next<R>(n:Next<T, R>):Promise<R>
    return this.flatMap(v -> n(v));

  /**
   *  Merges two futures into one by applying the merger function on the two future values
   */
  public function merge<A, R>(that:Future<A>, combine:T->A->R):Future<R>
    return
      new SuspendableFuture<R>(yield -> {
        var aDone = false, bDone = false;
        var aRes = null, bRes = null;
        function check() if (aDone && bDone) yield(combine(aRes, bRes));
        return
          this.handle(function (a) { aRes = a; aDone = true; check(); }).join(
            that.handle(function (b) { bRes = b; bDone = true; check(); })
          );
      });

  /**
   *  Flattens `Future<Future<A>>` into `Future<A>`
   */
  static public function flatten<A>(f:Future<Future<A>>):Future<A>
    return new SuspendableFuture<A>(yield -> {
      var inner = null;
      var outer = f.handle(function (second) {
        inner = second.handle(yield);
      });
      return outer.join(function () inner.cancel());
    });

  #if js
  /**
   *  Casts a js Promise into a Surprise
   */
  @:from static public function ofJsPromise<A>(promise:JsPromise<A>):Surprise<A, Error>
    return Future.async(
      yield -> {
        promise
          .then(
            a -> yield(Success(a)),
            e -> yield(Failure(Error.ofJsError(e)))
          );
        null;
      }
    ).eager();
  #end

  @:from static inline function ofAny<T>(v:T):Future<T>
    return Future.sync(v);

  /**
   *  Casts a Surprise into a Promise
   */
  static inline public function asPromise<T>(s:Surprise<T, Error>):Promise<T>
    return s;

  /**
   *  Merges multiple futures into Future<Array<A>>
   */
  static public function ofMany<A>(futures:Array<Future<A>>) {
    var ret = sync([]);
    for (f in futures)
      ret = ret.flatMap(
        function (results:Array<A>)
          return f.map(
            function (result)
              return results.concat([result])
          )
      );
    return ret;
  }

  //TODO: use this as `sync` for 2.0
  @:noUsing static inline public function lazy<A>(l:Lazy<A>):Future<A>
    return new SyncFuture(l);

  /**
   *  Creates a sync future.
   *  Example: `var i = Future.sync(1); // Future<Int>`
   */
  @:noUsing static inline public function sync<A>(v:A):Future<A>
    return new SyncFuture(v);

  /**
   *  Creates an async future
   *  Example: `var i = Future.async(function(cb) cb(1)); // Future<Int>`
   */
  #if python @:native('make') #end
  @:noUsing static public function async<A>(f:(A->Void)->Void):Future<A>
    return new SuspendableFuture(yield -> {
      f(yield);
      null;
    });

  /**
   *  Same as `first`
   */
  @:noCompletion @:op(a || b) static public function or<A>(a:Future<A>, b:Future<A>):Future<A>
    return a.first(b);

  /**
   *  Same as `first`, but use `Either` to handle the two different types
   */
  @:noCompletion @:op(a || b) static public function either<A, B>(a:Future<A>, b:Future<B>):Future<Either<A, B>>
    return a.map(Either.Left).first(b.map(Either.Right));

  /**
   *  Uses `Pair` to merge two futures
   */
  @:noCompletion @:op(a && b) static public function and<A, B>(a:Future<A>, b:Future<B>):Future<Pair<A, B>>
    return a.merge(b, function (a, b) return new Pair(a, b));

  @:noCompletion @:op(a >> b) static public function _tryFailingFlatMap<D, F, R>(f:Surprise<D, F>, map:D->Surprise<R, F>)
    return f.flatMap(o -> switch o {
      case Success(d): map(d);
      case Failure(f): Future.sync(Failure(f));
    });

  @:noCompletion @:op(a >> b) static public function _tryFlatMap<D, F, R>(f:Surprise<D, F>, map:D->Future<R>):Surprise<R, F>
    return f.flatMap(o -> switch o {
      case Success(d): map(d).map(Success);
      case Failure(f): Future.sync(Failure(f));
    });

  @:noCompletion @:op(a >> b) static public function _tryFailingMap<D, F, R>(f:Surprise<D, F>, map:D->Outcome<R, F>)
    return f.map(o -> o.flatMap(map));

  @:noCompletion @:op(a >> b) static public function _tryMap<D, F, R>(f:Surprise<D, F>, map:D->R)
    return f.map(o -> o.map(map));

  @:noCompletion @:op(a >> b) static public function _flatMap<T, R>(f:Future<T>, map:T->Future<R>)
    return f.flatMap(map);

  @:noCompletion @:op(a >> b) static public function _map<T, R>(f:Future<T>, map:T->R)
    return f.map(map);

  /**
   *  Creates a new `FutureTrigger`
   */
  @:noUsing static public inline function trigger<A>(?onChangeCount):FutureTrigger<A>
    return new FutureTrigger(onChangeCount);

  @:noUsing static public function delay<T>(ms:Int, value:Lazy<T>):Future<T>
    return Future.async(function(cb) haxe.Timer.delay(function() cb(value.get()), ms));

}

private interface FutureObject<T> {

  function map<R>(f:T->R):Future<R>;
  function flatMap<R>(f:T->Future<R>):Future<R>;
  /**
   *  Registers a callback to handle the future result.
   *  If the result is already available, the callback will be invoked immediately.
   *  @return A `CallbackLink` instance that can be used to cancel the callback, no effect if the callback is already invoked
   */
  function handle(callback:Callback<T>):CallbackLink;
  /**
   *  Makes this future eager.
   *  Futures are lazy by default, i.e. it does not try to fetch the result until someone `handle` it
   */
  function eager():Future<T>;
}

private class NeverFuture<T> implements FutureObject<T> {
  public static var inst(default, null):NeverFuture<Dynamic> = new NeverFuture();
  function new() {}
  public function map<R>(f:T->R):Future<R> return cast inst;
  public function flatMap<R>(f:T->Future<R>):Future<R> return cast inst;
  public function handle(callback:Callback<T>):CallbackLink return null;
  public function eager():Future<T> return cast inst;
}

private class SyncFuture<T> implements FutureObject<T> {

  var value:Lazy<T>;

  public inline function new(value)
    this.value = value;

  public inline function map<R>(f:T->R):Future<R>
    return new SyncFuture(value.map(f));

  public inline function flatMap<R>(f:T->Future<R>):Future<R>
    return new SuspendableFuture(function (yield) return f(value.get()).handle(yield));

  public function handle(cb:Callback<T>):CallbackLink {
    cb.invoke(value);
    return null;
  }

  public function eager()
    return this;
}

class FutureTrigger<T> implements FutureObject<T> {
  var result:T;
  var list:CallbackList<T>;

  public function new(?onChangeCount)
    this.list = new CallbackList(onChangeCount);

  public function handle(callback:Callback<T>):CallbackLink
    return switch list {
      case null:
        callback.invoke(result);
        null;
      case v:
        v.add(callback);
    }

  public function map<R>(f:T->R):Future<R>
    return new SuspendableFuture(function (yield) {
      return this.handle(function (res) yield(f(res)));
    });

  public function flatMap<R>(f:T->Future<R>):Future<R>
    return Future.flatten(map(f));

  public function eager():Future<T>
    return this;

  public inline function asFuture():Future<T>
    return this;

  /**
   *  Triggers a value for this future
   */
  public function trigger(result:T):Bool
    return
      if (list == null) false;
      else {
        var list = this.list;
        this.list = null;
        this.result = result;
        list.invoke(result, true);
        true;
      }
}

typedef Surprise<D, F> = Future<Outcome<D, F>>;

#if js
class JsPromiseTools {
  static inline public function toSurprise<A>(promise:JsPromise<A>):Surprise<A, Error>
    return Future.ofJsPromise(promise);
  static inline public function toPromise<A>(promise:JsPromise<A>):Promise<A>
    return Future.ofJsPromise(promise);
}
#end

private class SuspendableFuture<T> extends FutureTrigger<T> {//TODO: this has quite a bit of duplication with FutureTrigger
  var suspended:Bool = true;
  var link:CallbackLink;
  var lazy:Bool = true;
  var wakeup:(T->Void)->CallbackLink;

  public function new(wakeup) {
    super(
      count -> if (count == 0 && lazy && list != null) {
        suspended = true;
        link.cancel();
        link = null;
      }
    );
    this.wakeup = wakeup;
  }

  override function trigger(value)
    return
      if (super.trigger(value)) {
        link.dissolve();
        link = null;//consider disolving
        wakeup = null;
        true;
      }
      else false;

  function arm()
    if (suspended) {
      suspended = false;
      link = wakeup(trigger);
    }

  override function handle(callback)
    return switch super.handle(callback) {
      case null: null;
      case ret:
        inline arm();
        ret;
    }

  override public function eager():Future<T> {
    if (lazy) {
      lazy = false;
      arm();
      wakeup = null;
    }
    return this;
  }

}