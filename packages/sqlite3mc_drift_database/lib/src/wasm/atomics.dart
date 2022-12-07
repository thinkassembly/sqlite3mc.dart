@JS()
library workarounds;

import 'dart:typed_data';
import 'package:js/js.dart';
import 'dart:js_util' as js_util;

@JS('Int32Array')
external Object? get int32ArrayConstructor;

Int32List createSharedArray(Object sab) {
  return js_util.callConstructor<Int32List>(int32ArrayConstructor!, [sab]);
}



@JS()
abstract class Atomics {
  @JS('add')
  external static int add(List<int> typedArray, int index, int value);

  @JS('and')
  external static int and(List<int> typedArray, int index, int value);

  @JS('compareExchange')
  external static int compareExchange(
      List<int> typedArray, int index, int expectedValue, int replacementValue);

  @JS('exchange')
  external static int exchange(List<int> typedArray, int index, int value);

  @JS('isLockFree')
  external static bool isLockFree(int size);

  @JS('load')
  external static int load(List<int> typedArray, int index);

  @JS('notify')
  external static int notify(List<int> typedArray, int index, [int count]);

  @JS('or')
  external static int or(List<int> typedArray, int index, int value);

  @JS('store')
  external static int store(List<int> typedArray, int index, int value);

  @JS('sub')
  external static int sub(List<int> typedArray, int index, int value);

  @JS('wait')
  external static String wait(List<int> typedArray, int index, int value,
      [num timeout]);

  @JS('xor')
  external static int xor(List<int> typedArray, int index, int value);
}



