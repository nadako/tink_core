package tink.core;

import tink.core.Callback;
import tink.core.Noise;

@:forward
abstract Signal<T>(SignalObject<T>) from SignalObject<T> to SignalObject<T> {
  
  public inline function new(f:Callback<T>->CallbackLink) 
    this = new Suspendable(f);
  
  /**
   *  Creates a new signal by applying a transform function to the result.
   *  Different from `flatMap`, the transform function of `map` returns a sync value
   */
  public function map<A>(f:T->A):Signal<A> 
    return new Signal(function (cb) return this.handle(function (result) cb.invoke(f(result))));
  /**
   *  Creates a new signal by applying a transform function to the result.
   *  Different from `map`, the transform function of `flatMap` returns a `Future`
   */
  public function flatMap<A>(f:T->Future<A>):Signal<A> 
    return new Signal(function (cb) return this.handle(function (result) f(result).handle(cb)));
  
  /**
   *  Creates a new signal whose values will only be emitted when the filter function evalutes to `true`
   */
  public function filter(f:T->Bool):Signal<T> 
    return new Signal(function (cb) return this.handle(function (result) if (f(result)) cb.invoke(result)));

  public function select<R>(selector:T->Option<R>):Signal<R> 
    return new Signal(function (cb) return this.handle(function (result) switch selector(result) {
      case Some(v): cb.invoke(v);
      case None:
    }));
  
  /**
   *  Creates a new signal by joining `this` and `other`,
   *  the new signal will be triggered whenever either of the two triggers
   */
  public function join(other:Signal<T>):Signal<T> 
    return new Signal(
      function (cb:Callback<T>):CallbackLink 
        return this.handle(cb) & other.handle(cb)
    );
  
  /**
   *  Gets the next emitted value as a Future
   */
  public function nextTime(?condition:T->Bool):Future<T> {
    var ret = Future.trigger();
    var link:CallbackLink = null,
        immediate = false;
        
    link = this.handle(function (v) if (condition == null || condition(v)) {
      ret.trigger(v);
      if (link == null) immediate = true;
      else link.cancel();
    });
    
    if (immediate) 
      link.cancel();
    
    return ret.asFuture();
  }

  public function until<X>(end:Future<X>):Signal<T> {
    var ret = new Suspendable(
      function (yield) return this.handle(yield)
    );
    end.handle(ret.kill);
    return ret;
  }

  @:deprecated("use nextTime instead")
  public inline function next(?condition:T->Bool):Future<T>
    return nextTime(condition);
  
  /**
   *  Transforms this signal and makes it emit `Noise`
   */
  public function noise():Signal<Noise>
    return map(function (_) return Noise);
  
  static public function generate<T>(generator:(T->Void)->Void):Signal<T> {
    var ret = trigger();
    generator(ret.trigger);
    return ret;
  }

  /**
   *  Creates a new `SignalTrigger`
   */
  static public function trigger<T>():SignalTrigger<T>
    return new SignalTrigger();

  static public inline function create<T>(create:(T->Void)->CallbackLink):Signal<T>
    return new Suspendable<T>(create);
    
  /**
   *  Creates a `Signal` from classic signals that has the semantics of `addListener` and `removeListener`
   *  Example: `var signal = Signal.ofClassical(emitter.addListener.bind(eventType), emitter.removeListener.bind(eventType));`
   */
  static public function ofClassical<A>(add:(A->Void)->Void, remove:(A->Void)->Void) 
    return Signal.create(function (cb:Callback<A>) {
      var f = function (a) cb.invoke(a);
      add(f);
      return remove.bind(f);
    });
}

private class Suspendable<T> implements SignalObject<T> {
  var trigger:SignalTrigger<T> = new SignalTrigger();
  var activate:(T->Void)->CallbackLink;
  var link:CallbackLink;

  public function new(activate) {
    this.activate = activate;
  }

  public var killed(default, null):Bool = false;

  public function kill()
    if (!killed) {
      killed = true;
      trigger = null;
    }  

  public function handle(cb) {
    if (trigger.getLength() == 0) 
      this.link = activate(trigger.trigger);
    
    return 
      trigger.handle(cb) 
      & function ()
        if (trigger.getLength() == 0) {
          link.cancel();
          link = null;
        }
  }
}

class SignalTrigger<T> implements SignalObject<T> {
  var handlers = new CallbackList<T>();
  public inline function new() {} 
    
  /**
   *  Emits a value for this signal
   */
  public inline function trigger(event:T)
    handlers.invoke(event);
    
  /**
   *  Gets the number of handlers registered
   */
  public inline function getLength()
    return handlers.length;

  public inline function handle(cb) 
    return handlers.add(cb);

  /**
   *  Clear all handlers
   */
  public inline function clear()
    handlers.clear();
    
  @:to public inline function asSignal():Signal<T> 
    return this;
}

interface SignalObject<T> {
  /**
   *  Registers a callback to be invoked every time the signal is triggered
   *  @return A `CallbackLink` instance that can be used to unregister the callback
   */
  function handle(handler:Callback<T>):CallbackLink;
}