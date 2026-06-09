(() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __esm = (fn, res) => function __init() {
    return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
  };
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));

  // node_modules/mathjs/lib/utils/polyfills.js
  var require_polyfills = __commonJS({
    "node_modules/mathjs/lib/utils/polyfills.js"() {
      "use strict";
      Number.isFinite = Number.isFinite || function(value) {
        return typeof value === "number" && isFinite(value);
      };
      Number.isNaN = Number.isNaN || function(value) {
        return value !== value;
      };
    }
  });

  // node_modules/mathjs/lib/utils/bignumber/isBigNumber.js
  var require_isBigNumber = __commonJS({
    "node_modules/mathjs/lib/utils/bignumber/isBigNumber.js"(exports, module) {
      "use strict";
      module.exports = function isBigNumber(x) {
        return x && x.constructor.prototype.isBigNumber || false;
      };
    }
  });

  // node_modules/mathjs/lib/utils/object.js
  var require_object = __commonJS({
    "node_modules/mathjs/lib/utils/object.js"(exports) {
      "use strict";
      function _typeof(obj) {
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      var isBigNumber = require_isBigNumber();
      exports.clone = function clone(x) {
        var type = _typeof(x);
        if (type === "number" || type === "string" || type === "boolean" || x === null || x === void 0) {
          return x;
        }
        if (typeof x.clone === "function") {
          return x.clone();
        }
        if (Array.isArray(x)) {
          return x.map(function(value) {
            return clone(value);
          });
        }
        if (x instanceof Date) return new Date(x.valueOf());
        if (isBigNumber(x)) return x;
        if (x instanceof RegExp) throw new TypeError("Cannot clone " + x);
        return exports.map(x, clone);
      };
      exports.map = function(object, callback) {
        var clone = {};
        for (var key in object) {
          if (exports.hasOwnProperty(object, key)) {
            clone[key] = callback(object[key]);
          }
        }
        return clone;
      };
      exports.extend = function(a, b) {
        for (var prop in b) {
          if (exports.hasOwnProperty(b, prop)) {
            a[prop] = b[prop];
          }
        }
        return a;
      };
      exports.deepExtend = function deepExtend(a, b) {
        if (Array.isArray(b)) {
          throw new TypeError("Arrays are not supported by deepExtend");
        }
        for (var prop in b) {
          if (exports.hasOwnProperty(b, prop)) {
            if (b[prop] && b[prop].constructor === Object) {
              if (a[prop] === void 0) {
                a[prop] = {};
              }
              if (a[prop].constructor === Object) {
                deepExtend(a[prop], b[prop]);
              } else {
                a[prop] = b[prop];
              }
            } else if (Array.isArray(b[prop])) {
              throw new TypeError("Arrays are not supported by deepExtend");
            } else {
              a[prop] = b[prop];
            }
          }
        }
        return a;
      };
      exports.deepEqual = function deepEqual(a, b) {
        var prop, i, len;
        if (Array.isArray(a)) {
          if (!Array.isArray(b)) {
            return false;
          }
          if (a.length !== b.length) {
            return false;
          }
          for (i = 0, len = a.length; i < len; i++) {
            if (!exports.deepEqual(a[i], b[i])) {
              return false;
            }
          }
          return true;
        } else if (a instanceof Object) {
          if (Array.isArray(b) || !(b instanceof Object)) {
            return false;
          }
          for (prop in a) {
            if (!exports.deepEqual(a[prop], b[prop])) {
              return false;
            }
          }
          for (prop in b) {
            if (!exports.deepEqual(a[prop], b[prop])) {
              return false;
            }
          }
          return true;
        } else {
          return a === b;
        }
      };
      exports.canDefineProperty = function() {
        try {
          if (Object.defineProperty) {
            Object.defineProperty({}, "x", {
              get: function get() {
              }
            });
            return true;
          }
        } catch (e) {
        }
        return false;
      };
      exports.lazy = function(object, prop, fn) {
        if (exports.canDefineProperty()) {
          var _uninitialized = true;
          var _value;
          Object.defineProperty(object, prop, {
            get: function get() {
              if (_uninitialized) {
                _value = fn();
                _uninitialized = false;
              }
              return _value;
            },
            set: function set(value) {
              _value = value;
              _uninitialized = false;
            },
            configurable: true,
            enumerable: true
          });
        } else {
          object[prop] = fn();
        }
      };
      exports.traverse = function(object, path) {
        var obj = object;
        if (path) {
          var names = path.split(".");
          for (var i = 0; i < names.length; i++) {
            var name = names[i];
            if (!(name in obj)) {
              obj[name] = {};
            }
            obj = obj[name];
          }
        }
        return obj;
      };
      exports.hasOwnProperty = function(object, property) {
        return object && Object.hasOwnProperty.call(object, property);
      };
      exports.isFactory = function(object) {
        return object && typeof object.factory === "function";
      };
    }
  });

  // node_modules/typed-function/typed-function.js
  var require_typed_function = __commonJS({
    "node_modules/typed-function/typed-function.js"(exports, module) {
      "use strict";
      (function(root, factory) {
        if (typeof define === "function" && define.amd) {
          define([], factory);
        } else if (typeof exports === "object") {
          module.exports = factory();
        } else {
          root.typed = factory();
        }
      })(exports, function() {
        function ok() {
          return true;
        }
        function notOk() {
          return false;
        }
        function undef() {
          return void 0;
        }
        function create() {
          var _types = [
            { name: "number", test: function(x) {
              return typeof x === "number";
            } },
            { name: "string", test: function(x) {
              return typeof x === "string";
            } },
            { name: "boolean", test: function(x) {
              return typeof x === "boolean";
            } },
            { name: "Function", test: function(x) {
              return typeof x === "function";
            } },
            { name: "Array", test: Array.isArray },
            { name: "Date", test: function(x) {
              return x instanceof Date;
            } },
            { name: "RegExp", test: function(x) {
              return x instanceof RegExp;
            } },
            { name: "Object", test: function(x) {
              return typeof x === "object" && x.constructor === Object;
            } },
            { name: "null", test: function(x) {
              return x === null;
            } },
            { name: "undefined", test: function(x) {
              return x === void 0;
            } }
          ];
          var anyType = {
            name: "any",
            test: ok
          };
          var _ignore = [];
          var _conversions = [];
          var typed = {
            types: _types,
            conversions: _conversions,
            ignore: _ignore
          };
          function findTypeByName(typeName) {
            var entry = findInArray(typed.types, function(entry2) {
              return entry2.name === typeName;
            });
            if (entry) {
              return entry;
            }
            if (typeName === "any") {
              return anyType;
            }
            var hint = findInArray(typed.types, function(entry2) {
              return entry2.name.toLowerCase() === typeName.toLowerCase();
            });
            throw new TypeError('Unknown type "' + typeName + '"' + (hint ? '. Did you mean "' + hint.name + '"?' : ""));
          }
          function findTypeIndex(type) {
            if (type === anyType) {
              return 999;
            }
            return typed.types.indexOf(type);
          }
          function findTypeName(value) {
            var entry = findInArray(typed.types, function(entry2) {
              return entry2.test(value);
            });
            if (entry) {
              return entry.name;
            }
            throw new TypeError("Value has unknown type. Value: " + value);
          }
          function find(fn, signature) {
            if (!fn.signatures) {
              throw new TypeError("Function is no typed-function");
            }
            var arr;
            if (typeof signature === "string") {
              arr = signature.split(",");
              for (var i = 0; i < arr.length; i++) {
                arr[i] = arr[i].trim();
              }
            } else if (Array.isArray(signature)) {
              arr = signature;
            } else {
              throw new TypeError("String array or a comma separated string expected");
            }
            var str = arr.join(",");
            var match = fn.signatures[str];
            if (match) {
              return match;
            }
            throw new TypeError("Signature not found (signature: " + (fn.name || "unnamed") + "(" + arr.join(", ") + "))");
          }
          function convert(value, type) {
            var from = findTypeName(value);
            if (type === from) {
              return value;
            }
            for (var i = 0; i < typed.conversions.length; i++) {
              var conversion = typed.conversions[i];
              if (conversion.from === from && conversion.to === type) {
                return conversion.convert(value);
              }
            }
            throw new Error("Cannot convert from " + from + " to " + type);
          }
          function stringifyParams(params) {
            return params.map(function(param) {
              var typeNames = param.types.map(getTypeName);
              return (param.restParam ? "..." : "") + typeNames.join("|");
            }).join(",");
          }
          function parseParam(param, conversions) {
            var restParam = param.indexOf("...") === 0;
            var types = !restParam ? param : param.length > 3 ? param.slice(3) : "any";
            var typeNames = types.split("|").map(trim).filter(notEmpty).filter(notIgnore);
            var matchingConversions = filterConversions(conversions, typeNames);
            var exactTypes = typeNames.map(function(typeName) {
              var type = findTypeByName(typeName);
              return {
                name: typeName,
                typeIndex: findTypeIndex(type),
                test: type.test,
                conversion: null,
                conversionIndex: -1
              };
            });
            var convertibleTypes = matchingConversions.map(function(conversion) {
              var type = findTypeByName(conversion.from);
              return {
                name: conversion.from,
                typeIndex: findTypeIndex(type),
                test: type.test,
                conversion,
                conversionIndex: conversions.indexOf(conversion)
              };
            });
            return {
              types: exactTypes.concat(convertibleTypes),
              restParam
            };
          }
          function parseSignature(signature, fn, conversions) {
            var params = [];
            if (signature.trim() !== "") {
              params = signature.split(",").map(trim).map(function(param, index, array) {
                var parsedParam = parseParam(param, conversions);
                if (parsedParam.restParam && index !== array.length - 1) {
                  throw new SyntaxError('Unexpected rest parameter "' + param + '": only allowed for the last parameter');
                }
                return parsedParam;
              });
            }
            if (params.some(isInvalidParam)) {
              return null;
            }
            return {
              params,
              fn
            };
          }
          function hasRestParam(params) {
            var param = last(params);
            return param ? param.restParam : false;
          }
          function hasConversions(param) {
            return param.types.some(function(type) {
              return type.conversion != null;
            });
          }
          function compileTest(param) {
            if (!param || param.types.length === 0) {
              return ok;
            } else if (param.types.length === 1) {
              return findTypeByName(param.types[0].name).test;
            } else if (param.types.length === 2) {
              var test0 = findTypeByName(param.types[0].name).test;
              var test1 = findTypeByName(param.types[1].name).test;
              return function or(x) {
                return test0(x) || test1(x);
              };
            } else {
              var tests = param.types.map(function(type) {
                return findTypeByName(type.name).test;
              });
              return function or(x) {
                for (var i = 0; i < tests.length; i++) {
                  if (tests[i](x)) {
                    return true;
                  }
                }
                return false;
              };
            }
          }
          function compileTests(params) {
            var tests, test0, test1;
            if (hasRestParam(params)) {
              tests = initial(params).map(compileTest);
              var varIndex = tests.length;
              var lastTest = compileTest(last(params));
              var testRestParam = function(args) {
                for (var i = varIndex; i < args.length; i++) {
                  if (!lastTest(args[i])) {
                    return false;
                  }
                }
                return true;
              };
              return function testArgs(args) {
                for (var i = 0; i < tests.length; i++) {
                  if (!tests[i](args[i])) {
                    return false;
                  }
                }
                return testRestParam(args) && args.length >= varIndex + 1;
              };
            } else {
              if (params.length === 0) {
                return function testArgs(args) {
                  return args.length === 0;
                };
              } else if (params.length === 1) {
                test0 = compileTest(params[0]);
                return function testArgs(args) {
                  return test0(args[0]) && args.length === 1;
                };
              } else if (params.length === 2) {
                test0 = compileTest(params[0]);
                test1 = compileTest(params[1]);
                return function testArgs(args) {
                  return test0(args[0]) && test1(args[1]) && args.length === 2;
                };
              } else {
                tests = params.map(compileTest);
                return function testArgs(args) {
                  for (var i = 0; i < tests.length; i++) {
                    if (!tests[i](args[i])) {
                      return false;
                    }
                  }
                  return args.length === tests.length;
                };
              }
            }
          }
          function getParamAtIndex(signature, index) {
            return index < signature.params.length ? signature.params[index] : hasRestParam(signature.params) ? last(signature.params) : null;
          }
          function getExpectedTypeNames(signature, index, excludeConversions) {
            var param = getParamAtIndex(signature, index);
            var types = param ? excludeConversions ? param.types.filter(isExactType) : param.types : [];
            return types.map(getTypeName);
          }
          function getTypeName(type) {
            return type.name;
          }
          function isExactType(type) {
            return type.conversion === null || type.conversion === void 0;
          }
          function mergeExpectedParams(signatures, index) {
            var typeNames = uniq(flatMap(signatures, function(signature) {
              return getExpectedTypeNames(signature, index, false);
            }));
            return typeNames.indexOf("any") !== -1 ? ["any"] : typeNames;
          }
          function createError(name, args, signatures) {
            var err, expected;
            var _name = name || "unnamed";
            var matchingSignatures = signatures;
            var index;
            for (index = 0; index < args.length; index++) {
              var nextMatchingDefs = matchingSignatures.filter(function(signature) {
                var test = compileTest(getParamAtIndex(signature, index));
                return (index < signature.params.length || hasRestParam(signature.params)) && test(args[index]);
              });
              if (nextMatchingDefs.length === 0) {
                expected = mergeExpectedParams(matchingSignatures, index);
                if (expected.length > 0) {
                  var actualType = findTypeName(args[index]);
                  err = new TypeError("Unexpected type of argument in function " + _name + " (expected: " + expected.join(" or ") + ", actual: " + actualType + ", index: " + index + ")");
                  err.data = {
                    category: "wrongType",
                    fn: _name,
                    index,
                    actual: actualType,
                    expected
                  };
                  return err;
                }
              } else {
                matchingSignatures = nextMatchingDefs;
              }
            }
            var lengths = matchingSignatures.map(function(signature) {
              return hasRestParam(signature.params) ? Infinity : signature.params.length;
            });
            if (args.length < Math.min.apply(null, lengths)) {
              expected = mergeExpectedParams(matchingSignatures, index);
              err = new TypeError("Too few arguments in function " + _name + " (expected: " + expected.join(" or ") + ", index: " + args.length + ")");
              err.data = {
                category: "tooFewArgs",
                fn: _name,
                index: args.length,
                expected
              };
              return err;
            }
            var maxLength = Math.max.apply(null, lengths);
            if (args.length > maxLength) {
              err = new TypeError("Too many arguments in function " + _name + " (expected: " + maxLength + ", actual: " + args.length + ")");
              err.data = {
                category: "tooManyArgs",
                fn: _name,
                index: args.length,
                expectedLength: maxLength
              };
              return err;
            }
            err = new TypeError('Arguments of type "' + args.join(", ") + '" do not match any of the defined signatures of function ' + _name + ".");
            err.data = {
              category: "mismatch",
              actual: args.map(findTypeName)
            };
            return err;
          }
          function getLowestTypeIndex(param) {
            var min = 999;
            for (var i = 0; i < param.types.length; i++) {
              if (isExactType(param.types[i])) {
                min = Math.min(min, param.types[i].typeIndex);
              }
            }
            return min;
          }
          function getLowestConversionIndex(param) {
            var min = 999;
            for (var i = 0; i < param.types.length; i++) {
              if (!isExactType(param.types[i])) {
                min = Math.min(min, param.types[i].conversionIndex);
              }
            }
            return min;
          }
          function compareParams(param1, param2) {
            var c;
            c = param1.restParam - param2.restParam;
            if (c !== 0) {
              return c;
            }
            c = hasConversions(param1) - hasConversions(param2);
            if (c !== 0) {
              return c;
            }
            c = getLowestTypeIndex(param1) - getLowestTypeIndex(param2);
            if (c !== 0) {
              return c;
            }
            return getLowestConversionIndex(param1) - getLowestConversionIndex(param2);
          }
          function compareSignatures(signature1, signature2) {
            var len = Math.min(signature1.params.length, signature2.params.length);
            var i;
            var c;
            c = signature1.params.some(hasConversions) - signature2.params.some(hasConversions);
            if (c !== 0) {
              return c;
            }
            for (i = 0; i < len; i++) {
              c = hasConversions(signature1.params[i]) - hasConversions(signature2.params[i]);
              if (c !== 0) {
                return c;
              }
            }
            for (i = 0; i < len; i++) {
              c = compareParams(signature1.params[i], signature2.params[i]);
              if (c !== 0) {
                return c;
              }
            }
            return signature1.params.length - signature2.params.length;
          }
          function filterConversions(conversions, typeNames) {
            var matches = {};
            conversions.forEach(function(conversion) {
              if (typeNames.indexOf(conversion.from) === -1 && typeNames.indexOf(conversion.to) !== -1 && !matches[conversion.from]) {
                matches[conversion.from] = conversion;
              }
            });
            return Object.keys(matches).map(function(from) {
              return matches[from];
            });
          }
          function compileArgsPreprocessing(params, fn) {
            var fnConvert = fn;
            if (params.some(hasConversions)) {
              var restParam = hasRestParam(params);
              var compiledConversions = params.map(compileArgConversion);
              fnConvert = function convertArgs() {
                var args = [];
                var last2 = restParam ? arguments.length - 1 : arguments.length;
                for (var i = 0; i < last2; i++) {
                  args[i] = compiledConversions[i](arguments[i]);
                }
                if (restParam) {
                  args[last2] = arguments[last2].map(compiledConversions[last2]);
                }
                return fn.apply(null, args);
              };
            }
            var fnPreprocess = fnConvert;
            if (hasRestParam(params)) {
              var offset = params.length - 1;
              fnPreprocess = function preprocessRestParams() {
                return fnConvert.apply(
                  null,
                  slice(arguments, 0, offset).concat([slice(arguments, offset)])
                );
              };
            }
            return fnPreprocess;
          }
          function compileArgConversion(param) {
            var test0, test1, conversion0, conversion1;
            var tests = [];
            var conversions = [];
            param.types.forEach(function(type) {
              if (type.conversion) {
                tests.push(findTypeByName(type.conversion.from).test);
                conversions.push(type.conversion.convert);
              }
            });
            switch (conversions.length) {
              case 0:
                return function convertArg(arg) {
                  return arg;
                };
              case 1:
                test0 = tests[0];
                conversion0 = conversions[0];
                return function convertArg(arg) {
                  if (test0(arg)) {
                    return conversion0(arg);
                  }
                  return arg;
                };
              case 2:
                test0 = tests[0];
                test1 = tests[1];
                conversion0 = conversions[0];
                conversion1 = conversions[1];
                return function convertArg(arg) {
                  if (test0(arg)) {
                    return conversion0(arg);
                  }
                  if (test1(arg)) {
                    return conversion1(arg);
                  }
                  return arg;
                };
              default:
                return function convertArg(arg) {
                  for (var i = 0; i < conversions.length; i++) {
                    if (tests[i](arg)) {
                      return conversions[i](arg);
                    }
                  }
                  return arg;
                };
            }
          }
          function createSignaturesMap(signatures) {
            var signaturesMap = {};
            signatures.forEach(function(signature) {
              if (!signature.params.some(hasConversions)) {
                splitParams(signature.params, true).forEach(function(params) {
                  signaturesMap[stringifyParams(params)] = signature.fn;
                });
              }
            });
            return signaturesMap;
          }
          function splitParams(params, ignoreConversionTypes) {
            function _splitParams(params2, index, types) {
              if (index < params2.length) {
                var param = params2[index];
                var filteredTypes = ignoreConversionTypes ? param.types.filter(isExactType) : param.types;
                var typeGroups;
                if (param.restParam) {
                  var exactTypes = filteredTypes.filter(isExactType);
                  typeGroups = exactTypes.length < filteredTypes.length ? [exactTypes, filteredTypes] : [filteredTypes];
                } else {
                  typeGroups = filteredTypes.map(function(type) {
                    return [type];
                  });
                }
                return flatMap(typeGroups, function(typeGroup) {
                  return _splitParams(params2, index + 1, types.concat([typeGroup]));
                });
              } else {
                var splittedParams = types.map(function(type, typeIndex) {
                  return {
                    types: type,
                    restParam: typeIndex === params2.length - 1 && hasRestParam(params2)
                  };
                });
                return [splittedParams];
              }
            }
            return _splitParams(params, 0, []);
          }
          function hasConflictingParams(signature1, signature2) {
            var ii = Math.max(signature1.params.length, signature2.params.length);
            for (var i = 0; i < ii; i++) {
              var typesNames1 = getExpectedTypeNames(signature1, i, true);
              var typesNames2 = getExpectedTypeNames(signature2, i, true);
              if (!hasOverlap(typesNames1, typesNames2)) {
                return false;
              }
            }
            var len1 = signature1.params.length;
            var len2 = signature2.params.length;
            var restParam1 = hasRestParam(signature1.params);
            var restParam2 = hasRestParam(signature2.params);
            return restParam1 ? restParam2 ? len1 === len2 : len2 >= len1 : restParam2 ? len1 >= len2 : len1 === len2;
          }
          function createTypedFunction(name, signaturesMap) {
            if (Object.keys(signaturesMap).length === 0) {
              throw new SyntaxError("No signatures provided");
            }
            var parsedSignatures = [];
            Object.keys(signaturesMap).map(function(signature) {
              return parseSignature(signature, signaturesMap[signature], typed.conversions);
            }).filter(notNull).forEach(function(parsedSignature) {
              var conflictingSignature = findInArray(parsedSignatures, function(s) {
                return hasConflictingParams(s, parsedSignature);
              });
              if (conflictingSignature) {
                throw new TypeError('Conflicting signatures "' + stringifyParams(conflictingSignature.params) + '" and "' + stringifyParams(parsedSignature.params) + '".');
              }
              parsedSignatures.push(parsedSignature);
            });
            var signatures = flatMap(parsedSignatures, function(parsedSignature) {
              var params = parsedSignature ? splitParams(parsedSignature.params, false) : [];
              return params.map(function(params2) {
                return {
                  params: params2,
                  fn: parsedSignature.fn
                };
              });
            }).filter(notNull);
            signatures.sort(compareSignatures);
            var ok0 = signatures[0] && signatures[0].params.length <= 2 && !hasRestParam(signatures[0].params);
            var ok1 = signatures[1] && signatures[1].params.length <= 2 && !hasRestParam(signatures[1].params);
            var ok2 = signatures[2] && signatures[2].params.length <= 2 && !hasRestParam(signatures[2].params);
            var ok3 = signatures[3] && signatures[3].params.length <= 2 && !hasRestParam(signatures[3].params);
            var ok4 = signatures[4] && signatures[4].params.length <= 2 && !hasRestParam(signatures[4].params);
            var ok5 = signatures[5] && signatures[5].params.length <= 2 && !hasRestParam(signatures[5].params);
            var allOk = ok0 && ok1 && ok2 && ok3 && ok4 && ok5;
            var tests = signatures.map(function(signature) {
              return compileTests(signature.params);
            });
            var test00 = ok0 ? compileTest(signatures[0].params[0]) : notOk;
            var test10 = ok1 ? compileTest(signatures[1].params[0]) : notOk;
            var test20 = ok2 ? compileTest(signatures[2].params[0]) : notOk;
            var test30 = ok3 ? compileTest(signatures[3].params[0]) : notOk;
            var test40 = ok4 ? compileTest(signatures[4].params[0]) : notOk;
            var test50 = ok5 ? compileTest(signatures[5].params[0]) : notOk;
            var test01 = ok0 ? compileTest(signatures[0].params[1]) : notOk;
            var test11 = ok1 ? compileTest(signatures[1].params[1]) : notOk;
            var test21 = ok2 ? compileTest(signatures[2].params[1]) : notOk;
            var test31 = ok3 ? compileTest(signatures[3].params[1]) : notOk;
            var test41 = ok4 ? compileTest(signatures[4].params[1]) : notOk;
            var test51 = ok5 ? compileTest(signatures[5].params[1]) : notOk;
            var fns = signatures.map(function(signature) {
              return compileArgsPreprocessing(signature.params, signature.fn);
            });
            var fn0 = ok0 ? fns[0] : undef;
            var fn1 = ok1 ? fns[1] : undef;
            var fn2 = ok2 ? fns[2] : undef;
            var fn3 = ok3 ? fns[3] : undef;
            var fn4 = ok4 ? fns[4] : undef;
            var fn5 = ok5 ? fns[5] : undef;
            var len0 = ok0 ? signatures[0].params.length : -1;
            var len1 = ok1 ? signatures[1].params.length : -1;
            var len2 = ok2 ? signatures[2].params.length : -1;
            var len3 = ok3 ? signatures[3].params.length : -1;
            var len4 = ok4 ? signatures[4].params.length : -1;
            var len5 = ok5 ? signatures[5].params.length : -1;
            var iStart = allOk ? 6 : 0;
            var iEnd = signatures.length;
            var generic = function generic2() {
              "use strict";
              for (var i = iStart; i < iEnd; i++) {
                if (tests[i](arguments)) {
                  return fns[i].apply(null, arguments);
                }
              }
              throw createError(name, arguments, signatures);
            };
            var fn = function fn6(arg0, arg1) {
              "use strict";
              if (arguments.length === len0 && test00(arg0) && test01(arg1)) {
                return fn0.apply(null, arguments);
              }
              if (arguments.length === len1 && test10(arg0) && test11(arg1)) {
                return fn1.apply(null, arguments);
              }
              if (arguments.length === len2 && test20(arg0) && test21(arg1)) {
                return fn2.apply(null, arguments);
              }
              if (arguments.length === len3 && test30(arg0) && test31(arg1)) {
                return fn3.apply(null, arguments);
              }
              if (arguments.length === len4 && test40(arg0) && test41(arg1)) {
                return fn4.apply(null, arguments);
              }
              if (arguments.length === len5 && test50(arg0) && test51(arg1)) {
                return fn5.apply(null, arguments);
              }
              return generic.apply(null, arguments);
            };
            try {
              Object.defineProperty(fn, "name", { value: name });
            } catch (err) {
            }
            fn.signatures = createSignaturesMap(signatures);
            return fn;
          }
          function notIgnore(typeName) {
            return typed.ignore.indexOf(typeName) === -1;
          }
          function trim(str) {
            return str.trim();
          }
          function notEmpty(str) {
            return !!str;
          }
          function notNull(value) {
            return value !== null;
          }
          function isInvalidParam(param) {
            return param.types.length === 0;
          }
          function initial(arr) {
            return arr.slice(0, arr.length - 1);
          }
          function last(arr) {
            return arr[arr.length - 1];
          }
          function slice(arr, start, end) {
            return Array.prototype.slice.call(arr, start, end);
          }
          function contains(array, item) {
            return array.indexOf(item) !== -1;
          }
          function hasOverlap(array1, array2) {
            for (var i = 0; i < array1.length; i++) {
              if (contains(array2, array1[i])) {
                return true;
              }
            }
            return false;
          }
          function findInArray(arr, test) {
            for (var i = 0; i < arr.length; i++) {
              if (test(arr[i])) {
                return arr[i];
              }
            }
            return void 0;
          }
          function uniq(arr) {
            var entries = {};
            for (var i = 0; i < arr.length; i++) {
              entries[arr[i]] = true;
            }
            return Object.keys(entries);
          }
          function flatMap(arr, callback) {
            return Array.prototype.concat.apply([], arr.map(callback));
          }
          function getName(fns) {
            var name = "";
            for (var i = 0; i < fns.length; i++) {
              var fn = fns[i];
              if ((typeof fn.signatures === "object" || typeof fn.signature === "string") && fn.name !== "") {
                if (name === "") {
                  name = fn.name;
                } else if (name !== fn.name) {
                  var err = new Error("Function names do not match (expected: " + name + ", actual: " + fn.name + ")");
                  err.data = {
                    actual: fn.name,
                    expected: name
                  };
                  throw err;
                }
              }
            }
            return name;
          }
          function extractSignatures(fns) {
            var err;
            var signaturesMap = {};
            function validateUnique(_signature, _fn) {
              if (signaturesMap.hasOwnProperty(_signature) && _fn !== signaturesMap[_signature]) {
                err = new Error('Signature "' + _signature + '" is defined twice');
                err.data = { signature: _signature };
                throw err;
              }
            }
            for (var i = 0; i < fns.length; i++) {
              var fn = fns[i];
              if (typeof fn.signatures === "object") {
                for (var signature in fn.signatures) {
                  if (fn.signatures.hasOwnProperty(signature)) {
                    validateUnique(signature, fn.signatures[signature]);
                    signaturesMap[signature] = fn.signatures[signature];
                  }
                }
              } else if (typeof fn.signature === "string") {
                validateUnique(fn.signature, fn);
                signaturesMap[fn.signature] = fn;
              } else {
                err = new TypeError("Function is no typed-function (index: " + i + ")");
                err.data = { index: i };
                throw err;
              }
            }
            return signaturesMap;
          }
          typed = createTypedFunction("typed", {
            "string, Object": createTypedFunction,
            "Object": function(signaturesMap) {
              var fns = [];
              for (var signature in signaturesMap) {
                if (signaturesMap.hasOwnProperty(signature)) {
                  fns.push(signaturesMap[signature]);
                }
              }
              var name = getName(fns);
              return createTypedFunction(name, signaturesMap);
            },
            "...Function": function(fns) {
              return createTypedFunction(getName(fns), extractSignatures(fns));
            },
            "string, ...Function": function(name, fns) {
              return createTypedFunction(name, extractSignatures(fns));
            }
          });
          typed.create = create;
          typed.types = _types;
          typed.conversions = _conversions;
          typed.ignore = _ignore;
          typed.convert = convert;
          typed.find = find;
          typed.addType = function(type, beforeObjectTest) {
            if (!type || typeof type.name !== "string" || typeof type.test !== "function") {
              throw new TypeError("Object with properties {name: string, test: function} expected");
            }
            if (beforeObjectTest !== false) {
              for (var i = 0; i < typed.types.length; i++) {
                if (typed.types[i].name === "Object") {
                  typed.types.splice(i, 0, type);
                  return;
                }
              }
            }
            typed.types.push(type);
          };
          typed.addConversion = function(conversion) {
            if (!conversion || typeof conversion.from !== "string" || typeof conversion.to !== "string" || typeof conversion.convert !== "function") {
              throw new TypeError("Object with properties {from: string, to: string, convert: function} expected");
            }
            typed.conversions.push(conversion);
          };
          return typed;
        }
        return create();
      });
    }
  });

  // node_modules/mathjs/lib/utils/number.js
  var require_number = __commonJS({
    "node_modules/mathjs/lib/utils/number.js"(exports) {
      "use strict";
      var objectUtils = require_object();
      exports.isNumber = function(value) {
        return typeof value === "number";
      };
      exports.isInteger = function(value) {
        if (typeof value === "boolean") {
          return true;
        }
        return isFinite(value) ? value === Math.round(value) : false;
      };
      exports.sign = Math.sign || function(x) {
        if (x > 0) {
          return 1;
        } else if (x < 0) {
          return -1;
        } else {
          return 0;
        }
      };
      exports.format = function(value, options) {
        if (typeof options === "function") {
          return options(value);
        }
        if (value === Infinity) {
          return "Infinity";
        } else if (value === -Infinity) {
          return "-Infinity";
        } else if (isNaN(value)) {
          return "NaN";
        }
        var notation = "auto";
        var precision;
        if (options) {
          if (options.notation) {
            notation = options.notation;
          }
          if (exports.isNumber(options)) {
            precision = options;
          } else if (exports.isNumber(options.precision)) {
            precision = options.precision;
          }
        }
        switch (notation) {
          case "fixed":
            return exports.toFixed(value, precision);
          case "exponential":
            return exports.toExponential(value, precision);
          case "engineering":
            return exports.toEngineering(value, precision);
          case "auto":
            if (options && options.exponential && (options.exponential.lower !== void 0 || options.exponential.upper !== void 0)) {
              var fixedOptions = objectUtils.map(options, function(x) {
                return x;
              });
              fixedOptions.exponential = void 0;
              if (options.exponential.lower !== void 0) {
                fixedOptions.lowerExp = Math.round(Math.log(options.exponential.lower) / Math.LN10);
              }
              if (options.exponential.upper !== void 0) {
                fixedOptions.upperExp = Math.round(Math.log(options.exponential.upper) / Math.LN10);
              }
              console.warn("Deprecation warning: Formatting options exponential.lower and exponential.upper (minimum and maximum value) are replaced with exponential.lowerExp and exponential.upperExp (minimum and maximum exponent) since version 4.0.0. Replace " + JSON.stringify(options) + " with " + JSON.stringify(fixedOptions));
              return exports.toPrecision(value, precision, fixedOptions);
            }
            return exports.toPrecision(value, precision, options && options).replace(/((\.\d*?)(0+))($|e)/, function() {
              var digits = arguments[2];
              var e = arguments[4];
              return digits !== "." ? digits + e : e;
            });
          default:
            throw new Error('Unknown notation "' + notation + '". Choose "auto", "exponential", or "fixed".');
        }
      };
      exports.splitNumber = function(value) {
        var match = String(value).toLowerCase().match(/^0*?(-?)(\d+\.?\d*)(e([+-]?\d+))?$/);
        if (!match) {
          throw new SyntaxError("Invalid number " + value);
        }
        var sign = match[1];
        var digits = match[2];
        var exponent = parseFloat(match[4] || "0");
        var dot = digits.indexOf(".");
        exponent += dot !== -1 ? dot - 1 : digits.length - 1;
        var coefficients = digits.replace(".", "").replace(/^0*/, function(zeros2) {
          exponent -= zeros2.length;
          return "";
        }).replace(/0*$/, "").split("").map(function(d) {
          return parseInt(d);
        });
        if (coefficients.length === 0) {
          coefficients.push(0);
          exponent++;
        }
        return {
          sign,
          coefficients,
          exponent
        };
      };
      exports.toEngineering = function(value, precision) {
        if (isNaN(value) || !isFinite(value)) {
          return String(value);
        }
        var rounded = exports.roundDigits(exports.splitNumber(value), precision);
        var e = rounded.exponent;
        var c = rounded.coefficients;
        var newExp = e % 3 === 0 ? e : e < 0 ? e - 3 - e % 3 : e - e % 3;
        if (exports.isNumber(precision)) {
          while (precision > c.length || e - newExp + 1 > c.length) {
            c.push(0);
          }
        } else {
          var significandsDiff = e >= 0 ? e : Math.abs(newExp);
          while (c.length - 1 < significandsDiff) {
            c.push(0);
          }
        }
        var expDiff = Math.abs(e - newExp);
        var decimalIdx = 1;
        while (expDiff > 0) {
          decimalIdx++;
          expDiff--;
        }
        var decimals = c.slice(decimalIdx).join("");
        var decimalVal = exports.isNumber(precision) && decimals.length || decimals.match(/[1-9]/) ? "." + decimals : "";
        var str = c.slice(0, decimalIdx).join("") + decimalVal + "e" + (e >= 0 ? "+" : "") + newExp.toString();
        return rounded.sign + str;
      };
      exports.toFixed = function(value, precision) {
        if (isNaN(value) || !isFinite(value)) {
          return String(value);
        }
        var splitValue = exports.splitNumber(value);
        var rounded = typeof precision === "number" ? exports.roundDigits(splitValue, splitValue.exponent + 1 + precision) : splitValue;
        var c = rounded.coefficients;
        var p = rounded.exponent + 1;
        var pp = p + (precision || 0);
        if (c.length < pp) {
          c = c.concat(zeros(pp - c.length));
        }
        if (p < 0) {
          c = zeros(-p + 1).concat(c);
          p = 1;
        }
        if (p < c.length) {
          c.splice(p, 0, p === 0 ? "0." : ".");
        }
        return rounded.sign + c.join("");
      };
      exports.toExponential = function(value, precision) {
        if (isNaN(value) || !isFinite(value)) {
          return String(value);
        }
        var split = exports.splitNumber(value);
        var rounded = precision ? exports.roundDigits(split, precision) : split;
        var c = rounded.coefficients;
        var e = rounded.exponent;
        if (c.length < precision) {
          c = c.concat(zeros(precision - c.length));
        }
        var first = c.shift();
        return rounded.sign + first + (c.length > 0 ? "." + c.join("") : "") + "e" + (e >= 0 ? "+" : "") + e;
      };
      exports.toPrecision = function(value, precision, options) {
        if (isNaN(value) || !isFinite(value)) {
          return String(value);
        }
        var lowerExp = options && options.lowerExp !== void 0 ? options.lowerExp : -3;
        var upperExp = options && options.upperExp !== void 0 ? options.upperExp : 5;
        var split = exports.splitNumber(value);
        if (split.exponent < lowerExp || split.exponent >= upperExp) {
          return exports.toExponential(value, precision);
        } else {
          var rounded = precision ? exports.roundDigits(split, precision) : split;
          var c = rounded.coefficients;
          var e = rounded.exponent;
          if (c.length < precision) {
            c = c.concat(zeros(precision - c.length));
          }
          c = c.concat(zeros(e - c.length + 1 + (c.length < precision ? precision - c.length : 0)));
          c = zeros(-e).concat(c);
          var dot = e > 0 ? e : 0;
          if (dot < c.length - 1) {
            c.splice(dot + 1, 0, ".");
          }
          return rounded.sign + c.join("");
        }
      };
      exports.roundDigits = function(split, precision) {
        var rounded = {
          sign: split.sign,
          coefficients: split.coefficients,
          exponent: split.exponent
        };
        var c = rounded.coefficients;
        while (precision <= 0) {
          c.unshift(0);
          rounded.exponent++;
          precision++;
        }
        if (c.length > precision) {
          var removed = c.splice(precision, c.length - precision);
          if (removed[0] >= 5) {
            var i = precision - 1;
            c[i]++;
            while (c[i] === 10) {
              c.pop();
              if (i === 0) {
                c.unshift(0);
                rounded.exponent++;
                i++;
              }
              i--;
              c[i]++;
            }
          }
        }
        return rounded;
      };
      function zeros(length) {
        var arr = [];
        for (var i = 0; i < length; i++) {
          arr.push(0);
        }
        return arr;
      }
      exports.digits = function(value) {
        return value.toExponential().replace(/e.*$/, "").replace(/^0\.?0*|\./, "").length;
      };
      exports.DBL_EPSILON = Number.EPSILON || 2220446049250313e-31;
      exports.nearlyEqual = function(x, y, epsilon) {
        if (epsilon === null || epsilon === void 0) {
          return x === y;
        }
        if (x === y) {
          return true;
        }
        if (isNaN(x) || isNaN(y)) {
          return false;
        }
        if (isFinite(x) && isFinite(y)) {
          var diff = Math.abs(x - y);
          if (diff < exports.DBL_EPSILON) {
            return true;
          } else {
            return diff <= Math.max(Math.abs(x), Math.abs(y)) * epsilon;
          }
        }
        return false;
      };
    }
  });

  // node_modules/mathjs/lib/utils/collection/isMatrix.js
  var require_isMatrix = __commonJS({
    "node_modules/mathjs/lib/utils/collection/isMatrix.js"(exports, module) {
      "use strict";
      module.exports = function isMatrix(x) {
        return x && x.constructor.prototype.isMatrix || false;
      };
    }
  });

  // node_modules/mathjs/lib/core/typed.js
  var require_typed = __commonJS({
    "node_modules/mathjs/lib/core/typed.js"(exports) {
      "use strict";
      function _typeof(obj) {
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      var typedFunction = require_typed_function();
      var digits = require_number().digits;
      var isBigNumber = require_isBigNumber();
      var isMatrix = require_isMatrix();
      var _createTyped = function createTyped() {
        _createTyped = typedFunction.create;
        return typedFunction;
      };
      exports.create = function create(type) {
        type.isNumber = function(x) {
          return typeof x === "number";
        };
        type.isComplex = function(x) {
          return type.Complex && x instanceof type.Complex || false;
        };
        type.isBigNumber = isBigNumber;
        type.isFraction = function(x) {
          return type.Fraction && x instanceof type.Fraction || false;
        };
        type.isUnit = function(x) {
          return x && x.constructor.prototype.isUnit || false;
        };
        type.isString = function(x) {
          return typeof x === "string";
        };
        type.isArray = Array.isArray;
        type.isMatrix = isMatrix;
        type.isDenseMatrix = function(x) {
          return x && x.isDenseMatrix && x.constructor.prototype.isMatrix || false;
        };
        type.isSparseMatrix = function(x) {
          return x && x.isSparseMatrix && x.constructor.prototype.isMatrix || false;
        };
        type.isRange = function(x) {
          return x && x.constructor.prototype.isRange || false;
        };
        type.isIndex = function(x) {
          return x && x.constructor.prototype.isIndex || false;
        };
        type.isBoolean = function(x) {
          return typeof x === "boolean";
        };
        type.isResultSet = function(x) {
          return x && x.constructor.prototype.isResultSet || false;
        };
        type.isHelp = function(x) {
          return x && x.constructor.prototype.isHelp || false;
        };
        type.isFunction = function(x) {
          return typeof x === "function";
        };
        type.isDate = function(x) {
          return x instanceof Date;
        };
        type.isRegExp = function(x) {
          return x instanceof RegExp;
        };
        type.isObject = function(x) {
          return _typeof(x) === "object" && x.constructor === Object && !type.isComplex(x) && !type.isFraction(x);
        };
        type.isNull = function(x) {
          return x === null;
        };
        type.isUndefined = function(x) {
          return x === void 0;
        };
        type.isAccessorNode = function(x) {
          return x && x.isAccessorNode && x.constructor.prototype.isNode || false;
        };
        type.isArrayNode = function(x) {
          return x && x.isArrayNode && x.constructor.prototype.isNode || false;
        };
        type.isAssignmentNode = function(x) {
          return x && x.isAssignmentNode && x.constructor.prototype.isNode || false;
        };
        type.isBlockNode = function(x) {
          return x && x.isBlockNode && x.constructor.prototype.isNode || false;
        };
        type.isConditionalNode = function(x) {
          return x && x.isConditionalNode && x.constructor.prototype.isNode || false;
        };
        type.isConstantNode = function(x) {
          return x && x.isConstantNode && x.constructor.prototype.isNode || false;
        };
        type.isFunctionAssignmentNode = function(x) {
          return x && x.isFunctionAssignmentNode && x.constructor.prototype.isNode || false;
        };
        type.isFunctionNode = function(x) {
          return x && x.isFunctionNode && x.constructor.prototype.isNode || false;
        };
        type.isIndexNode = function(x) {
          return x && x.isIndexNode && x.constructor.prototype.isNode || false;
        };
        type.isNode = function(x) {
          return x && x.isNode && x.constructor.prototype.isNode || false;
        };
        type.isObjectNode = function(x) {
          return x && x.isObjectNode && x.constructor.prototype.isNode || false;
        };
        type.isOperatorNode = function(x) {
          return x && x.isOperatorNode && x.constructor.prototype.isNode || false;
        };
        type.isParenthesisNode = function(x) {
          return x && x.isParenthesisNode && x.constructor.prototype.isNode || false;
        };
        type.isRangeNode = function(x) {
          return x && x.isRangeNode && x.constructor.prototype.isNode || false;
        };
        type.isSymbolNode = function(x) {
          return x && x.isSymbolNode && x.constructor.prototype.isNode || false;
        };
        type.isChain = function(x) {
          return x && x.constructor.prototype.isChain || false;
        };
        var typed = _createTyped();
        typed.types = [{
          name: "number",
          test: type.isNumber
        }, {
          name: "Complex",
          test: type.isComplex
        }, {
          name: "BigNumber",
          test: type.isBigNumber
        }, {
          name: "Fraction",
          test: type.isFraction
        }, {
          name: "Unit",
          test: type.isUnit
        }, {
          name: "string",
          test: type.isString
        }, {
          name: "Array",
          test: type.isArray
        }, {
          name: "Matrix",
          test: type.isMatrix
        }, {
          name: "DenseMatrix",
          test: type.isDenseMatrix
        }, {
          name: "SparseMatrix",
          test: type.isSparseMatrix
        }, {
          name: "Range",
          test: type.isRange
        }, {
          name: "Index",
          test: type.isIndex
        }, {
          name: "boolean",
          test: type.isBoolean
        }, {
          name: "ResultSet",
          test: type.isResultSet
        }, {
          name: "Help",
          test: type.isHelp
        }, {
          name: "function",
          test: type.isFunction
        }, {
          name: "Date",
          test: type.isDate
        }, {
          name: "RegExp",
          test: type.isRegExp
        }, {
          name: "null",
          test: type.isNull
        }, {
          name: "undefined",
          test: type.isUndefined
        }, {
          name: "OperatorNode",
          test: type.isOperatorNode
        }, {
          name: "ConstantNode",
          test: type.isConstantNode
        }, {
          name: "SymbolNode",
          test: type.isSymbolNode
        }, {
          name: "ParenthesisNode",
          test: type.isParenthesisNode
        }, {
          name: "FunctionNode",
          test: type.isFunctionNode
        }, {
          name: "FunctionAssignmentNode",
          test: type.isFunctionAssignmentNode
        }, {
          name: "ArrayNode",
          test: type.isArrayNode
        }, {
          name: "AssignmentNode",
          test: type.isAssignmentNode
        }, {
          name: "BlockNode",
          test: type.isBlockNode
        }, {
          name: "ConditionalNode",
          test: type.isConditionalNode
        }, {
          name: "IndexNode",
          test: type.isIndexNode
        }, {
          name: "RangeNode",
          test: type.isRangeNode
        }, {
          name: "Node",
          test: type.isNode
        }, {
          name: "Object",
          test: type.isObject
          // order 'Object' last, it matches on other classes too
        }];
        typed.conversions = [{
          from: "number",
          to: "BigNumber",
          convert: function convert(x) {
            if (digits(x) > 15) {
              throw new TypeError("Cannot implicitly convert a number with >15 significant digits to BigNumber (value: " + x + "). Use function bignumber(x) to convert to BigNumber.");
            }
            return new type.BigNumber(x);
          }
        }, {
          from: "number",
          to: "Complex",
          convert: function convert(x) {
            return new type.Complex(x, 0);
          }
        }, {
          from: "number",
          to: "string",
          convert: function convert(x) {
            return x + "";
          }
        }, {
          from: "BigNumber",
          to: "Complex",
          convert: function convert(x) {
            return new type.Complex(x.toNumber(), 0);
          }
        }, {
          from: "Fraction",
          to: "BigNumber",
          convert: function convert(x) {
            throw new TypeError("Cannot implicitly convert a Fraction to BigNumber or vice versa. Use function bignumber(x) to convert to BigNumber or fraction(x) to convert to Fraction.");
          }
        }, {
          from: "Fraction",
          to: "Complex",
          convert: function convert(x) {
            return new type.Complex(x.valueOf(), 0);
          }
        }, {
          from: "number",
          to: "Fraction",
          convert: function convert(x) {
            var f = new type.Fraction(x);
            if (f.valueOf() !== x) {
              throw new TypeError("Cannot implicitly convert a number to a Fraction when there will be a loss of precision (value: " + x + "). Use function fraction(x) to convert to Fraction.");
            }
            return new type.Fraction(x);
          }
        }, {
          // FIXME: add conversion from Fraction to number, for example for `sqrt(fraction(1,3))`
          //  from: 'Fraction',
          //  to: 'number',
          //  convert: function (x) {
          //    return x.valueOf()
          //  }
          // }, {
          from: "string",
          to: "number",
          convert: function convert(x) {
            var n = Number(x);
            if (isNaN(n)) {
              throw new Error('Cannot convert "' + x + '" to a number');
            }
            return n;
          }
        }, {
          from: "string",
          to: "BigNumber",
          convert: function convert(x) {
            try {
              return new type.BigNumber(x);
            } catch (err) {
              throw new Error('Cannot convert "' + x + '" to BigNumber');
            }
          }
        }, {
          from: "string",
          to: "Fraction",
          convert: function convert(x) {
            try {
              return new type.Fraction(x);
            } catch (err) {
              throw new Error('Cannot convert "' + x + '" to Fraction');
            }
          }
        }, {
          from: "string",
          to: "Complex",
          convert: function convert(x) {
            try {
              return new type.Complex(x);
            } catch (err) {
              throw new Error('Cannot convert "' + x + '" to Complex');
            }
          }
        }, {
          from: "boolean",
          to: "number",
          convert: function convert(x) {
            return +x;
          }
        }, {
          from: "boolean",
          to: "BigNumber",
          convert: function convert(x) {
            return new type.BigNumber(+x);
          }
        }, {
          from: "boolean",
          to: "Fraction",
          convert: function convert(x) {
            return new type.Fraction(+x);
          }
        }, {
          from: "boolean",
          to: "string",
          convert: function convert(x) {
            return +x;
          }
        }, {
          from: "Array",
          to: "Matrix",
          convert: function convert(array) {
            return new type.DenseMatrix(array);
          }
        }, {
          from: "Matrix",
          to: "Array",
          convert: function convert(matrix) {
            return matrix.valueOf();
          }
        }];
        return typed;
      };
    }
  });

  // node_modules/tiny-emitter/index.js
  var require_tiny_emitter = __commonJS({
    "node_modules/tiny-emitter/index.js"(exports, module) {
      function E() {
      }
      E.prototype = {
        on: function(name, callback, ctx) {
          var e = this.e || (this.e = {});
          (e[name] || (e[name] = [])).push({
            fn: callback,
            ctx
          });
          return this;
        },
        once: function(name, callback, ctx) {
          var self = this;
          function listener() {
            self.off(name, listener);
            callback.apply(ctx, arguments);
          }
          ;
          listener._ = callback;
          return this.on(name, listener, ctx);
        },
        emit: function(name) {
          var data = [].slice.call(arguments, 1);
          var evtArr = ((this.e || (this.e = {}))[name] || []).slice();
          var i = 0;
          var len = evtArr.length;
          for (i; i < len; i++) {
            evtArr[i].fn.apply(evtArr[i].ctx, data);
          }
          return this;
        },
        off: function(name, callback) {
          var e = this.e || (this.e = {});
          var evts = e[name];
          var liveEvents = [];
          if (evts && callback) {
            for (var i = 0, len = evts.length; i < len; i++) {
              if (evts[i].fn !== callback && evts[i].fn._ !== callback)
                liveEvents.push(evts[i]);
            }
          }
          liveEvents.length ? e[name] = liveEvents : delete e[name];
          return this;
        }
      };
      module.exports = E;
      module.exports.TinyEmitter = E;
    }
  });

  // node_modules/mathjs/lib/utils/emitter.js
  var require_emitter = __commonJS({
    "node_modules/mathjs/lib/utils/emitter.js"(exports) {
      "use strict";
      var Emitter = require_tiny_emitter();
      exports.mixin = function(obj) {
        var emitter = new Emitter();
        obj.on = emitter.on.bind(emitter);
        obj.off = emitter.off.bind(emitter);
        obj.once = emitter.once.bind(emitter);
        obj.emit = emitter.emit.bind(emitter);
        return obj;
      };
    }
  });

  // node_modules/mathjs/lib/error/ArgumentsError.js
  var require_ArgumentsError = __commonJS({
    "node_modules/mathjs/lib/error/ArgumentsError.js"(exports, module) {
      "use strict";
      function ArgumentsError(fn, count, min, max) {
        if (!(this instanceof ArgumentsError)) {
          throw new SyntaxError("Constructor must be called with the new operator");
        }
        this.fn = fn;
        this.count = count;
        this.min = min;
        this.max = max;
        this.message = "Wrong number of arguments in function " + fn + " (" + count + " provided, " + min + (max !== void 0 && max !== null ? "-" + max : "") + " expected)";
        this.stack = new Error().stack;
      }
      ArgumentsError.prototype = new Error();
      ArgumentsError.prototype.constructor = Error;
      ArgumentsError.prototype.name = "ArgumentsError";
      ArgumentsError.prototype.isArgumentsError = true;
      module.exports = ArgumentsError;
    }
  });

  // node_modules/mathjs/lib/core/function/import.js
  var require_import = __commonJS({
    "node_modules/mathjs/lib/core/function/import.js"(exports) {
      "use strict";
      function _typeof(obj) {
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      var lazy = require_object().lazy;
      var isFactory = require_object().isFactory;
      var traverse = require_object().traverse;
      var ArgumentsError = require_ArgumentsError();
      function factory(type, config, load, typed, math2) {
        function mathImport(object, options) {
          var num = arguments.length;
          if (num !== 1 && num !== 2) {
            throw new ArgumentsError("import", num, 1, 2);
          }
          if (!options) {
            options = {};
          }
          if (isFactory(object)) {
            _importFactory(object, options);
          } else if (Array.isArray(object)) {
            object.forEach(function(entry) {
              mathImport(entry, options);
            });
          } else if (_typeof(object) === "object") {
            for (var name in object) {
              if (object.hasOwnProperty(name)) {
                var value = object[name];
                if (isSupportedType(value)) {
                  _import(name, value, options);
                } else if (isFactory(object)) {
                  _importFactory(object, options);
                } else {
                  mathImport(value, options);
                }
              }
            }
          } else {
            if (!options.silent) {
              throw new TypeError("Factory, Object, or Array expected");
            }
          }
        }
        function _import(name, value, options) {
          if (options.wrap && typeof value === "function") {
            value = _wrap(value);
          }
          if (isTypedFunction(math2[name]) && isTypedFunction(value)) {
            if (options.override) {
              value = typed(name, value.signatures);
            } else {
              value = typed(math2[name], value);
            }
            math2[name] = value;
            _importTransform(name, value);
            math2.emit("import", name, function resolver() {
              return value;
            });
            return;
          }
          if (math2[name] === void 0 || options.override) {
            math2[name] = value;
            _importTransform(name, value);
            math2.emit("import", name, function resolver() {
              return value;
            });
            return;
          }
          if (!options.silent) {
            throw new Error('Cannot import "' + name + '": already exists');
          }
        }
        function _importTransform(name, value) {
          if (value && typeof value.transform === "function") {
            math2.expression.transform[name] = value.transform;
            if (allowedInExpressions(name)) {
              math2.expression.mathWithTransform[name] = value.transform;
            }
          } else {
            delete math2.expression.transform[name];
            if (allowedInExpressions(name)) {
              math2.expression.mathWithTransform[name] = value;
            }
          }
        }
        function _deleteTransform(name) {
          delete math2.expression.transform[name];
          if (allowedInExpressions(name)) {
            math2.expression.mathWithTransform[name] = math2[name];
          } else {
            delete math2.expression.mathWithTransform[name];
          }
        }
        function _wrap(fn) {
          var wrapper = function wrapper2() {
            var args = [];
            for (var i = 0, len = arguments.length; i < len; i++) {
              var arg = arguments[i];
              args[i] = arg && arg.valueOf();
            }
            return fn.apply(math2, args);
          };
          if (fn.transform) {
            wrapper.transform = fn.transform;
          }
          return wrapper;
        }
        function _importFactory(factory2, options) {
          if (typeof factory2.name === "string") {
            var name = factory2.name;
            var existingTransform = name in math2.expression.transform;
            var namespace = factory2.path ? traverse(math2, factory2.path) : math2;
            var existing = namespace.hasOwnProperty(name) ? namespace[name] : void 0;
            var resolver = function resolver2() {
              var instance = load(factory2);
              if (instance && typeof instance.transform === "function") {
                throw new Error('Transforms cannot be attached to factory functions. Please create a separate function for it with exports.path="expression.transform"');
              }
              if (isTypedFunction(existing) && isTypedFunction(instance)) {
                if (options.override) {
                } else {
                  instance = typed(existing, instance);
                }
                return instance;
              }
              if (existing === void 0 || options.override) {
                return instance;
              }
              if (!options.silent) {
                throw new Error('Cannot import "' + name + '": already exists');
              }
            };
            if (factory2.lazy !== false) {
              lazy(namespace, name, resolver);
              if (existingTransform) {
                _deleteTransform(name);
              } else {
                if (factory2.path === "expression.transform" || factoryAllowedInExpressions(factory2)) {
                  lazy(math2.expression.mathWithTransform, name, resolver);
                }
              }
            } else {
              namespace[name] = resolver();
              if (existingTransform) {
                _deleteTransform(name);
              } else {
                if (factory2.path === "expression.transform" || factoryAllowedInExpressions(factory2)) {
                  math2.expression.mathWithTransform[name] = resolver();
                }
              }
            }
            math2.emit("import", name, resolver, factory2.path);
          } else {
            load(factory2);
          }
        }
        function isSupportedType(object) {
          return typeof object === "function" || typeof object === "number" || typeof object === "string" || typeof object === "boolean" || object === null || object && type.isUnit(object) || object && type.isComplex(object) || object && type.isBigNumber(object) || object && type.isFraction(object) || object && type.isMatrix(object) || object && Array.isArray(object);
        }
        function isTypedFunction(fn) {
          return typeof fn === "function" && _typeof(fn.signatures) === "object";
        }
        function allowedInExpressions(name) {
          return !unsafe.hasOwnProperty(name);
        }
        function factoryAllowedInExpressions(factory2) {
          return factory2.path === void 0 && !unsafe.hasOwnProperty(factory2.name);
        }
        var unsafe = {
          "expression": true,
          "type": true,
          "docs": true,
          "error": true,
          "json": true,
          "chain": true
          // chain method not supported. Note that there is a unit chain too.
        };
        return mathImport;
      }
      exports.math = true;
      exports.name = "import";
      exports.factory = factory;
      exports.lazy = true;
    }
  });

  // node_modules/mathjs/lib/core/function/config.js
  var require_config = __commonJS({
    "node_modules/mathjs/lib/core/function/config.js"(exports) {
      "use strict";
      var object = require_object();
      function factory(type, config, load, typed, math2) {
        var MATRIX = ["Matrix", "Array"];
        var NUMBER = ["number", "BigNumber", "Fraction"];
        function _config(options) {
          if (options) {
            var prev = object.map(config, object.clone);
            validateOption(options, "matrix", MATRIX);
            validateOption(options, "number", NUMBER);
            object.deepExtend(config, options);
            var curr = object.map(config, object.clone);
            var changes = object.map(options, object.clone);
            math2.emit("config", curr, prev, changes);
            return curr;
          } else {
            return object.map(config, object.clone);
          }
        }
        _config.MATRIX = MATRIX;
        _config.NUMBER = NUMBER;
        return _config;
      }
      function contains(array, item) {
        return array.indexOf(item) !== -1;
      }
      function findIndex(array, item) {
        return array.map(function(i) {
          return i.toLowerCase();
        }).indexOf(item.toLowerCase());
      }
      function validateOption(options, name, values) {
        if (options[name] !== void 0 && !contains(values, options[name])) {
          var index = findIndex(values, options[name]);
          if (index !== -1) {
            console.warn('Warning: Wrong casing for configuration option "' + name + '", should be "' + values[index] + '" instead of "' + options[name] + '".');
            options[name] = values[index];
          } else {
            console.warn('Warning: Unknown value "' + options[name] + '" for configuration option "' + name + '". Available options: ' + values.map(JSON.stringify).join(", ") + ".");
          }
        }
      }
      exports.name = "config";
      exports.math = true;
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/core/core.js
  var require_core = __commonJS({
    "node_modules/mathjs/lib/core/core.js"(exports) {
      "use strict";
      require_polyfills();
      var isFactory = require_object().isFactory;
      var typedFactory = require_typed();
      var emitter = require_emitter();
      var importFactory = require_import();
      var configFactory = require_config();
      exports.create = function create(options) {
        if (typeof Object.create !== "function") {
          throw new Error("ES5 not supported by this JavaScript engine. Please load the es5-shim and es5-sham library for compatibility.");
        }
        var factories = [];
        var instances = [];
        var math2 = emitter.mixin({});
        math2.type = {};
        math2.expression = {
          transform: {},
          mathWithTransform: {}
          // create a new typed instance
        };
        math2.typed = typedFactory.create(math2.type);
        var _config = {
          // minimum relative difference between two compared values,
          // used by all comparison functions
          epsilon: 1e-12,
          // type of default matrix output. Choose 'matrix' (default) or 'array'
          matrix: "Matrix",
          // type of default number output. Choose 'number' (default) 'BigNumber', or 'Fraction
          number: "number",
          // number of significant digits in BigNumbers
          precision: 64,
          // predictable output type of functions. When true, output type depends only
          // on the input types. When false (default), output type can vary depending
          // on input values. For example `math.sqrt(-4)` returns `complex('2i')` when
          // predictable is false, and returns `NaN` when true.
          predictable: false,
          // random seed for seeded pseudo random number generation
          // null = randomly seed
          randomSeed: null
          /**
           * Load a function or data type from a factory.
           * If the function or data type already exists, the existing instance is
           * returned.
           * @param {{type: string, name: string, factory: Function}} factory
           * @returns {*}
           */
        };
        function load(factory) {
          if (!isFactory(factory)) {
            throw new Error("Factory object with properties `type`, `name`, and `factory` expected");
          }
          var index = factories.indexOf(factory);
          var instance;
          if (index === -1) {
            if (factory.math === true) {
              instance = factory.factory(math2.type, _config, load, math2.typed, math2);
            } else {
              instance = factory.factory(math2.type, _config, load, math2.typed);
            }
            factories.push(factory);
            instances.push(instance);
          } else {
            instance = instances[index];
          }
          return instance;
        }
        math2["import"] = load(importFactory);
        math2["config"] = load(configFactory);
        math2.expression.mathWithTransform["config"] = math2["config"];
        if (options) {
          math2.config(options);
        }
        return math2;
      };
    }
  });

  // node_modules/mathjs/core.js
  var require_core2 = __commonJS({
    "node_modules/mathjs/core.js"(exports, module) {
      module.exports = require_core();
    }
  });

  // node_modules/mathjs/lib/utils/collection/deepMap.js
  var require_deepMap = __commonJS({
    "node_modules/mathjs/lib/utils/collection/deepMap.js"(exports, module) {
      "use strict";
      module.exports = function deepMap(array, callback, skipZeros) {
        if (array && typeof array.map === "function") {
          return array.map(function(x) {
            return deepMap(x, callback, skipZeros);
          });
        } else {
          return callback(array);
        }
      };
    }
  });

  // node_modules/mathjs/lib/function/utils/typeof.js
  var require_typeof = __commonJS({
    "node_modules/mathjs/lib/function/utils/typeof.js"(exports) {
      "use strict";
      function _typeof2(obj) {
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof2 = function _typeof22(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof2 = function _typeof22(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof2(obj);
      }
      function factory(type, config, load, typed) {
        var _typeof = typed("_typeof", {
          "any": function any(x) {
            var t = _typeof2(x);
            if (t === "object") {
              if (x === null) return "null";
              if (Array.isArray(x)) return "Array";
              if (x instanceof Date) return "Date";
              if (x instanceof RegExp) return "RegExp";
              if (type.isBigNumber(x)) return "BigNumber";
              if (type.isComplex(x)) return "Complex";
              if (type.isFraction(x)) return "Fraction";
              if (type.isMatrix(x)) return "Matrix";
              if (type.isUnit(x)) return "Unit";
              if (type.isIndex(x)) return "Index";
              if (type.isRange(x)) return "Range";
              if (type.isResultSet(x)) return "ResultSet";
              if (type.isNode(x)) return x.type;
              if (type.isChain(x)) return "Chain";
              if (type.isHelp(x)) return "Help";
              return "Object";
            }
            if (t === "function") return "Function";
            return t;
          }
        });
        _typeof.toTex = void 0;
        return _typeof;
      }
      exports.name = "typeof";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/type/number.js
  var require_number2 = __commonJS({
    "node_modules/mathjs/lib/type/number.js"(exports) {
      "use strict";
      var deepMap = require_deepMap();
      function factory(type, config, load, typed) {
        var number = typed("number", {
          "": function _() {
            return 0;
          },
          "number": function number2(x) {
            return x;
          },
          "string": function string(x) {
            if (x === "NaN") return NaN;
            var num = Number(x);
            if (isNaN(num)) {
              throw new SyntaxError('String "' + x + '" is no valid number');
            }
            return num;
          },
          "BigNumber": function BigNumber(x) {
            return x.toNumber();
          },
          "Fraction": function Fraction(x) {
            return x.valueOf();
          },
          "Unit": function Unit(x) {
            throw new Error("Second argument with valueless unit expected");
          },
          "null": function _null(x) {
            return 0;
          },
          "Unit, string | Unit": function UnitStringUnit(unit, valuelessUnit) {
            return unit.toNumber(valuelessUnit);
          },
          "Array | Matrix": function ArrayMatrix(x) {
            return deepMap(x, number);
          }
        });
        number.toTex = {
          0: "0",
          1: "\\left(${args[0]}\\right)",
          2: "\\left(\\left(${args[0]}\\right)${args[1]}\\right)"
        };
        return number;
      }
      exports.name = "number";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/type/bignumber/function/bignumber.js
  var require_bignumber = __commonJS({
    "node_modules/mathjs/lib/type/bignumber/function/bignumber.js"(exports) {
      "use strict";
      var deepMap = require_deepMap();
      function factory(type, config, load, typed) {
        var bignumber = typed("bignumber", {
          "": function _() {
            return new type.BigNumber(0);
          },
          "number": function number(x) {
            return new type.BigNumber(x + "");
          },
          "string": function string(x) {
            return new type.BigNumber(x);
          },
          "BigNumber": function BigNumber(x) {
            return x;
          },
          "Fraction": function Fraction(x) {
            return new type.BigNumber(x.n).div(x.d).times(x.s);
          },
          "null": function _null(x) {
            return new type.BigNumber(0);
          },
          "Array | Matrix": function ArrayMatrix(x) {
            return deepMap(x, bignumber);
          }
        });
        bignumber.toTex = {
          0: "0",
          1: "\\left(${args[0]}\\right)"
        };
        return bignumber;
      }
      exports.name = "bignumber";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/type/fraction/function/fraction.js
  var require_fraction = __commonJS({
    "node_modules/mathjs/lib/type/fraction/function/fraction.js"(exports) {
      "use strict";
      var deepMap = require_deepMap();
      function factory(type, config, load, typed) {
        var fraction = typed("fraction", {
          "number": function number(x) {
            if (!isFinite(x) || isNaN(x)) {
              throw new Error(x + " cannot be represented as a fraction");
            }
            return new type.Fraction(x);
          },
          "string": function string(x) {
            return new type.Fraction(x);
          },
          "number, number": function numberNumber(numerator, denominator) {
            return new type.Fraction(numerator, denominator);
          },
          "null": function _null(x) {
            return new type.Fraction(0);
          },
          "BigNumber": function BigNumber(x) {
            return new type.Fraction(x.toString());
          },
          "Fraction": function Fraction(x) {
            return x;
          },
          "Object": function Object2(x) {
            return new type.Fraction(x);
          },
          "Array | Matrix": function ArrayMatrix(x) {
            return deepMap(x, fraction);
          }
        });
        return fraction;
      }
      exports.name = "fraction";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/type/numeric.js
  var require_numeric = __commonJS({
    "node_modules/mathjs/lib/type/numeric.js"(exports) {
      "use strict";
      function factory(type, config, load, typed) {
        var getTypeOf = load(require_typeof());
        var validInputTypes = {
          "string": true,
          "number": true,
          "BigNumber": true,
          "Fraction": true
          // Load the conversion functions for each output type
        };
        var validOutputTypes = {
          "number": load(require_number2()),
          "BigNumber": load(require_bignumber()),
          "Fraction": load(require_fraction())
          /**
           * Convert a numeric value to a specific type: number, BigNumber, or Fraction
           *
           * @param {string | number | BigNumber | Fraction } value
           * @param {'number' | 'BigNumber' | 'Fraction'} outputType
           * @return {number | BigNumber | Fraction} Returns an instance of the
           *                                         numeric in the requested type
           */
        };
        var numeric = function numeric2(value, outputType) {
          var inputType = getTypeOf(value);
          if (!(inputType in validInputTypes)) {
            throw new TypeError("Cannot convert " + value + ' of type "' + inputType + '"; valid input types are ' + Object.keys(validInputTypes).join(", "));
          }
          if (!(outputType in validOutputTypes)) {
            throw new TypeError("Cannot convert " + value + ' to type "' + outputType + '"; valid output types are ' + Object.keys(validOutputTypes).join(", "));
          }
          if (outputType === inputType) {
            return value;
          } else {
            return validOutputTypes[outputType](value);
          }
        };
        numeric.toTex = function(node, options) {
          return node.args[0].toTex();
        };
        return numeric;
      }
      exports.path = "type";
      exports.name = "_numeric";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/utils/customs.js
  var require_customs = __commonJS({
    "node_modules/mathjs/lib/utils/customs.js"(exports) {
      "use strict";
      function _typeof(obj) {
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      var hasOwnProperty = require_object().hasOwnProperty;
      function getSafeProperty(object, prop) {
        if (isPlainObject(object) && isSafeProperty(object, prop)) {
          return object[prop];
        }
        if (typeof object[prop] === "function" && isSafeMethod(object, prop)) {
          throw new Error('Cannot access method "' + prop + '" as a property');
        }
        throw new Error('No access to property "' + prop + '"');
      }
      function setSafeProperty(object, prop, value) {
        if (isPlainObject(object) && isSafeProperty(object, prop)) {
          object[prop] = value;
          return value;
        }
        throw new Error('No access to property "' + prop + '"');
      }
      function isSafeProperty(object, prop) {
        if (!object || _typeof(object) !== "object") {
          return false;
        }
        if (hasOwnProperty(safeNativeProperties, prop)) {
          return true;
        }
        if (prop in Object.prototype) {
          return false;
        }
        if (prop in Function.prototype) {
          return false;
        }
        return true;
      }
      function validateSafeMethod(object, method) {
        if (!isSafeMethod(object, method)) {
          throw new Error('No access to method "' + method + '"');
        }
      }
      function isSafeMethod(object, method) {
        if (!object || typeof object[method] !== "function") {
          return false;
        }
        if (hasOwnProperty(object, method) && Object.getPrototypeOf && method in Object.getPrototypeOf(object)) {
          return false;
        }
        if (hasOwnProperty(safeNativeMethods, method)) {
          return true;
        }
        if (method in Object.prototype) {
          return false;
        }
        if (method in Function.prototype) {
          return false;
        }
        return true;
      }
      function isPlainObject(object) {
        return _typeof(object) === "object" && object && object.constructor === Object;
      }
      var safeNativeProperties = {
        length: true,
        name: true
      };
      var safeNativeMethods = {
        toString: true,
        valueOf: true,
        toLocaleString: true
      };
      exports.getSafeProperty = getSafeProperty;
      exports.setSafeProperty = setSafeProperty;
      exports.isSafeProperty = isSafeProperty;
      exports.validateSafeMethod = validateSafeMethod;
      exports.isSafeMethod = isSafeMethod;
      exports.isPlainObject = isPlainObject;
    }
  });

  // node_modules/mathjs/lib/expression/keywords.js
  var require_keywords = __commonJS({
    "node_modules/mathjs/lib/expression/keywords.js"(exports, module) {
      "use strict";
      module.exports = {
        end: true
      };
    }
  });

  // node_modules/mathjs/lib/expression/node/Node.js
  var require_Node = __commonJS({
    "node_modules/mathjs/lib/expression/node/Node.js"(exports) {
      "use strict";
      function _typeof(obj) {
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      var keywords = require_keywords();
      var deepEqual = require_object().deepEqual;
      var hasOwnProperty = require_object().hasOwnProperty;
      function factory(type, config, load, typed, math2) {
        function Node() {
          if (!(this instanceof Node)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
        }
        Node.prototype.eval = function(scope) {
          return this.compile().eval(scope);
        };
        Node.prototype.type = "Node";
        Node.prototype.isNode = true;
        Node.prototype.comment = "";
        Node.prototype.compile = function() {
          var expr = this._compile(math2.expression.mathWithTransform, {});
          var args = {};
          var context = null;
          return {
            eval: function evalNode(scope) {
              var s = scope || {};
              _validateScope(s);
              return expr(s, args, context);
            }
          };
        };
        Node.prototype._compile = function(math3, argNames) {
          throw new Error("Method _compile should be implemented by type " + this.type);
        };
        Node.prototype.forEach = function(callback) {
          throw new Error("Cannot run forEach on a Node interface");
        };
        Node.prototype.map = function(callback) {
          throw new Error("Cannot run map on a Node interface");
        };
        Node.prototype._ifNode = function(node) {
          if (!type.isNode(node)) {
            throw new TypeError("Callback function must return a Node");
          }
          return node;
        };
        Node.prototype.traverse = function(callback) {
          callback(this, null, null);
          function _traverse(node, callback2) {
            node.forEach(function(child, path, parent) {
              callback2(child, path, parent);
              _traverse(child, callback2);
            });
          }
          _traverse(this, callback);
        };
        Node.prototype.transform = function(callback) {
          function _transform(node, callback2) {
            return node.map(function(child, path, parent) {
              var replacement2 = callback2(child, path, parent);
              return _transform(replacement2, callback2);
            });
          }
          var replacement = callback(this, null, null);
          return _transform(replacement, callback);
        };
        Node.prototype.filter = function(callback) {
          var nodes = [];
          this.traverse(function(node, path, parent) {
            if (callback(node, path, parent)) {
              nodes.push(node);
            }
          });
          return nodes;
        };
        Node.prototype.find = function() {
          throw new Error("Function Node.find is deprecated. Use Node.filter instead.");
        };
        Node.prototype.match = function() {
          throw new Error("Function Node.match is deprecated. See functions Node.filter, Node.transform, Node.traverse.");
        };
        Node.prototype.clone = function() {
          throw new Error("Cannot clone a Node interface");
        };
        Node.prototype.cloneDeep = function() {
          return this.map(function(node) {
            return node.cloneDeep();
          });
        };
        Node.prototype.equals = function(other) {
          return other ? deepEqual(this, other) : false;
        };
        Node.prototype.toString = function(options) {
          var customString;
          if (options && _typeof(options) === "object") {
            switch (_typeof(options.handler)) {
              case "object":
              case "undefined":
                break;
              case "function":
                customString = options.handler(this, options);
                break;
              default:
                throw new TypeError("Object or function expected as callback");
            }
          }
          if (typeof customString !== "undefined") {
            return customString;
          }
          return this._toString(options);
        };
        Node.prototype.toJSON = function() {
          throw new Error("Cannot serialize object: toJSON not implemented by " + this.type);
        };
        Node.prototype.toHTML = function(options) {
          var customString;
          if (options && _typeof(options) === "object") {
            switch (_typeof(options.handler)) {
              case "object":
              case "undefined":
                break;
              case "function":
                customString = options.handler(this, options);
                break;
              default:
                throw new TypeError("Object or function expected as callback");
            }
          }
          if (typeof customString !== "undefined") {
            return customString;
          }
          return this.toHTML(options);
        };
        Node.prototype._toString = function() {
          throw new Error("_toString not implemented for " + this.type);
        };
        Node.prototype.toTex = function(options) {
          var customTex;
          if (options && _typeof(options) === "object") {
            switch (_typeof(options.handler)) {
              case "object":
              case "undefined":
                break;
              case "function":
                customTex = options.handler(this, options);
                break;
              default:
                throw new TypeError("Object or function expected as callback");
            }
          }
          if (typeof customTex !== "undefined") {
            return customTex;
          }
          return this._toTex(options);
        };
        Node.prototype._toTex = function(options) {
          throw new Error("_toTex not implemented for " + this.type);
        };
        Node.prototype.getIdentifier = function() {
          return this.type;
        };
        Node.prototype.getContent = function() {
          return this;
        };
        function _validateScope(scope) {
          for (var symbol in scope) {
            if (hasOwnProperty(scope, symbol)) {
              if (symbol in keywords) {
                throw new Error('Scope contains an illegal symbol, "' + symbol + '" is a reserved keyword');
              }
            }
          }
        }
        return Node;
      }
      exports.name = "Node";
      exports.path = "expression.node";
      exports.math = true;
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/error/IndexError.js
  var require_IndexError = __commonJS({
    "node_modules/mathjs/lib/error/IndexError.js"(exports, module) {
      "use strict";
      function IndexError(index, min, max) {
        if (!(this instanceof IndexError)) {
          throw new SyntaxError("Constructor must be called with the new operator");
        }
        this.index = index;
        if (arguments.length < 3) {
          this.min = 0;
          this.max = min;
        } else {
          this.min = min;
          this.max = max;
        }
        if (this.min !== void 0 && this.index < this.min) {
          this.message = "Index out of range (" + this.index + " < " + this.min + ")";
        } else if (this.max !== void 0 && this.index >= this.max) {
          this.message = "Index out of range (" + this.index + " > " + (this.max - 1) + ")";
        } else {
          this.message = "Index out of range (" + this.index + ")";
        }
        this.stack = new Error().stack;
      }
      IndexError.prototype = new RangeError();
      IndexError.prototype.constructor = RangeError;
      IndexError.prototype.name = "IndexError";
      IndexError.prototype.isIndexError = true;
      module.exports = IndexError;
    }
  });

  // node_modules/mathjs/lib/expression/transform/error.transform.js
  var require_error_transform = __commonJS({
    "node_modules/mathjs/lib/expression/transform/error.transform.js"(exports) {
      "use strict";
      var IndexError = require_IndexError();
      exports.transform = function(err) {
        if (err && err.isIndexError) {
          return new IndexError(err.index + 1, err.min + 1, err.max !== void 0 ? err.max + 1 : void 0);
        }
        return err;
      };
    }
  });

  // node_modules/mathjs/lib/utils/bignumber/formatter.js
  var require_formatter = __commonJS({
    "node_modules/mathjs/lib/utils/bignumber/formatter.js"(exports) {
      "use strict";
      var objectUtils = require_object();
      exports.format = function(value, options) {
        if (typeof options === "function") {
          return options(value);
        }
        if (!value.isFinite()) {
          return value.isNaN() ? "NaN" : value.gt(0) ? "Infinity" : "-Infinity";
        }
        var notation = "auto";
        var precision;
        if (options !== void 0) {
          if (options.notation) {
            notation = options.notation;
          }
          if (typeof options === "number") {
            precision = options;
          } else if (options.precision) {
            precision = options.precision;
          }
        }
        switch (notation) {
          case "fixed":
            return exports.toFixed(value, precision);
          case "exponential":
            return exports.toExponential(value, precision);
          case "engineering":
            return exports.toEngineering(value, precision);
          case "auto":
            if (options && options.exponential && (options.exponential.lower !== void 0 || options.exponential.upper !== void 0)) {
              var fixedOptions = objectUtils.map(options, function(x) {
                return x;
              });
              fixedOptions.exponential = void 0;
              if (options.exponential.lower !== void 0) {
                fixedOptions.lowerExp = Math.round(Math.log(options.exponential.lower) / Math.LN10);
              }
              if (options.exponential.upper !== void 0) {
                fixedOptions.upperExp = Math.round(Math.log(options.exponential.upper) / Math.LN10);
              }
              console.warn("Deprecation warning: Formatting options exponential.lower and exponential.upper (minimum and maximum value) are replaced with exponential.lowerExp and exponential.upperExp (minimum and maximum exponent) since version 4.0.0. Replace " + JSON.stringify(options) + " with " + JSON.stringify(fixedOptions));
              return exports.format(value, fixedOptions);
            }
            var lowerExp = options && options.lowerExp !== void 0 ? options.lowerExp : -3;
            var upperExp = options && options.upperExp !== void 0 ? options.upperExp : 5;
            if (value.isZero()) return "0";
            var str;
            var exp = value.e;
            if (exp >= lowerExp && exp < upperExp) {
              str = value.toSignificantDigits(precision).toFixed();
            } else {
              str = exports.toExponential(value, precision);
            }
            return str.replace(/((\.\d*?)(0+))($|e)/, function() {
              var digits = arguments[2];
              var e = arguments[4];
              return digits !== "." ? digits + e : e;
            });
          default:
            throw new Error('Unknown notation "' + notation + '". Choose "auto", "exponential", or "fixed".');
        }
      };
      exports.toEngineering = function(value, precision) {
        var e = value.e;
        var newExp = e % 3 === 0 ? e : e < 0 ? e - 3 - e % 3 : e - e % 3;
        var valueWithoutExp = value.mul(Math.pow(10, -newExp));
        var valueStr = valueWithoutExp.toPrecision(precision);
        if (valueStr.indexOf("e") !== -1) {
          valueStr = valueWithoutExp.toString();
        }
        return valueStr + "e" + (e >= 0 ? "+" : "") + newExp.toString();
      };
      exports.toExponential = function(value, precision) {
        if (precision !== void 0) {
          return value.toExponential(precision - 1);
        } else {
          return value.toExponential();
        }
      };
      exports.toFixed = function(value, precision) {
        return value.toFixed(precision);
      };
    }
  });

  // node_modules/mathjs/lib/utils/string.js
  var require_string = __commonJS({
    "node_modules/mathjs/lib/utils/string.js"(exports) {
      "use strict";
      function _typeof(obj) {
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      var formatNumber = require_number().format;
      var formatBigNumber = require_formatter().format;
      var isBigNumber = require_isBigNumber();
      exports.isString = function(value) {
        return typeof value === "string";
      };
      exports.endsWith = function(text, search) {
        var start = text.length - search.length;
        var end = text.length;
        return text.substring(start, end) === search;
      };
      exports.format = function(value, options) {
        if (typeof value === "number") {
          return formatNumber(value, options);
        }
        if (isBigNumber(value)) {
          return formatBigNumber(value, options);
        }
        if (looksLikeFraction(value)) {
          if (!options || options.fraction !== "decimal") {
            return value.s * value.n + "/" + value.d;
          } else {
            return value.toString();
          }
        }
        if (Array.isArray(value)) {
          return formatArray(value, options);
        }
        if (exports.isString(value)) {
          return '"' + value + '"';
        }
        if (typeof value === "function") {
          return value.syntax ? String(value.syntax) : "function";
        }
        if (value && _typeof(value) === "object") {
          if (typeof value.format === "function") {
            return value.format(options);
          } else if (value && value.toString() !== {}.toString()) {
            return value.toString();
          } else {
            var entries = [];
            for (var key in value) {
              if (value.hasOwnProperty(key)) {
                entries.push('"' + key + '": ' + exports.format(value[key], options));
              }
            }
            return "{" + entries.join(", ") + "}";
          }
        }
        return String(value);
      };
      exports.stringify = function(value) {
        var text = String(value);
        var escaped = "";
        var i = 0;
        while (i < text.length) {
          var c = text.charAt(i);
          if (c === "\\") {
            escaped += c;
            i++;
            c = text.charAt(i);
            if (c === "" || '"\\/bfnrtu'.indexOf(c) === -1) {
              escaped += "\\";
            }
            escaped += c;
          } else if (c === '"') {
            escaped += '\\"';
          } else {
            escaped += c;
          }
          i++;
        }
        return '"' + escaped + '"';
      };
      exports.escape = function(value) {
        var text = String(value);
        text = text.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/'/g, "&#39;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return text;
      };
      function formatArray(array, options) {
        if (Array.isArray(array)) {
          var str = "[";
          var len = array.length;
          for (var i = 0; i < len; i++) {
            if (i !== 0) {
              str += ", ";
            }
            str += formatArray(array[i], options);
          }
          str += "]";
          return str;
        } else {
          return exports.format(array, options);
        }
      }
      function looksLikeFraction(value) {
        return value && _typeof(value) === "object" && typeof value.s === "number" && typeof value.n === "number" && typeof value.d === "number" || false;
      }
    }
  });

  // node_modules/mathjs/lib/error/DimensionError.js
  var require_DimensionError = __commonJS({
    "node_modules/mathjs/lib/error/DimensionError.js"(exports, module) {
      "use strict";
      function DimensionError(actual, expected, relation) {
        if (!(this instanceof DimensionError)) {
          throw new SyntaxError("Constructor must be called with the new operator");
        }
        this.actual = actual;
        this.expected = expected;
        this.relation = relation;
        this.message = "Dimension mismatch (" + (Array.isArray(actual) ? "[" + actual.join(", ") + "]" : actual) + " " + (this.relation || "!=") + " " + (Array.isArray(expected) ? "[" + expected.join(", ") + "]" : expected) + ")";
        this.stack = new Error().stack;
      }
      DimensionError.prototype = new RangeError();
      DimensionError.prototype.constructor = RangeError;
      DimensionError.prototype.name = "DimensionError";
      DimensionError.prototype.isDimensionError = true;
      module.exports = DimensionError;
    }
  });

  // node_modules/mathjs/lib/utils/array.js
  var require_array = __commonJS({
    "node_modules/mathjs/lib/utils/array.js"(exports) {
      "use strict";
      Object.defineProperty(exports, "__esModule", {
        value: true
      });
      exports.size = size;
      exports.validate = validate;
      exports.validateIndex = validateIndex;
      exports.resize = resize;
      exports.reshape = reshape;
      exports.squeeze = squeeze;
      exports.unsqueeze = unsqueeze;
      exports.flatten = flatten;
      exports.map = map;
      exports.forEach = forEach;
      exports.filter = filter;
      exports.filterRegExp = filterRegExp;
      exports.join = join;
      exports.identify = identify;
      exports.generalize = generalize;
      var _number = _interopRequireDefault(require_number());
      var _string = _interopRequireDefault(require_string());
      var _DimensionError = _interopRequireDefault(require_DimensionError());
      var _IndexError = _interopRequireDefault(require_IndexError());
      function _interopRequireDefault(obj) {
        return obj && obj.__esModule ? obj : { "default": obj };
      }
      function size(x) {
        var s = [];
        while (Array.isArray(x)) {
          s.push(x.length);
          x = x[0];
        }
        return s;
      }
      function _validate(array, size2, dim) {
        var i;
        var len = array.length;
        if (len !== size2[dim]) {
          throw new _DimensionError["default"](len, size2[dim]);
        }
        if (dim < size2.length - 1) {
          var dimNext = dim + 1;
          for (i = 0; i < len; i++) {
            var child = array[i];
            if (!Array.isArray(child)) {
              throw new _DimensionError["default"](size2.length - 1, size2.length, "<");
            }
            _validate(array[i], size2, dimNext);
          }
        } else {
          for (i = 0; i < len; i++) {
            if (Array.isArray(array[i])) {
              throw new _DimensionError["default"](size2.length + 1, size2.length, ">");
            }
          }
        }
      }
      function validate(array, size2) {
        var isScalar = size2.length === 0;
        if (isScalar) {
          if (Array.isArray(array)) {
            throw new _DimensionError["default"](array.length, 0);
          }
        } else {
          _validate(array, size2, 0);
        }
      }
      function validateIndex(index, length) {
        if (!_number["default"].isNumber(index) || !_number["default"].isInteger(index)) {
          throw new TypeError("Index must be an integer (value: " + index + ")");
        }
        if (index < 0 || typeof length === "number" && index >= length) {
          throw new _IndexError["default"](index, length);
        }
      }
      function resize(array, size2, defaultValue) {
        if (!Array.isArray(array) || !Array.isArray(size2)) {
          throw new TypeError("Array expected");
        }
        if (size2.length === 0) {
          throw new Error("Resizing to scalar is not supported");
        }
        size2.forEach(function(value) {
          if (!_number["default"].isNumber(value) || !_number["default"].isInteger(value) || value < 0) {
            throw new TypeError("Invalid size, must contain positive integers (size: " + _string["default"].format(size2) + ")");
          }
        });
        var _defaultValue = defaultValue !== void 0 ? defaultValue : 0;
        _resize(array, size2, 0, _defaultValue);
        return array;
      }
      function _resize(array, size2, dim, defaultValue) {
        var i;
        var elem;
        var oldLen = array.length;
        var newLen = size2[dim];
        var minLen = Math.min(oldLen, newLen);
        array.length = newLen;
        if (dim < size2.length - 1) {
          var dimNext = dim + 1;
          for (i = 0; i < minLen; i++) {
            elem = array[i];
            if (!Array.isArray(elem)) {
              elem = [elem];
              array[i] = elem;
            }
            _resize(elem, size2, dimNext, defaultValue);
          }
          for (i = minLen; i < newLen; i++) {
            elem = [];
            array[i] = elem;
            _resize(elem, size2, dimNext, defaultValue);
          }
        } else {
          for (i = 0; i < minLen; i++) {
            while (Array.isArray(array[i])) {
              array[i] = array[i][0];
            }
          }
          for (i = minLen; i < newLen; i++) {
            array[i] = defaultValue;
          }
        }
      }
      function reshape(array, sizes) {
        var flatArray = flatten(array);
        var newArray;
        function product(arr) {
          return arr.reduce(function(prev, curr) {
            return prev * curr;
          });
        }
        if (!Array.isArray(array) || !Array.isArray(sizes)) {
          throw new TypeError("Array expected");
        }
        if (sizes.length === 0) {
          throw new _DimensionError["default"](0, product(size(array)), "!=");
        }
        var totalSize = 1;
        for (var sizeIndex = 0; sizeIndex < sizes.length; sizeIndex++) {
          totalSize *= sizes[sizeIndex];
        }
        if (flatArray.length !== totalSize) {
          throw new _DimensionError["default"](product(sizes), product(size(array)), "!=");
        }
        try {
          newArray = _reshape(flatArray, sizes);
        } catch (e) {
          if (e instanceof _DimensionError["default"]) {
            throw new _DimensionError["default"](product(sizes), product(size(array)), "!=");
          }
          throw e;
        }
        return newArray;
      }
      function _reshape(array, sizes) {
        var tmpArray = array;
        var tmpArray2;
        for (var sizeIndex = sizes.length - 1; sizeIndex > 0; sizeIndex--) {
          var size2 = sizes[sizeIndex];
          tmpArray2 = [];
          var length = tmpArray.length / size2;
          for (var i = 0; i < length; i++) {
            tmpArray2.push(tmpArray.slice(i * size2, (i + 1) * size2));
          }
          tmpArray = tmpArray2;
        }
        return tmpArray;
      }
      function squeeze(array, arraySize) {
        var s = arraySize || size(array);
        while (Array.isArray(array) && array.length === 1) {
          array = array[0];
          s.shift();
        }
        var dims = s.length;
        while (s[dims - 1] === 1) {
          dims--;
        }
        if (dims < s.length) {
          array = _squeeze(array, dims, 0);
          s.length = dims;
        }
        return array;
      }
      function _squeeze(array, dims, dim) {
        var i, ii;
        if (dim < dims) {
          var next = dim + 1;
          for (i = 0, ii = array.length; i < ii; i++) {
            array[i] = _squeeze(array[i], dims, next);
          }
        } else {
          while (Array.isArray(array)) {
            array = array[0];
          }
        }
        return array;
      }
      function unsqueeze(array, dims, outer, arraySize) {
        var s = arraySize || size(array);
        if (outer) {
          for (var i = 0; i < outer; i++) {
            array = [array];
            s.unshift(1);
          }
        }
        array = _unsqueeze(array, dims, 0);
        while (s.length < dims) {
          s.push(1);
        }
        return array;
      }
      function _unsqueeze(array, dims, dim) {
        var i, ii;
        if (Array.isArray(array)) {
          var next = dim + 1;
          for (i = 0, ii = array.length; i < ii; i++) {
            array[i] = _unsqueeze(array[i], dims, next);
          }
        } else {
          for (var d = dim; d < dims; d++) {
            array = [array];
          }
        }
        return array;
      }
      function flatten(array) {
        if (!Array.isArray(array)) {
          return array;
        }
        var flat = [];
        array.forEach(function callback(value) {
          if (Array.isArray(value)) {
            value.forEach(callback);
          } else {
            flat.push(value);
          }
        });
        return flat;
      }
      function map(array, callback) {
        return Array.prototype.map.call(array, callback);
      }
      function forEach(array, callback) {
        Array.prototype.forEach.call(array, callback);
      }
      function filter(array, callback) {
        if (size(array).length !== 1) {
          throw new Error("Only one dimensional matrices supported");
        }
        return Array.prototype.filter.call(array, callback);
      }
      function filterRegExp(array, regexp) {
        if (size(array).length !== 1) {
          throw new Error("Only one dimensional matrices supported");
        }
        return Array.prototype.filter.call(array, function(entry) {
          return regexp.test(entry);
        });
      }
      function join(array, separator) {
        return Array.prototype.join.call(array, separator);
      }
      function identify(a) {
        if (!Array.isArray(a)) {
          throw new TypeError("Array input expected");
        }
        if (a.length === 0) {
          return a;
        }
        var b = [];
        var count = 0;
        b[0] = {
          value: a[0],
          identifier: 0
        };
        for (var i = 1; i < a.length; i++) {
          if (a[i] === a[i - 1]) {
            count++;
          } else {
            count = 0;
          }
          b.push({
            value: a[i],
            identifier: count
          });
        }
        return b;
      }
      function generalize(a) {
        if (!Array.isArray(a)) {
          throw new TypeError("Array input expected");
        }
        if (a.length === 0) {
          return a;
        }
        var b = [];
        for (var i = 0; i < a.length; i++) {
          b.push(a[i].value);
        }
        return b;
      }
    }
  });

  // node_modules/mathjs/lib/type/matrix/function/matrix.js
  var require_matrix = __commonJS({
    "node_modules/mathjs/lib/type/matrix/function/matrix.js"(exports) {
      "use strict";
      function factory(type, config, load, typed) {
        var matrix = typed("matrix", {
          "": function _() {
            return _create([]);
          },
          "string": function string(format) {
            return _create([], format);
          },
          "string, string": function stringString(format, datatype) {
            return _create([], format, datatype);
          },
          "Array": function Array2(data) {
            return _create(data);
          },
          "Matrix": function Matrix(data) {
            return _create(data, data.storage());
          },
          "Array | Matrix, string": _create,
          "Array | Matrix, string, string": _create
        });
        matrix.toTex = {
          0: "\\begin{bmatrix}\\end{bmatrix}",
          1: "\\left(${args[0]}\\right)",
          2: "\\left(${args[0]}\\right)"
        };
        return matrix;
        function _create(data, format, datatype) {
          var M = type.Matrix.storage(format || "default");
          return new M(data, datatype);
        }
      }
      exports.name = "matrix";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/function/matrix/subset.js
  var require_subset = __commonJS({
    "node_modules/mathjs/lib/function/matrix/subset.js"(exports) {
      "use strict";
      var clone = require_object().clone;
      var validateIndex = require_array().validateIndex;
      var getSafeProperty = require_customs().getSafeProperty;
      var setSafeProperty = require_customs().setSafeProperty;
      var DimensionError = require_DimensionError();
      function factory(type, config, load, typed) {
        var matrix = load(require_matrix());
        var subset = typed("subset", {
          // get subset
          "Array, Index": function ArrayIndex(value, index) {
            var m = matrix(value);
            var subset2 = m.subset(index);
            return index.isScalar() ? subset2 : subset2.valueOf();
          },
          "Matrix, Index": function MatrixIndex(value, index) {
            return value.subset(index);
          },
          "Object, Index": _getObjectProperty,
          "string, Index": _getSubstring,
          // set subset
          "Array, Index, any": function ArrayIndexAny(value, index, replacement) {
            return matrix(clone(value)).subset(index, replacement, void 0).valueOf();
          },
          "Array, Index, any, any": function ArrayIndexAnyAny(value, index, replacement, defaultValue) {
            return matrix(clone(value)).subset(index, replacement, defaultValue).valueOf();
          },
          "Matrix, Index, any": function MatrixIndexAny(value, index, replacement) {
            return value.clone().subset(index, replacement);
          },
          "Matrix, Index, any, any": function MatrixIndexAnyAny(value, index, replacement, defaultValue) {
            return value.clone().subset(index, replacement, defaultValue);
          },
          "string, Index, string": _setSubstring,
          "string, Index, string, string": _setSubstring,
          "Object, Index, any": _setObjectProperty
        });
        subset.toTex = void 0;
        return subset;
        function _getSubstring(str, index) {
          if (!type.isIndex(index)) {
            throw new TypeError("Index expected");
          }
          if (index.size().length !== 1) {
            throw new DimensionError(index.size().length, 1);
          }
          var strLen = str.length;
          validateIndex(index.min()[0], strLen);
          validateIndex(index.max()[0], strLen);
          var range = index.dimension(0);
          var substr = "";
          range.forEach(function(v) {
            substr += str.charAt(v);
          });
          return substr;
        }
        function _setSubstring(str, index, replacement, defaultValue) {
          if (!index || index.isIndex !== true) {
            throw new TypeError("Index expected");
          }
          if (index.size().length !== 1) {
            throw new DimensionError(index.size().length, 1);
          }
          if (defaultValue !== void 0) {
            if (typeof defaultValue !== "string" || defaultValue.length !== 1) {
              throw new TypeError("Single character expected as defaultValue");
            }
          } else {
            defaultValue = " ";
          }
          var range = index.dimension(0);
          var len = range.size()[0];
          if (len !== replacement.length) {
            throw new DimensionError(range.size()[0], replacement.length);
          }
          var strLen = str.length;
          validateIndex(index.min()[0]);
          validateIndex(index.max()[0]);
          var chars = [];
          for (var i = 0; i < strLen; i++) {
            chars[i] = str.charAt(i);
          }
          range.forEach(function(v, i2) {
            chars[v] = replacement.charAt(i2[0]);
          });
          if (chars.length > strLen) {
            for (var _i = strLen - 1, _len = chars.length; _i < _len; _i++) {
              if (!chars[_i]) {
                chars[_i] = defaultValue;
              }
            }
          }
          return chars.join("");
        }
      }
      function _getObjectProperty(object, index) {
        if (index.size().length !== 1) {
          throw new DimensionError(index.size(), 1);
        }
        var key = index.dimension(0);
        if (typeof key !== "string") {
          throw new TypeError("String expected as index to retrieve an object property");
        }
        return getSafeProperty(object, key);
      }
      function _setObjectProperty(object, index, replacement) {
        if (index.size().length !== 1) {
          throw new DimensionError(index.size(), 1);
        }
        var key = index.dimension(0);
        if (typeof key !== "string") {
          throw new TypeError("String expected as index to retrieve an object property");
        }
        var updated = clone(object);
        setSafeProperty(updated, key, replacement);
        return updated;
      }
      exports.name = "subset";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/utils/access.js
  var require_access = __commonJS({
    "node_modules/mathjs/lib/expression/node/utils/access.js"(exports) {
      "use strict";
      function _typeof(obj) {
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      var errorTransform = require_error_transform().transform;
      var getSafeProperty = require_customs().getSafeProperty;
      function factory(type, config, load, typed) {
        var subset = load(require_subset());
        return function access(object, index) {
          try {
            if (Array.isArray(object)) {
              return subset(object, index);
            } else if (object && typeof object.subset === "function") {
              return object.subset(index);
            } else if (typeof object === "string") {
              return subset(object, index);
            } else if (_typeof(object) === "object") {
              if (!index.isObjectProperty()) {
                throw new TypeError("Cannot apply a numeric index as object property");
              }
              return getSafeProperty(object, index.getObjectProperty());
            } else {
              throw new TypeError("Cannot apply index: unsupported type of object");
            }
          } catch (err) {
            throw errorTransform(err);
          }
        };
      }
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/AccessorNode.js
  var require_AccessorNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/AccessorNode.js"(exports) {
      "use strict";
      var getSafeProperty = require_customs().getSafeProperty;
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        var access = load(require_access());
        function AccessorNode(object, index) {
          if (!(this instanceof AccessorNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          if (!type.isNode(object)) {
            throw new TypeError('Node expected for parameter "object"');
          }
          if (!type.isIndexNode(index)) {
            throw new TypeError('IndexNode expected for parameter "index"');
          }
          this.object = object || null;
          this.index = index;
          Object.defineProperty(this, "name", {
            get: function() {
              if (this.index) {
                return this.index.isObjectProperty() ? this.index.getObjectProperty() : "";
              } else {
                return this.object.name || "";
              }
            }.bind(this),
            set: function set() {
              throw new Error("Cannot assign a new name, name is read-only");
            }
          });
        }
        AccessorNode.prototype = new Node();
        AccessorNode.prototype.type = "AccessorNode";
        AccessorNode.prototype.isAccessorNode = true;
        AccessorNode.prototype._compile = function(math2, argNames) {
          var evalObject = this.object._compile(math2, argNames);
          var evalIndex = this.index._compile(math2, argNames);
          if (this.index.isObjectProperty()) {
            var prop = this.index.getObjectProperty();
            return function evalAccessorNode(scope, args, context) {
              return getSafeProperty(evalObject(scope, args, context), prop);
            };
          } else {
            return function evalAccessorNode(scope, args, context) {
              var object = evalObject(scope, args, context);
              var index = evalIndex(scope, args, object);
              return access(object, index);
            };
          }
        };
        AccessorNode.prototype.forEach = function(callback) {
          callback(this.object, "object", this);
          callback(this.index, "index", this);
        };
        AccessorNode.prototype.map = function(callback) {
          return new AccessorNode(this._ifNode(callback(this.object, "object", this)), this._ifNode(callback(this.index, "index", this)));
        };
        AccessorNode.prototype.clone = function() {
          return new AccessorNode(this.object, this.index);
        };
        AccessorNode.prototype._toString = function(options) {
          var object = this.object.toString(options);
          if (needParenthesis(this.object)) {
            object = "(" + object + ")";
          }
          return object + this.index.toString(options);
        };
        AccessorNode.prototype.toHTML = function(options) {
          var object = this.object.toHTML(options);
          if (needParenthesis(this.object)) {
            object = '<span class="math-parenthesis math-round-parenthesis">(</span>' + object + '<span class="math-parenthesis math-round-parenthesis">)</span>';
          }
          return object + this.index.toHTML(options);
        };
        AccessorNode.prototype._toTex = function(options) {
          var object = this.object.toTex(options);
          if (needParenthesis(this.object)) {
            object = "\\left(' + object + '\\right)";
          }
          return object + this.index.toTex(options);
        };
        AccessorNode.prototype.toJSON = function() {
          return {
            mathjs: "AccessorNode",
            object: this.object,
            index: this.index
          };
        };
        AccessorNode.fromJSON = function(json) {
          return new AccessorNode(json.object, json.index);
        };
        function needParenthesis(node) {
          return !(type.isAccessorNode(node) || type.isArrayNode(node) || type.isConstantNode(node) || type.isFunctionNode(node) || type.isObjectNode(node) || type.isParenthesisNode(node) || type.isSymbolNode(node));
        }
        return AccessorNode;
      }
      exports.name = "AccessorNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/ArrayNode.js
  var require_ArrayNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/ArrayNode.js"(exports) {
      "use strict";
      var map = require_array().map;
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        function ArrayNode(items) {
          if (!(this instanceof ArrayNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          this.items = items || [];
          if (!Array.isArray(this.items) || !this.items.every(type.isNode)) {
            throw new TypeError("Array containing Nodes expected");
          }
          var deprecated = function deprecated2() {
            throw new Error("Property `ArrayNode.nodes` is deprecated, use `ArrayNode.items` instead");
          };
          Object.defineProperty(this, "nodes", {
            get: deprecated,
            set: deprecated
          });
        }
        ArrayNode.prototype = new Node();
        ArrayNode.prototype.type = "ArrayNode";
        ArrayNode.prototype.isArrayNode = true;
        ArrayNode.prototype._compile = function(math2, argNames) {
          var evalItems = map(this.items, function(item) {
            return item._compile(math2, argNames);
          });
          var asMatrix = math2.config().matrix !== "Array";
          if (asMatrix) {
            var matrix = math2.matrix;
            return function evalArrayNode(scope, args, context) {
              return matrix(map(evalItems, function(evalItem) {
                return evalItem(scope, args, context);
              }));
            };
          } else {
            return function evalArrayNode(scope, args, context) {
              return map(evalItems, function(evalItem) {
                return evalItem(scope, args, context);
              });
            };
          }
        };
        ArrayNode.prototype.forEach = function(callback) {
          for (var i = 0; i < this.items.length; i++) {
            var node = this.items[i];
            callback(node, "items[" + i + "]", this);
          }
        };
        ArrayNode.prototype.map = function(callback) {
          var items = [];
          for (var i = 0; i < this.items.length; i++) {
            items[i] = this._ifNode(callback(this.items[i], "items[" + i + "]", this));
          }
          return new ArrayNode(items);
        };
        ArrayNode.prototype.clone = function() {
          return new ArrayNode(this.items.slice(0));
        };
        ArrayNode.prototype._toString = function(options) {
          var items = this.items.map(function(node) {
            return node.toString(options);
          });
          return "[" + items.join(", ") + "]";
        };
        ArrayNode.prototype.toJSON = function() {
          return {
            mathjs: "ArrayNode",
            items: this.items
          };
        };
        ArrayNode.fromJSON = function(json) {
          return new ArrayNode(json.items);
        };
        ArrayNode.prototype.toHTML = function(options) {
          var items = this.items.map(function(node) {
            return node.toHTML(options);
          });
          return '<span class="math-parenthesis math-square-parenthesis">[</span>' + items.join('<span class="math-separator">,</span>') + '<span class="math-parenthesis math-square-parenthesis">]</span>';
        };
        ArrayNode.prototype._toTex = function(options) {
          var s = "\\begin{bmatrix}";
          this.items.forEach(function(node) {
            if (node.items) {
              s += node.items.map(function(childNode) {
                return childNode.toTex(options);
              }).join("&");
            } else {
              s += node.toTex(options);
            }
            s += "\\\\";
          });
          s += "\\end{bmatrix}";
          return s;
        };
        return ArrayNode;
      }
      exports.name = "ArrayNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/utils/assign.js
  var require_assign = __commonJS({
    "node_modules/mathjs/lib/expression/node/utils/assign.js"(exports) {
      "use strict";
      function _typeof(obj) {
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      var errorTransform = require_error_transform().transform;
      var setSafeProperty = require_customs().setSafeProperty;
      function factory(type, config, load, typed) {
        var subset = load(require_subset());
        var matrix = load(require_matrix());
        return function assign(object, index, value) {
          try {
            if (Array.isArray(object)) {
              return matrix(object).subset(index, value).valueOf();
            } else if (object && typeof object.subset === "function") {
              return object.subset(index, value);
            } else if (typeof object === "string") {
              return subset(object, index, value);
            } else if (_typeof(object) === "object") {
              if (!index.isObjectProperty()) {
                throw TypeError("Cannot apply a numeric index as object property");
              }
              setSafeProperty(object, index.getObjectProperty(), value);
              return object;
            } else {
              throw new TypeError("Cannot apply index: unsupported type of object");
            }
          } catch (err) {
            throw errorTransform(err);
          }
        };
      }
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/operators.js
  var require_operators = __commonJS({
    "node_modules/mathjs/lib/expression/operators.js"(exports, module) {
      "use strict";
      var properties = [{
        // assignment
        "AssignmentNode": {},
        "FunctionAssignmentNode": {}
      }, {
        // conditional expression
        "ConditionalNode": {
          latexLeftParens: false,
          latexRightParens: false,
          latexParens: false
          // conditionals don't need parentheses in LaTeX because
          // they are 2 dimensional
        }
      }, {
        // logical or
        "OperatorNode:or": {
          associativity: "left",
          associativeWith: []
        }
      }, {
        // logical xor
        "OperatorNode:xor": {
          associativity: "left",
          associativeWith: []
        }
      }, {
        // logical and
        "OperatorNode:and": {
          associativity: "left",
          associativeWith: []
        }
      }, {
        // bitwise or
        "OperatorNode:bitOr": {
          associativity: "left",
          associativeWith: []
        }
      }, {
        // bitwise xor
        "OperatorNode:bitXor": {
          associativity: "left",
          associativeWith: []
        }
      }, {
        // bitwise and
        "OperatorNode:bitAnd": {
          associativity: "left",
          associativeWith: []
        }
      }, {
        // relational operators
        "OperatorNode:equal": {
          associativity: "left",
          associativeWith: []
        },
        "OperatorNode:unequal": {
          associativity: "left",
          associativeWith: []
        },
        "OperatorNode:smaller": {
          associativity: "left",
          associativeWith: []
        },
        "OperatorNode:larger": {
          associativity: "left",
          associativeWith: []
        },
        "OperatorNode:smallerEq": {
          associativity: "left",
          associativeWith: []
        },
        "OperatorNode:largerEq": {
          associativity: "left",
          associativeWith: []
        },
        "RelationalNode": {
          associativity: "left",
          associativeWith: []
        }
      }, {
        // bitshift operators
        "OperatorNode:leftShift": {
          associativity: "left",
          associativeWith: []
        },
        "OperatorNode:rightArithShift": {
          associativity: "left",
          associativeWith: []
        },
        "OperatorNode:rightLogShift": {
          associativity: "left",
          associativeWith: []
        }
      }, {
        // unit conversion
        "OperatorNode:to": {
          associativity: "left",
          associativeWith: []
        }
      }, {
        // range
        "RangeNode": {}
      }, {
        // addition, subtraction
        "OperatorNode:add": {
          associativity: "left",
          associativeWith: ["OperatorNode:add", "OperatorNode:subtract"]
        },
        "OperatorNode:subtract": {
          associativity: "left",
          associativeWith: []
        }
      }, {
        // multiply, divide, modulus
        "OperatorNode:multiply": {
          associativity: "left",
          associativeWith: ["OperatorNode:multiply", "OperatorNode:divide", "Operator:dotMultiply", "Operator:dotDivide"]
        },
        "OperatorNode:divide": {
          associativity: "left",
          associativeWith: [],
          latexLeftParens: false,
          latexRightParens: false,
          latexParens: false
          // fractions don't require parentheses because
          // they're 2 dimensional, so parens aren't needed
          // in LaTeX
        },
        "OperatorNode:dotMultiply": {
          associativity: "left",
          associativeWith: ["OperatorNode:multiply", "OperatorNode:divide", "OperatorNode:dotMultiply", "OperatorNode:doDivide"]
        },
        "OperatorNode:dotDivide": {
          associativity: "left",
          associativeWith: []
        },
        "OperatorNode:mod": {
          associativity: "left",
          associativeWith: []
        }
      }, {
        // unary prefix operators
        "OperatorNode:unaryPlus": {
          associativity: "right"
        },
        "OperatorNode:unaryMinus": {
          associativity: "right"
        },
        "OperatorNode:bitNot": {
          associativity: "right"
        },
        "OperatorNode:not": {
          associativity: "right"
        }
      }, {
        // exponentiation
        "OperatorNode:pow": {
          associativity: "right",
          associativeWith: [],
          latexRightParens: false
          // the exponent doesn't need parentheses in
          // LaTeX because it's 2 dimensional
          // (it's on top)
        },
        "OperatorNode:dotPow": {
          associativity: "right",
          associativeWith: []
        }
      }, {
        // factorial
        "OperatorNode:factorial": {
          associativity: "left"
        }
      }, {
        // matrix transpose
        "OperatorNode:transpose": {
          associativity: "left"
        }
      }];
      function getPrecedence(_node, parenthesis) {
        var node = _node;
        if (parenthesis !== "keep") {
          node = _node.getContent();
        }
        var identifier = node.getIdentifier();
        for (var i = 0; i < properties.length; i++) {
          if (identifier in properties[i]) {
            return i;
          }
        }
        return null;
      }
      function getAssociativity(_node, parenthesis) {
        var node = _node;
        if (parenthesis !== "keep") {
          node = _node.getContent();
        }
        var identifier = node.getIdentifier();
        var index = getPrecedence(node, parenthesis);
        if (index === null) {
          return null;
        }
        var property = properties[index][identifier];
        if (property.hasOwnProperty("associativity")) {
          if (property.associativity === "left") {
            return "left";
          }
          if (property.associativity === "right") {
            return "right";
          }
          throw Error("'" + identifier + "' has the invalid associativity '" + property.associativity + "'.");
        }
        return null;
      }
      function isAssociativeWith(nodeA, nodeB, parenthesis) {
        var a = parenthesis !== "keep" ? nodeA.getContent() : nodeA;
        var b = parenthesis !== "keep" ? nodeA.getContent() : nodeB;
        var identifierA = a.getIdentifier();
        var identifierB = b.getIdentifier();
        var index = getPrecedence(a, parenthesis);
        if (index === null) {
          return null;
        }
        var property = properties[index][identifierA];
        if (property.hasOwnProperty("associativeWith") && property.associativeWith instanceof Array) {
          for (var i = 0; i < property.associativeWith.length; i++) {
            if (property.associativeWith[i] === identifierB) {
              return true;
            }
          }
          return false;
        }
        return null;
      }
      module.exports.properties = properties;
      module.exports.getPrecedence = getPrecedence;
      module.exports.getAssociativity = getAssociativity;
      module.exports.isAssociativeWith = isAssociativeWith;
    }
  });

  // node_modules/mathjs/lib/expression/node/AssignmentNode.js
  var require_AssignmentNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/AssignmentNode.js"(exports) {
      "use strict";
      var getSafeProperty = require_customs().getSafeProperty;
      var setSafeProperty = require_customs().setSafeProperty;
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        var assign = load(require_assign());
        var access = load(require_access());
        var operators = require_operators();
        function AssignmentNode(object, index, value) {
          if (!(this instanceof AssignmentNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          this.object = object;
          this.index = value ? index : null;
          this.value = value || index;
          if (!type.isSymbolNode(object) && !type.isAccessorNode(object)) {
            throw new TypeError('SymbolNode or AccessorNode expected as "object"');
          }
          if (type.isSymbolNode(object) && object.name === "end") {
            throw new Error('Cannot assign to symbol "end"');
          }
          if (this.index && !type.isIndexNode(this.index)) {
            throw new TypeError('IndexNode expected as "index"');
          }
          if (!type.isNode(this.value)) {
            throw new TypeError('Node expected as "value"');
          }
          Object.defineProperty(this, "name", {
            get: function() {
              if (this.index) {
                return this.index.isObjectProperty() ? this.index.getObjectProperty() : "";
              } else {
                return this.object.name || "";
              }
            }.bind(this),
            set: function set() {
              throw new Error("Cannot assign a new name, name is read-only");
            }
          });
        }
        AssignmentNode.prototype = new Node();
        AssignmentNode.prototype.type = "AssignmentNode";
        AssignmentNode.prototype.isAssignmentNode = true;
        AssignmentNode.prototype._compile = function(math2, argNames) {
          var evalObject = this.object._compile(math2, argNames);
          var evalIndex = this.index ? this.index._compile(math2, argNames) : null;
          var evalValue = this.value._compile(math2, argNames);
          var name = this.object.name;
          if (!this.index) {
            if (!type.isSymbolNode(this.object)) {
              throw new TypeError("SymbolNode expected as object");
            }
            return function evalAssignmentNode(scope, args, context) {
              return setSafeProperty(scope, name, evalValue(scope, args, context));
            };
          } else if (this.index.isObjectProperty()) {
            var prop = this.index.getObjectProperty();
            return function evalAssignmentNode(scope, args, context) {
              var object = evalObject(scope, args, context);
              var value = evalValue(scope, args, context);
              return setSafeProperty(object, prop, value);
            };
          } else if (type.isSymbolNode(this.object)) {
            return function evalAssignmentNode(scope, args, context) {
              var childObject = evalObject(scope, args, context);
              var value = evalValue(scope, args, context);
              var index = evalIndex(scope, args, childObject);
              setSafeProperty(scope, name, assign(childObject, index, value));
              return value;
            };
          } else {
            var evalParentObject = this.object.object._compile(math2, argNames);
            if (this.object.index.isObjectProperty()) {
              var parentProp = this.object.index.getObjectProperty();
              return function evalAssignmentNode(scope, args, context) {
                var parent = evalParentObject(scope, args, context);
                var childObject = getSafeProperty(parent, parentProp);
                var index = evalIndex(scope, args, childObject);
                var value = evalValue(scope, args, context);
                setSafeProperty(parent, parentProp, assign(childObject, index, value));
                return value;
              };
            } else {
              var evalParentIndex = this.object.index._compile(math2, argNames);
              return function evalAssignmentNode(scope, args, context) {
                var parent = evalParentObject(scope, args, context);
                var parentIndex = evalParentIndex(scope, args, parent);
                var childObject = access(parent, parentIndex);
                var index = evalIndex(scope, args, childObject);
                var value = evalValue(scope, args, context);
                assign(parent, parentIndex, assign(childObject, index, value));
                return value;
              };
            }
          }
        };
        AssignmentNode.prototype.forEach = function(callback) {
          callback(this.object, "object", this);
          if (this.index) {
            callback(this.index, "index", this);
          }
          callback(this.value, "value", this);
        };
        AssignmentNode.prototype.map = function(callback) {
          var object = this._ifNode(callback(this.object, "object", this));
          var index = this.index ? this._ifNode(callback(this.index, "index", this)) : null;
          var value = this._ifNode(callback(this.value, "value", this));
          return new AssignmentNode(object, index, value);
        };
        AssignmentNode.prototype.clone = function() {
          return new AssignmentNode(this.object, this.index, this.value);
        };
        function needParenthesis(node, parenthesis) {
          if (!parenthesis) {
            parenthesis = "keep";
          }
          var precedence = operators.getPrecedence(node, parenthesis);
          var exprPrecedence = operators.getPrecedence(node.value, parenthesis);
          return parenthesis === "all" || exprPrecedence !== null && exprPrecedence <= precedence;
        }
        AssignmentNode.prototype._toString = function(options) {
          var object = this.object.toString(options);
          var index = this.index ? this.index.toString(options) : "";
          var value = this.value.toString(options);
          if (needParenthesis(this, options && options.parenthesis)) {
            value = "(" + value + ")";
          }
          return object + index + " = " + value;
        };
        AssignmentNode.prototype.toJSON = function() {
          return {
            mathjs: "AssignmentNode",
            object: this.object,
            index: this.index,
            value: this.value
          };
        };
        AssignmentNode.fromJSON = function(json) {
          return new AssignmentNode(json.object, json.index, json.value);
        };
        AssignmentNode.prototype.toHTML = function(options) {
          var object = this.object.toHTML(options);
          var index = this.index ? this.index.toHTML(options) : "";
          var value = this.value.toHTML(options);
          if (needParenthesis(this, options && options.parenthesis)) {
            value = '<span class="math-paranthesis math-round-parenthesis">(</span>' + value + '<span class="math-paranthesis math-round-parenthesis">)</span>';
          }
          return object + index + '<span class="math-operator math-assignment-operator math-variable-assignment-operator math-binary-operator">=</span>' + value;
        };
        AssignmentNode.prototype._toTex = function(options) {
          var object = this.object.toTex(options);
          var index = this.index ? this.index.toTex(options) : "";
          var value = this.value.toTex(options);
          if (needParenthesis(this, options && options.parenthesis)) {
            value = "\\left(".concat(value, "\\right)");
          }
          return object + index + ":=" + value;
        };
        return AssignmentNode;
      }
      exports.name = "AssignmentNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/type/resultset/ResultSet.js
  var require_ResultSet = __commonJS({
    "node_modules/mathjs/lib/type/resultset/ResultSet.js"(exports) {
      "use strict";
      function factory(type, config, load, typed) {
        function ResultSet(entries) {
          if (!(this instanceof ResultSet)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          this.entries = entries || [];
        }
        ResultSet.prototype.type = "ResultSet";
        ResultSet.prototype.isResultSet = true;
        ResultSet.prototype.valueOf = function() {
          return this.entries;
        };
        ResultSet.prototype.toString = function() {
          return "[" + this.entries.join(", ") + "]";
        };
        ResultSet.prototype.toJSON = function() {
          return {
            mathjs: "ResultSet",
            entries: this.entries
          };
        };
        ResultSet.fromJSON = function(json) {
          return new ResultSet(json.entries);
        };
        return ResultSet;
      }
      exports.name = "ResultSet";
      exports.path = "type";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/BlockNode.js
  var require_BlockNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/BlockNode.js"(exports) {
      "use strict";
      var forEach = require_array().forEach;
      var map = require_array().map;
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        var ResultSet = load(require_ResultSet());
        function BlockNode(blocks) {
          if (!(this instanceof BlockNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          if (!Array.isArray(blocks)) throw new Error("Array expected");
          this.blocks = blocks.map(function(block) {
            var node = block && block.node;
            var visible = block && block.visible !== void 0 ? block.visible : true;
            if (!type.isNode(node)) throw new TypeError('Property "node" must be a Node');
            if (typeof visible !== "boolean") throw new TypeError('Property "visible" must be a boolean');
            return {
              node,
              visible
            };
          });
        }
        BlockNode.prototype = new Node();
        BlockNode.prototype.type = "BlockNode";
        BlockNode.prototype.isBlockNode = true;
        BlockNode.prototype._compile = function(math2, argNames) {
          var evalBlocks = map(this.blocks, function(block) {
            return {
              eval: block.node._compile(math2, argNames),
              visible: block.visible
            };
          });
          return function evalBlockNodes(scope, args, context) {
            var results = [];
            forEach(evalBlocks, function evalBlockNode(block) {
              var result = block.eval(scope, args, context);
              if (block.visible) {
                results.push(result);
              }
            });
            return new ResultSet(results);
          };
        };
        BlockNode.prototype.forEach = function(callback) {
          for (var i = 0; i < this.blocks.length; i++) {
            callback(this.blocks[i].node, "blocks[" + i + "].node", this);
          }
        };
        BlockNode.prototype.map = function(callback) {
          var blocks = [];
          for (var i = 0; i < this.blocks.length; i++) {
            var block = this.blocks[i];
            var node = this._ifNode(callback(block.node, "blocks[" + i + "].node", this));
            blocks[i] = {
              node,
              visible: block.visible
            };
          }
          return new BlockNode(blocks);
        };
        BlockNode.prototype.clone = function() {
          var blocks = this.blocks.map(function(block) {
            return {
              node: block.node,
              visible: block.visible
            };
          });
          return new BlockNode(blocks);
        };
        BlockNode.prototype._toString = function(options) {
          return this.blocks.map(function(param) {
            return param.node.toString(options) + (param.visible ? "" : ";");
          }).join("\n");
        };
        BlockNode.prototype.toJSON = function() {
          return {
            mathjs: "BlockNode",
            blocks: this.blocks
          };
        };
        BlockNode.fromJSON = function(json) {
          return new BlockNode(json.blocks);
        };
        BlockNode.prototype.toHTML = function(options) {
          return this.blocks.map(function(param) {
            return param.node.toHTML(options) + (param.visible ? "" : '<span class="math-separator">;</span>');
          }).join('<span class="math-separator"><br /></span>');
        };
        BlockNode.prototype._toTex = function(options) {
          return this.blocks.map(function(param) {
            return param.node.toTex(options) + (param.visible ? "" : ";");
          }).join("\\;\\;\n");
        };
        return BlockNode;
      }
      exports.name = "BlockNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/ConditionalNode.js
  var require_ConditionalNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/ConditionalNode.js"(exports) {
      "use strict";
      var operators = require_operators();
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        var mathTypeOf = load(require_typeof());
        function ConditionalNode(condition, trueExpr, falseExpr) {
          if (!(this instanceof ConditionalNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          if (!type.isNode(condition)) throw new TypeError("Parameter condition must be a Node");
          if (!type.isNode(trueExpr)) throw new TypeError("Parameter trueExpr must be a Node");
          if (!type.isNode(falseExpr)) throw new TypeError("Parameter falseExpr must be a Node");
          this.condition = condition;
          this.trueExpr = trueExpr;
          this.falseExpr = falseExpr;
        }
        ConditionalNode.prototype = new Node();
        ConditionalNode.prototype.type = "ConditionalNode";
        ConditionalNode.prototype.isConditionalNode = true;
        ConditionalNode.prototype._compile = function(math2, argNames) {
          var evalCondition = this.condition._compile(math2, argNames);
          var evalTrueExpr = this.trueExpr._compile(math2, argNames);
          var evalFalseExpr = this.falseExpr._compile(math2, argNames);
          return function evalConditionalNode(scope, args, context) {
            return testCondition(evalCondition(scope, args, context)) ? evalTrueExpr(scope, args, context) : evalFalseExpr(scope, args, context);
          };
        };
        ConditionalNode.prototype.forEach = function(callback) {
          callback(this.condition, "condition", this);
          callback(this.trueExpr, "trueExpr", this);
          callback(this.falseExpr, "falseExpr", this);
        };
        ConditionalNode.prototype.map = function(callback) {
          return new ConditionalNode(this._ifNode(callback(this.condition, "condition", this)), this._ifNode(callback(this.trueExpr, "trueExpr", this)), this._ifNode(callback(this.falseExpr, "falseExpr", this)));
        };
        ConditionalNode.prototype.clone = function() {
          return new ConditionalNode(this.condition, this.trueExpr, this.falseExpr);
        };
        ConditionalNode.prototype._toString = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var precedence = operators.getPrecedence(this, parenthesis);
          var condition = this.condition.toString(options);
          var conditionPrecedence = operators.getPrecedence(this.condition, parenthesis);
          if (parenthesis === "all" || this.condition.type === "OperatorNode" || conditionPrecedence !== null && conditionPrecedence <= precedence) {
            condition = "(" + condition + ")";
          }
          var trueExpr = this.trueExpr.toString(options);
          var truePrecedence = operators.getPrecedence(this.trueExpr, parenthesis);
          if (parenthesis === "all" || this.trueExpr.type === "OperatorNode" || truePrecedence !== null && truePrecedence <= precedence) {
            trueExpr = "(" + trueExpr + ")";
          }
          var falseExpr = this.falseExpr.toString(options);
          var falsePrecedence = operators.getPrecedence(this.falseExpr, parenthesis);
          if (parenthesis === "all" || this.falseExpr.type === "OperatorNode" || falsePrecedence !== null && falsePrecedence <= precedence) {
            falseExpr = "(" + falseExpr + ")";
          }
          return condition + " ? " + trueExpr + " : " + falseExpr;
        };
        ConditionalNode.prototype.toJSON = function() {
          return {
            mathjs: "ConditionalNode",
            condition: this.condition,
            trueExpr: this.trueExpr,
            falseExpr: this.falseExpr
          };
        };
        ConditionalNode.fromJSON = function(json) {
          return new ConditionalNode(json.condition, json.trueExpr, json.falseExpr);
        };
        ConditionalNode.prototype.toHTML = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var precedence = operators.getPrecedence(this, parenthesis);
          var condition = this.condition.toHTML(options);
          var conditionPrecedence = operators.getPrecedence(this.condition, parenthesis);
          if (parenthesis === "all" || this.condition.type === "OperatorNode" || conditionPrecedence !== null && conditionPrecedence <= precedence) {
            condition = '<span class="math-parenthesis math-round-parenthesis">(</span>' + condition + '<span class="math-parenthesis math-round-parenthesis">)</span>';
          }
          var trueExpr = this.trueExpr.toHTML(options);
          var truePrecedence = operators.getPrecedence(this.trueExpr, parenthesis);
          if (parenthesis === "all" || this.trueExpr.type === "OperatorNode" || truePrecedence !== null && truePrecedence <= precedence) {
            trueExpr = '<span class="math-parenthesis math-round-parenthesis">(</span>' + trueExpr + '<span class="math-parenthesis math-round-parenthesis">)</span>';
          }
          var falseExpr = this.falseExpr.toHTML(options);
          var falsePrecedence = operators.getPrecedence(this.falseExpr, parenthesis);
          if (parenthesis === "all" || this.falseExpr.type === "OperatorNode" || falsePrecedence !== null && falsePrecedence <= precedence) {
            falseExpr = '<span class="math-parenthesis math-round-parenthesis">(</span>' + falseExpr + '<span class="math-parenthesis math-round-parenthesis">)</span>';
          }
          return condition + '<span class="math-operator math-conditional-operator">?</span>' + trueExpr + '<span class="math-operator math-conditional-operator">:</span>' + falseExpr;
        };
        ConditionalNode.prototype._toTex = function(options) {
          return "\\begin{cases} {" + this.trueExpr.toTex(options) + "}, &\\quad{\\text{if }\\;" + this.condition.toTex(options) + "}\\\\{" + this.falseExpr.toTex(options) + "}, &\\quad{\\text{otherwise}}\\end{cases}";
        };
        function testCondition(condition) {
          if (typeof condition === "number" || typeof condition === "boolean" || typeof condition === "string") {
            return !!condition;
          }
          if (condition) {
            if (type.isBigNumber(condition)) {
              return !condition.isZero();
            }
            if (type.isComplex(condition)) {
              return !!(condition.re || condition.im);
            }
            if (type.isUnit(condition)) {
              return !!condition.value;
            }
          }
          if (condition === null || condition === void 0) {
            return false;
          }
          throw new TypeError('Unsupported type of condition "' + mathTypeOf(condition) + '"');
        }
        return ConditionalNode;
      }
      exports.name = "ConditionalNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/escape-latex/dist/index.js
  var require_dist = __commonJS({
    "node_modules/escape-latex/dist/index.js"(exports, module) {
      "use strict";
      var _extends = Object.assign || function(target) {
        for (var i = 1; i < arguments.length; i++) {
          var source = arguments[i];
          for (var key in source) {
            if (Object.prototype.hasOwnProperty.call(source, key)) {
              target[key] = source[key];
            }
          }
        }
        return target;
      };
      var defaultEscapes = {
        "{": "\\{",
        "}": "\\}",
        "\\": "\\textbackslash{}",
        "#": "\\#",
        $: "\\$",
        "%": "\\%",
        "&": "\\&",
        "^": "\\textasciicircum{}",
        _: "\\_",
        "~": "\\textasciitilde{}"
      };
      var formatEscapes = {
        "\u2013": "\\--",
        "\u2014": "\\---",
        " ": "~",
        "	": "\\qquad{}",
        "\r\n": "\\newline{}",
        "\n": "\\newline{}"
      };
      var defaultEscapeMapFn = function defaultEscapeMapFn2(defaultEscapes2, formatEscapes2) {
        return _extends({}, defaultEscapes2, formatEscapes2);
      };
      module.exports = function(str) {
        var _ref = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : {}, _ref$preserveFormatti = _ref.preserveFormatting, preserveFormatting = _ref$preserveFormatti === void 0 ? false : _ref$preserveFormatti, _ref$escapeMapFn = _ref.escapeMapFn, escapeMapFn = _ref$escapeMapFn === void 0 ? defaultEscapeMapFn : _ref$escapeMapFn;
        var runningStr = String(str);
        var result = "";
        var escapes = escapeMapFn(_extends({}, defaultEscapes), preserveFormatting ? _extends({}, formatEscapes) : {});
        var escapeKeys = Object.keys(escapes);
        var _loop = function _loop2() {
          var specialCharFound = false;
          escapeKeys.forEach(function(key, index) {
            if (specialCharFound) {
              return;
            }
            if (runningStr.length >= key.length && runningStr.slice(0, key.length) === key) {
              result += escapes[escapeKeys[index]];
              runningStr = runningStr.slice(key.length, runningStr.length);
              specialCharFound = true;
            }
          });
          if (!specialCharFound) {
            result += runningStr.slice(0, 1);
            runningStr = runningStr.slice(1, runningStr.length);
          }
        };
        while (runningStr) {
          _loop();
        }
        return result;
      };
    }
  });

  // node_modules/mathjs/lib/utils/latex.js
  var require_latex = __commonJS({
    "node_modules/mathjs/lib/utils/latex.js"(exports) {
      "use strict";
      var escapeLatex = require_dist();
      exports.symbols = {
        // GREEK LETTERS
        Alpha: "A",
        alpha: "\\alpha",
        Beta: "B",
        beta: "\\beta",
        Gamma: "\\Gamma",
        gamma: "\\gamma",
        Delta: "\\Delta",
        delta: "\\delta",
        Epsilon: "E",
        epsilon: "\\epsilon",
        varepsilon: "\\varepsilon",
        Zeta: "Z",
        zeta: "\\zeta",
        Eta: "H",
        eta: "\\eta",
        Theta: "\\Theta",
        theta: "\\theta",
        vartheta: "\\vartheta",
        Iota: "I",
        iota: "\\iota",
        Kappa: "K",
        kappa: "\\kappa",
        varkappa: "\\varkappa",
        Lambda: "\\Lambda",
        lambda: "\\lambda",
        Mu: "M",
        mu: "\\mu",
        Nu: "N",
        nu: "\\nu",
        Xi: "\\Xi",
        xi: "\\xi",
        Omicron: "O",
        omicron: "o",
        Pi: "\\Pi",
        pi: "\\pi",
        varpi: "\\varpi",
        Rho: "P",
        rho: "\\rho",
        varrho: "\\varrho",
        Sigma: "\\Sigma",
        sigma: "\\sigma",
        varsigma: "\\varsigma",
        Tau: "T",
        tau: "\\tau",
        Upsilon: "\\Upsilon",
        upsilon: "\\upsilon",
        Phi: "\\Phi",
        phi: "\\phi",
        varphi: "\\varphi",
        Chi: "X",
        chi: "\\chi",
        Psi: "\\Psi",
        psi: "\\psi",
        Omega: "\\Omega",
        omega: "\\omega",
        // logic
        "true": "\\mathrm{True}",
        "false": "\\mathrm{False}",
        // other
        i: "i",
        // TODO use \i ??
        inf: "\\infty",
        Inf: "\\infty",
        infinity: "\\infty",
        Infinity: "\\infty",
        oo: "\\infty",
        lim: "\\lim",
        "undefined": "\\mathbf{?}"
      };
      exports.operators = {
        "transpose": "^\\top",
        "ctranspose": "^H",
        "factorial": "!",
        "pow": "^",
        "dotPow": ".^\\wedge",
        // TODO find ideal solution
        "unaryPlus": "+",
        "unaryMinus": "-",
        "bitNot": "\\~",
        // TODO find ideal solution
        "not": "\\neg",
        "multiply": "\\cdot",
        "divide": "\\frac",
        // TODO how to handle that properly?
        "dotMultiply": ".\\cdot",
        // TODO find ideal solution
        "dotDivide": ".:",
        // TODO find ideal solution
        "mod": "\\mod",
        "add": "+",
        "subtract": "-",
        "to": "\\rightarrow",
        "leftShift": "<<",
        "rightArithShift": ">>",
        "rightLogShift": ">>>",
        "equal": "=",
        "unequal": "\\neq",
        "smaller": "<",
        "larger": ">",
        "smallerEq": "\\leq",
        "largerEq": "\\geq",
        "bitAnd": "\\&",
        "bitXor": "\\underline{|}",
        "bitOr": "|",
        "and": "\\wedge",
        "xor": "\\veebar",
        "or": "\\vee"
      };
      exports.defaultTemplate = "\\mathrm{${name}}\\left(${args}\\right)";
      var units = {
        deg: "^\\circ"
      };
      exports.escape = function(string) {
        return escapeLatex(string, {
          "preserveFormatting": true
        });
      };
      exports.toSymbol = function(name, isUnit) {
        isUnit = typeof isUnit === "undefined" ? false : isUnit;
        if (isUnit) {
          if (units.hasOwnProperty(name)) {
            return units[name];
          }
          return "\\mathrm{" + exports.escape(name) + "}";
        }
        if (exports.symbols.hasOwnProperty(name)) {
          return exports.symbols[name];
        }
        return exports.escape(name);
      };
    }
  });

  // node_modules/mathjs/lib/expression/node/ConstantNode.js
  var require_ConstantNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/ConstantNode.js"(exports) {
      "use strict";
      var format = require_string().format;
      var escapeLatex = require_latex().escape;
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        var getType = load(require_typeof());
        function ConstantNode(value) {
          if (!(this instanceof ConstantNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          if (arguments.length === 2) {
            throw new SyntaxError("new ConstantNode(valueStr, valueType) is not supported anymore since math v4.0.0. Use new ConstantNode(value) instead, where value is a non-stringified value.");
          }
          this.value = value;
        }
        ConstantNode.prototype = new Node();
        ConstantNode.prototype.type = "ConstantNode";
        ConstantNode.prototype.isConstantNode = true;
        ConstantNode.prototype._compile = function(math2, argNames) {
          var value = this.value;
          return function evalConstantNode() {
            return value;
          };
        };
        ConstantNode.prototype.forEach = function(callback) {
        };
        ConstantNode.prototype.map = function(callback) {
          return this.clone();
        };
        ConstantNode.prototype.clone = function() {
          return new ConstantNode(this.value);
        };
        ConstantNode.prototype._toString = function(options) {
          return format(this.value, options);
        };
        ConstantNode.prototype.toHTML = function(options) {
          var value = this._toString(options);
          switch (getType(this.value)) {
            case "number":
            case "BigNumber":
            case "Fraction":
              return '<span class="math-number">' + value + "</span>";
            case "string":
              return '<span class="math-string">' + value + "</span>";
            case "boolean":
              return '<span class="math-boolean">' + value + "</span>";
            case "null":
              return '<span class="math-null-symbol">' + value + "</span>";
            case "undefined":
              return '<span class="math-undefined">' + value + "</span>";
            default:
              return '<span class="math-symbol">' + value + "</span>";
          }
        };
        ConstantNode.prototype.toJSON = function() {
          return {
            mathjs: "ConstantNode",
            value: this.value
          };
        };
        ConstantNode.fromJSON = function(json) {
          return new ConstantNode(json.value);
        };
        ConstantNode.prototype._toTex = function(options) {
          var value = this._toString(options);
          switch (getType(this.value)) {
            case "string":
              return "\\mathtt{" + escapeLatex(value) + "}";
            case "number":
            case "BigNumber":
              var index = value.toLowerCase().indexOf("e");
              if (index !== -1) {
                return value.substring(0, index) + "\\cdot10^{" + value.substring(index + 1) + "}";
              }
              return value;
            case "Fraction":
              return this.value.toLatex();
            default:
              return value;
          }
        };
        return ConstantNode;
      }
      exports.name = "ConstantNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/FunctionAssignmentNode.js
  var require_FunctionAssignmentNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/FunctionAssignmentNode.js"(exports) {
      "use strict";
      var keywords = require_keywords();
      var escape = require_string().escape;
      var forEach = require_array().forEach;
      var join = require_array().join;
      var latex = require_latex();
      var operators = require_operators();
      var setSafeProperty = require_customs().setSafeProperty;
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        function FunctionAssignmentNode(name, params, expr) {
          if (!(this instanceof FunctionAssignmentNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          if (typeof name !== "string") throw new TypeError('String expected for parameter "name"');
          if (!Array.isArray(params)) throw new TypeError('Array containing strings or objects expected for parameter "params"');
          if (!type.isNode(expr)) throw new TypeError('Node expected for parameter "expr"');
          if (name in keywords) throw new Error('Illegal function name, "' + name + '" is a reserved keyword');
          this.name = name;
          this.params = params.map(function(param) {
            return param && param.name || param;
          });
          this.types = params.map(function(param) {
            return param && param.type || "any";
          });
          this.expr = expr;
        }
        FunctionAssignmentNode.prototype = new Node();
        FunctionAssignmentNode.prototype.type = "FunctionAssignmentNode";
        FunctionAssignmentNode.prototype.isFunctionAssignmentNode = true;
        FunctionAssignmentNode.prototype._compile = function(math2, argNames) {
          var childArgNames = Object.create(argNames);
          forEach(this.params, function(param) {
            childArgNames[param] = true;
          });
          var evalExpr = this.expr._compile(math2, childArgNames);
          var name = this.name;
          var params = this.params;
          var signature = join(this.types, ",");
          var syntax = name + "(" + join(this.params, ", ") + ")";
          return function evalFunctionAssignmentNode(scope, args, context) {
            var signatures = {};
            signatures[signature] = function() {
              var childArgs = Object.create(args);
              for (var i = 0; i < params.length; i++) {
                childArgs[params[i]] = arguments[i];
              }
              return evalExpr(scope, childArgs, context);
            };
            var fn = typed(name, signatures);
            fn.syntax = syntax;
            setSafeProperty(scope, name, fn);
            return fn;
          };
        };
        FunctionAssignmentNode.prototype.forEach = function(callback) {
          callback(this.expr, "expr", this);
        };
        FunctionAssignmentNode.prototype.map = function(callback) {
          var expr = this._ifNode(callback(this.expr, "expr", this));
          return new FunctionAssignmentNode(this.name, this.params.slice(0), expr);
        };
        FunctionAssignmentNode.prototype.clone = function() {
          return new FunctionAssignmentNode(this.name, this.params.slice(0), this.expr);
        };
        function needParenthesis(node, parenthesis) {
          var precedence = operators.getPrecedence(node, parenthesis);
          var exprPrecedence = operators.getPrecedence(node.expr, parenthesis);
          return parenthesis === "all" || exprPrecedence !== null && exprPrecedence <= precedence;
        }
        FunctionAssignmentNode.prototype._toString = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var expr = this.expr.toString(options);
          if (needParenthesis(this, parenthesis)) {
            expr = "(" + expr + ")";
          }
          return this.name + "(" + this.params.join(", ") + ") = " + expr;
        };
        FunctionAssignmentNode.prototype.toJSON = function() {
          var types = this.types;
          return {
            mathjs: "FunctionAssignmentNode",
            name: this.name,
            params: this.params.map(function(param, index) {
              return {
                name: param,
                type: types[index]
              };
            }),
            expr: this.expr
          };
        };
        FunctionAssignmentNode.fromJSON = function(json) {
          return new FunctionAssignmentNode(json.name, json.params, json.expr);
        };
        FunctionAssignmentNode.prototype.toHTML = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var params = [];
          for (var i = 0; i < this.params.length; i++) {
            params.push('<span class="math-symbol math-parameter">' + escape(this.params[i]) + "</span>");
          }
          var expr = this.expr.toHTML(options);
          if (needParenthesis(this, parenthesis)) {
            expr = '<span class="math-parenthesis math-round-parenthesis">(</span>' + expr + '<span class="math-parenthesis math-round-parenthesis">)</span>';
          }
          return '<span class="math-function">' + escape(this.name) + '</span><span class="math-parenthesis math-round-parenthesis">(</span>' + params.join('<span class="math-separator">,</span>') + '<span class="math-parenthesis math-round-parenthesis">)</span><span class="math-operator math-assignment-operator math-variable-assignment-operator math-binary-operator">=</span>' + expr;
        };
        FunctionAssignmentNode.prototype._toTex = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var expr = this.expr.toTex(options);
          if (needParenthesis(this, parenthesis)) {
            expr = "\\left(".concat(expr, "\\right)");
          }
          return "\\mathrm{" + this.name + "}\\left(" + this.params.map(latex.toSymbol).join(",") + "\\right):=" + expr;
        };
        return FunctionAssignmentNode;
      }
      exports.name = "FunctionAssignmentNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/type/matrix/Range.js
  var require_Range = __commonJS({
    "node_modules/mathjs/lib/type/matrix/Range.js"(exports) {
      "use strict";
      var number = require_number();
      function factory(type, config, load, typed) {
        function Range(start, end, step) {
          if (!(this instanceof Range)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          var hasStart = start !== null && start !== void 0;
          var hasEnd = end !== null && end !== void 0;
          var hasStep = step !== null && step !== void 0;
          if (hasStart) {
            if (type.isBigNumber(start)) {
              start = start.toNumber();
            } else if (typeof start !== "number") {
              throw new TypeError("Parameter start must be a number");
            }
          }
          if (hasEnd) {
            if (type.isBigNumber(end)) {
              end = end.toNumber();
            } else if (typeof end !== "number") {
              throw new TypeError("Parameter end must be a number");
            }
          }
          if (hasStep) {
            if (type.isBigNumber(step)) {
              step = step.toNumber();
            } else if (typeof step !== "number") {
              throw new TypeError("Parameter step must be a number");
            }
          }
          this.start = hasStart ? parseFloat(start) : 0;
          this.end = hasEnd ? parseFloat(end) : 0;
          this.step = hasStep ? parseFloat(step) : 1;
        }
        Range.prototype.type = "Range";
        Range.prototype.isRange = true;
        Range.parse = function(str) {
          if (typeof str !== "string") {
            return null;
          }
          var args = str.split(":");
          var nums = args.map(function(arg) {
            return parseFloat(arg);
          });
          var invalid = nums.some(function(num) {
            return isNaN(num);
          });
          if (invalid) {
            return null;
          }
          switch (nums.length) {
            case 2:
              return new Range(nums[0], nums[1]);
            case 3:
              return new Range(nums[0], nums[2], nums[1]);
            default:
              return null;
          }
        };
        Range.prototype.clone = function() {
          return new Range(this.start, this.end, this.step);
        };
        Range.prototype.size = function() {
          var len = 0;
          var start = this.start;
          var step = this.step;
          var end = this.end;
          var diff = end - start;
          if (number.sign(step) === number.sign(diff)) {
            len = Math.ceil(diff / step);
          } else if (diff === 0) {
            len = 0;
          }
          if (isNaN(len)) {
            len = 0;
          }
          return [len];
        };
        Range.prototype.min = function() {
          var size = this.size()[0];
          if (size > 0) {
            if (this.step > 0) {
              return this.start;
            } else {
              return this.start + (size - 1) * this.step;
            }
          } else {
            return void 0;
          }
        };
        Range.prototype.max = function() {
          var size = this.size()[0];
          if (size > 0) {
            if (this.step > 0) {
              return this.start + (size - 1) * this.step;
            } else {
              return this.start;
            }
          } else {
            return void 0;
          }
        };
        Range.prototype.forEach = function(callback) {
          var x = this.start;
          var step = this.step;
          var end = this.end;
          var i = 0;
          if (step > 0) {
            while (x < end) {
              callback(x, [i], this);
              x += step;
              i++;
            }
          } else if (step < 0) {
            while (x > end) {
              callback(x, [i], this);
              x += step;
              i++;
            }
          }
        };
        Range.prototype.map = function(callback) {
          var array = [];
          this.forEach(function(value, index, obj) {
            array[index[0]] = callback(value, index, obj);
          });
          return array;
        };
        Range.prototype.toArray = function() {
          var array = [];
          this.forEach(function(value, index) {
            array[index[0]] = value;
          });
          return array;
        };
        Range.prototype.valueOf = function() {
          return this.toArray();
        };
        Range.prototype.format = function(options) {
          var str = number.format(this.start, options);
          if (this.step !== 1) {
            str += ":" + number.format(this.step, options);
          }
          str += ":" + number.format(this.end, options);
          return str;
        };
        Range.prototype.toString = function() {
          return this.format();
        };
        Range.prototype.toJSON = function() {
          return {
            mathjs: "Range",
            start: this.start,
            end: this.end,
            step: this.step
          };
        };
        Range.fromJSON = function(json) {
          return new Range(json.start, json.end, json.step);
        };
        return Range;
      }
      exports.name = "Range";
      exports.path = "type";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/IndexNode.js
  var require_IndexNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/IndexNode.js"(exports) {
      "use strict";
      var map = require_array().map;
      var escape = require_string().escape;
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        var Range = load(require_Range());
        var isArray = Array.isArray;
        function IndexNode(dimensions, dotNotation) {
          if (!(this instanceof IndexNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          this.dimensions = dimensions;
          this.dotNotation = dotNotation || false;
          if (!isArray(dimensions) || !dimensions.every(type.isNode)) {
            throw new TypeError('Array containing Nodes expected for parameter "dimensions"');
          }
          if (this.dotNotation && !this.isObjectProperty()) {
            throw new Error("dotNotation only applicable for object properties");
          }
          var deprecated = function deprecated2() {
            throw new Error("Property `IndexNode.object` is deprecated, use `IndexNode.fn` instead");
          };
          Object.defineProperty(this, "object", {
            get: deprecated,
            set: deprecated
          });
        }
        IndexNode.prototype = new Node();
        IndexNode.prototype.type = "IndexNode";
        IndexNode.prototype.isIndexNode = true;
        IndexNode.prototype._compile = function(math2, argNames) {
          var evalDimensions = map(this.dimensions, function(range, i) {
            if (type.isRangeNode(range)) {
              if (range.needsEnd()) {
                var childArgNames = Object.create(argNames);
                childArgNames["end"] = true;
                var evalStart = range.start._compile(math2, childArgNames);
                var evalEnd = range.end._compile(math2, childArgNames);
                var evalStep = range.step ? range.step._compile(math2, childArgNames) : function() {
                  return 1;
                };
                return function evalDimension(scope, args, context) {
                  var size = math2.size(context).valueOf();
                  var childArgs = Object.create(args);
                  childArgs["end"] = size[i];
                  return createRange(evalStart(scope, childArgs, context), evalEnd(scope, childArgs, context), evalStep(scope, childArgs, context));
                };
              } else {
                var _evalStart = range.start._compile(math2, argNames);
                var _evalEnd = range.end._compile(math2, argNames);
                var _evalStep = range.step ? range.step._compile(math2, argNames) : function() {
                  return 1;
                };
                return function evalDimension(scope, args, context) {
                  return createRange(_evalStart(scope, args, context), _evalEnd(scope, args, context), _evalStep(scope, args, context));
                };
              }
            } else if (type.isSymbolNode(range) && range.name === "end") {
              var _childArgNames = Object.create(argNames);
              _childArgNames["end"] = true;
              var evalRange = range._compile(math2, _childArgNames);
              return function evalDimension(scope, args, context) {
                var size = math2.size(context).valueOf();
                var childArgs = Object.create(args);
                childArgs["end"] = size[i];
                return evalRange(scope, childArgs, context);
              };
            } else {
              var _evalRange = range._compile(math2, argNames);
              return function evalDimension(scope, args, context) {
                return _evalRange(scope, args, context);
              };
            }
          });
          return function evalIndexNode(scope, args, context) {
            var dimensions = map(evalDimensions, function(evalDimension) {
              return evalDimension(scope, args, context);
            });
            return math2.index.apply(math2, dimensions);
          };
        };
        IndexNode.prototype.forEach = function(callback) {
          for (var i = 0; i < this.dimensions.length; i++) {
            callback(this.dimensions[i], "dimensions[" + i + "]", this);
          }
        };
        IndexNode.prototype.map = function(callback) {
          var dimensions = [];
          for (var i = 0; i < this.dimensions.length; i++) {
            dimensions[i] = this._ifNode(callback(this.dimensions[i], "dimensions[" + i + "]", this));
          }
          return new IndexNode(dimensions);
        };
        IndexNode.prototype.clone = function() {
          return new IndexNode(this.dimensions.slice(0));
        };
        IndexNode.prototype.isObjectProperty = function() {
          return this.dimensions.length === 1 && type.isConstantNode(this.dimensions[0]) && typeof this.dimensions[0].value === "string";
        };
        IndexNode.prototype.getObjectProperty = function() {
          return this.isObjectProperty() ? this.dimensions[0].value : null;
        };
        IndexNode.prototype._toString = function(options) {
          return this.dotNotation ? "." + this.getObjectProperty() : "[" + this.dimensions.join(", ") + "]";
        };
        IndexNode.prototype.toJSON = function() {
          return {
            mathjs: "IndexNode",
            dimensions: this.dimensions,
            dotNotation: this.dotNotation
          };
        };
        IndexNode.fromJSON = function(json) {
          return new IndexNode(json.dimensions, json.dotNotation);
        };
        IndexNode.prototype.toHTML = function(options) {
          var dimensions = [];
          for (var i = 0; i < this.dimensions.length; i++) {
            dimensions[i] = this.dimensions[i].toHTML();
          }
          if (this.dotNotation) {
            return '<span class="math-operator math-accessor-operator">.</span><span class="math-symbol math-property">' + escape(this.getObjectProperty()) + "</span>";
          } else {
            return '<span class="math-parenthesis math-square-parenthesis">[</span>' + dimensions.join('<span class="math-separator">,</span>') + '<span class="math-parenthesis math-square-parenthesis">]</span>';
          }
        };
        IndexNode.prototype._toTex = function(options) {
          var dimensions = this.dimensions.map(function(range) {
            return range.toTex(options);
          });
          return this.dotNotation ? "." + this.getObjectProperty() : "_{" + dimensions.join(",") + "}";
        };
        function createRange(start, end, step) {
          return new Range(type.isBigNumber(start) ? start.toNumber() : start, type.isBigNumber(end) ? end.toNumber() : end, type.isBigNumber(step) ? step.toNumber() : step);
        }
        return IndexNode;
      }
      exports.name = "IndexNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/ObjectNode.js
  var require_ObjectNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/ObjectNode.js"(exports) {
      "use strict";
      function _typeof(obj) {
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      var stringify = require_string().stringify;
      var escape = require_string().escape;
      var isSafeProperty = require_customs().isSafeProperty;
      var hasOwnProperty = require_object().hasOwnProperty;
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        function ObjectNode(properties) {
          if (!(this instanceof ObjectNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          this.properties = properties || {};
          if (properties) {
            if (!(_typeof(properties) === "object") || !Object.keys(properties).every(function(key) {
              return type.isNode(properties[key]);
            })) {
              throw new TypeError("Object containing Nodes expected");
            }
          }
        }
        ObjectNode.prototype = new Node();
        ObjectNode.prototype.type = "ObjectNode";
        ObjectNode.prototype.isObjectNode = true;
        ObjectNode.prototype._compile = function(math2, argNames) {
          var evalEntries = {};
          for (var key in this.properties) {
            if (hasOwnProperty(this.properties, key)) {
              var stringifiedKey = stringify(key);
              var parsedKey = JSON.parse(stringifiedKey);
              if (!isSafeProperty(this.properties, parsedKey)) {
                throw new Error('No access to property "' + parsedKey + '"');
              }
              evalEntries[parsedKey] = this.properties[key]._compile(math2, argNames);
            }
          }
          return function evalObjectNode(scope, args, context) {
            var obj = {};
            for (var _key in evalEntries) {
              if (hasOwnProperty(evalEntries, _key)) {
                obj[_key] = evalEntries[_key](scope, args, context);
              }
            }
            return obj;
          };
        };
        ObjectNode.prototype.forEach = function(callback) {
          for (var key in this.properties) {
            if (this.properties.hasOwnProperty(key)) {
              callback(this.properties[key], "properties[" + stringify(key) + "]", this);
            }
          }
        };
        ObjectNode.prototype.map = function(callback) {
          var properties = {};
          for (var key in this.properties) {
            if (this.properties.hasOwnProperty(key)) {
              properties[key] = this._ifNode(callback(this.properties[key], "properties[" + stringify(key) + "]", this));
            }
          }
          return new ObjectNode(properties);
        };
        ObjectNode.prototype.clone = function() {
          var properties = {};
          for (var key in this.properties) {
            if (this.properties.hasOwnProperty(key)) {
              properties[key] = this.properties[key];
            }
          }
          return new ObjectNode(properties);
        };
        ObjectNode.prototype._toString = function(options) {
          var entries = [];
          for (var key in this.properties) {
            if (this.properties.hasOwnProperty(key)) {
              entries.push(stringify(key) + ": " + this.properties[key].toString(options));
            }
          }
          return "{" + entries.join(", ") + "}";
        };
        ObjectNode.prototype.toJSON = function() {
          return {
            mathjs: "ObjectNode",
            properties: this.properties
          };
        };
        ObjectNode.fromJSON = function(json) {
          return new ObjectNode(json.properties);
        };
        ObjectNode.prototype.toHTML = function(options) {
          var entries = [];
          for (var key in this.properties) {
            if (this.properties.hasOwnProperty(key)) {
              entries.push('<span class="math-symbol math-property">' + escape(key) + '</span><span class="math-operator math-assignment-operator math-property-assignment-operator math-binary-operator">:</span>' + this.properties[key].toHTML(options));
            }
          }
          return '<span class="math-parenthesis math-curly-parenthesis">{</span>' + entries.join('<span class="math-separator">,</span>') + '<span class="math-parenthesis math-curly-parenthesis">}</span>';
        };
        ObjectNode.prototype._toTex = function(options) {
          var entries = [];
          for (var key in this.properties) {
            if (this.properties.hasOwnProperty(key)) {
              entries.push("\\mathbf{" + key + ":} & " + this.properties[key].toTex(options) + "\\\\");
            }
          }
          return "\\left\\{\\begin{array}{ll}".concat(entries.join("\n"), "\\end{array}\\right\\}");
        };
        return ObjectNode;
      }
      exports.name = "ObjectNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/OperatorNode.js
  var require_OperatorNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/OperatorNode.js"(exports) {
      "use strict";
      var latex = require_latex();
      var map = require_array().map;
      var escape = require_string().escape;
      var isSafeMethod = require_customs().isSafeMethod;
      var getSafeProperty = require_customs().getSafeProperty;
      var operators = require_operators();
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        function OperatorNode(op, fn, args, implicit) {
          if (!(this instanceof OperatorNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          if (typeof op !== "string") {
            throw new TypeError('string expected for parameter "op"');
          }
          if (typeof fn !== "string") {
            throw new TypeError('string expected for parameter "fn"');
          }
          if (!Array.isArray(args) || !args.every(type.isNode)) {
            throw new TypeError('Array containing Nodes expected for parameter "args"');
          }
          this.implicit = implicit === true;
          this.op = op;
          this.fn = fn;
          this.args = args || [];
        }
        OperatorNode.prototype = new Node();
        OperatorNode.prototype.type = "OperatorNode";
        OperatorNode.prototype.isOperatorNode = true;
        OperatorNode.prototype._compile = function(math2, argNames) {
          if (typeof this.fn !== "string" || !isSafeMethod(math2, this.fn)) {
            if (!math2[this.fn]) {
              throw new Error("Function " + this.fn + ' missing in provided namespace "math"');
            } else {
              throw new Error('No access to function "' + this.fn + '"');
            }
          }
          var fn = getSafeProperty(math2, this.fn);
          var evalArgs = map(this.args, function(arg) {
            return arg._compile(math2, argNames);
          });
          if (evalArgs.length === 1) {
            var evalArg0 = evalArgs[0];
            return function evalOperatorNode(scope, args, context) {
              return fn(evalArg0(scope, args, context));
            };
          } else if (evalArgs.length === 2) {
            var _evalArg = evalArgs[0];
            var evalArg1 = evalArgs[1];
            return function evalOperatorNode(scope, args, context) {
              return fn(_evalArg(scope, args, context), evalArg1(scope, args, context));
            };
          } else {
            return function evalOperatorNode(scope, args, context) {
              return fn.apply(null, map(evalArgs, function(evalArg) {
                return evalArg(scope, args, context);
              }));
            };
          }
        };
        OperatorNode.prototype.forEach = function(callback) {
          for (var i = 0; i < this.args.length; i++) {
            callback(this.args[i], "args[" + i + "]", this);
          }
        };
        OperatorNode.prototype.map = function(callback) {
          var args = [];
          for (var i = 0; i < this.args.length; i++) {
            args[i] = this._ifNode(callback(this.args[i], "args[" + i + "]", this));
          }
          return new OperatorNode(this.op, this.fn, args, this.implicit);
        };
        OperatorNode.prototype.clone = function() {
          return new OperatorNode(this.op, this.fn, this.args.slice(0), this.implicit);
        };
        OperatorNode.prototype.isUnary = function() {
          return this.args.length === 1;
        };
        OperatorNode.prototype.isBinary = function() {
          return this.args.length === 2;
        };
        function calculateNecessaryParentheses(root, parenthesis, implicit, args, latex2) {
          var precedence = operators.getPrecedence(root, parenthesis);
          var associativity = operators.getAssociativity(root, parenthesis);
          if (parenthesis === "all" || args.length > 2 && root.getIdentifier() !== "OperatorNode:add" && root.getIdentifier() !== "OperatorNode:multiply") {
            var parens = args.map(function(arg) {
              switch (arg.getContent().type) {
                // Nodes that don't need extra parentheses
                case "ArrayNode":
                case "ConstantNode":
                case "SymbolNode":
                case "ParenthesisNode":
                  return false;
                default:
                  return true;
              }
            });
            return parens;
          }
          var result;
          switch (args.length) {
            case 0:
              result = [];
              break;
            case 1:
              var operandPrecedence = operators.getPrecedence(args[0], parenthesis);
              if (latex2 && operandPrecedence !== null) {
                var operandIdentifier;
                var rootIdentifier;
                if (parenthesis === "keep") {
                  operandIdentifier = args[0].getIdentifier();
                  rootIdentifier = root.getIdentifier();
                } else {
                  operandIdentifier = args[0].getContent().getIdentifier();
                  rootIdentifier = root.getContent().getIdentifier();
                }
                if (operators.properties[precedence][rootIdentifier].latexLeftParens === false) {
                  result = [false];
                  break;
                }
                if (operators.properties[operandPrecedence][operandIdentifier].latexParens === false) {
                  result = [false];
                  break;
                }
              }
              if (operandPrecedence === null) {
                result = [false];
                break;
              }
              if (operandPrecedence <= precedence) {
                result = [true];
                break;
              }
              result = [false];
              break;
            case 2:
              var lhsParens;
              var lhsPrecedence = operators.getPrecedence(args[0], parenthesis);
              var assocWithLhs = operators.isAssociativeWith(root, args[0], parenthesis);
              if (lhsPrecedence === null) {
                lhsParens = false;
              } else if (lhsPrecedence === precedence && associativity === "right" && !assocWithLhs) {
                lhsParens = true;
              } else if (lhsPrecedence < precedence) {
                lhsParens = true;
              } else {
                lhsParens = false;
              }
              var rhsParens;
              var rhsPrecedence = operators.getPrecedence(args[1], parenthesis);
              var assocWithRhs = operators.isAssociativeWith(root, args[1], parenthesis);
              if (rhsPrecedence === null) {
                rhsParens = false;
              } else if (rhsPrecedence === precedence && associativity === "left" && !assocWithRhs) {
                rhsParens = true;
              } else if (rhsPrecedence < precedence) {
                rhsParens = true;
              } else {
                rhsParens = false;
              }
              if (latex2) {
                var _rootIdentifier;
                var lhsIdentifier;
                var rhsIdentifier;
                if (parenthesis === "keep") {
                  _rootIdentifier = root.getIdentifier();
                  lhsIdentifier = root.args[0].getIdentifier();
                  rhsIdentifier = root.args[1].getIdentifier();
                } else {
                  _rootIdentifier = root.getContent().getIdentifier();
                  lhsIdentifier = root.args[0].getContent().getIdentifier();
                  rhsIdentifier = root.args[1].getContent().getIdentifier();
                }
                if (lhsPrecedence !== null) {
                  if (operators.properties[precedence][_rootIdentifier].latexLeftParens === false) {
                    lhsParens = false;
                  }
                  if (operators.properties[lhsPrecedence][lhsIdentifier].latexParens === false) {
                    lhsParens = false;
                  }
                }
                if (rhsPrecedence !== null) {
                  if (operators.properties[precedence][_rootIdentifier].latexRightParens === false) {
                    rhsParens = false;
                  }
                  if (operators.properties[rhsPrecedence][rhsIdentifier].latexParens === false) {
                    rhsParens = false;
                  }
                }
              }
              result = [lhsParens, rhsParens];
              break;
            default:
              if (root.getIdentifier() === "OperatorNode:add" || root.getIdentifier() === "OperatorNode:multiply") {
                result = args.map(function(arg) {
                  var argPrecedence = operators.getPrecedence(arg, parenthesis);
                  var assocWithArg = operators.isAssociativeWith(root, arg, parenthesis);
                  var argAssociativity = operators.getAssociativity(arg, parenthesis);
                  if (argPrecedence === null) {
                    return false;
                  } else if (precedence === argPrecedence && associativity === argAssociativity && !assocWithArg) {
                    return true;
                  } else if (argPrecedence < precedence) {
                    return true;
                  }
                  return false;
                });
              }
              break;
          }
          if (args.length >= 2 && root.getIdentifier() === "OperatorNode:multiply" && root.implicit && parenthesis === "auto" && implicit === "hide") {
            result = args.map(function(arg, index) {
              var isParenthesisNode = arg.getIdentifier() === "ParenthesisNode";
              if (result[index] || isParenthesisNode) {
                return true;
              }
              return false;
            });
          }
          return result;
        }
        OperatorNode.prototype._toString = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var implicit = options && options.implicit ? options.implicit : "hide";
          var args = this.args;
          var parens = calculateNecessaryParentheses(this, parenthesis, implicit, args, false);
          if (args.length === 1) {
            var assoc = operators.getAssociativity(this, parenthesis);
            var operand = args[0].toString(options);
            if (parens[0]) {
              operand = "(" + operand + ")";
            }
            var opIsNamed = /[a-zA-Z]+/.test(this.op);
            if (assoc === "right") {
              return this.op + (opIsNamed ? " " : "") + operand;
            } else if (assoc === "left") {
              return operand + (opIsNamed ? " " : "") + this.op;
            }
            return operand + this.op;
          } else if (args.length === 2) {
            var lhs = args[0].toString(options);
            var rhs = args[1].toString(options);
            if (parens[0]) {
              lhs = "(" + lhs + ")";
            }
            if (parens[1]) {
              rhs = "(" + rhs + ")";
            }
            if (this.implicit && this.getIdentifier() === "OperatorNode:multiply" && implicit === "hide") {
              return lhs + " " + rhs;
            }
            return lhs + " " + this.op + " " + rhs;
          } else if (args.length > 2 && (this.getIdentifier() === "OperatorNode:add" || this.getIdentifier() === "OperatorNode:multiply")) {
            var stringifiedArgs = args.map(function(arg, index) {
              arg = arg.toString(options);
              if (parens[index]) {
                arg = "(" + arg + ")";
              }
              return arg;
            });
            if (this.implicit && this.getIdentifier() === "OperatorNode:multiply" && implicit === "hide") {
              return stringifiedArgs.join(" ");
            }
            return stringifiedArgs.join(" " + this.op + " ");
          } else {
            return this.fn + "(" + this.args.join(", ") + ")";
          }
        };
        OperatorNode.prototype.toJSON = function() {
          return {
            mathjs: "OperatorNode",
            op: this.op,
            fn: this.fn,
            args: this.args,
            implicit: this.implicit
          };
        };
        OperatorNode.fromJSON = function(json) {
          return new OperatorNode(json.op, json.fn, json.args, json.implicit);
        };
        OperatorNode.prototype.toHTML = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var implicit = options && options.implicit ? options.implicit : "hide";
          var args = this.args;
          var parens = calculateNecessaryParentheses(this, parenthesis, implicit, args, false);
          if (args.length === 1) {
            var assoc = operators.getAssociativity(this, parenthesis);
            var operand = args[0].toHTML(options);
            if (parens[0]) {
              operand = '<span class="math-parenthesis math-round-parenthesis">(</span>' + operand + '<span class="math-parenthesis math-round-parenthesis">)</span>';
            }
            if (assoc === "right") {
              return '<span class="math-operator math-unary-operator math-lefthand-unary-operator">' + escape(this.op) + "</span>" + operand;
            } else {
              return operand + '<span class="math-operator math-unary-operator math-righthand-unary-operator">' + escape(this.op) + "</span>";
            }
          } else if (args.length === 2) {
            var lhs = args[0].toHTML(options);
            var rhs = args[1].toHTML(options);
            if (parens[0]) {
              lhs = '<span class="math-parenthesis math-round-parenthesis">(</span>' + lhs + '<span class="math-parenthesis math-round-parenthesis">)</span>';
            }
            if (parens[1]) {
              rhs = '<span class="math-parenthesis math-round-parenthesis">(</span>' + rhs + '<span class="math-parenthesis math-round-parenthesis">)</span>';
            }
            if (this.implicit && this.getIdentifier() === "OperatorNode:multiply" && implicit === "hide") {
              return lhs + '<span class="math-operator math-binary-operator math-implicit-binary-operator"></span>' + rhs;
            }
            return lhs + '<span class="math-operator math-binary-operator math-explicit-binary-operator">' + escape(this.op) + "</span>" + rhs;
          } else {
            var stringifiedArgs = args.map(function(arg, index) {
              arg = arg.toHTML(options);
              if (parens[index]) {
                arg = '<span class="math-parenthesis math-round-parenthesis">(</span>' + arg + '<span class="math-parenthesis math-round-parenthesis">)</span>';
              }
              return arg;
            });
            if (args.length > 2 && (this.getIdentifier() === "OperatorNode:add" || this.getIdentifier() === "OperatorNode:multiply")) {
              if (this.implicit && this.getIdentifier() === "OperatorNode:multiply" && implicit === "hide") {
                return stringifiedArgs.join('<span class="math-operator math-binary-operator math-implicit-binary-operator"></span>');
              }
              return stringifiedArgs.join('<span class="math-operator math-binary-operator math-explicit-binary-operator">' + escape(this.op) + "</span>");
            } else {
              return '<span class="math-function">' + escape(this.fn) + '</span><span class="math-paranthesis math-round-parenthesis">(</span>' + stringifiedArgs.join('<span class="math-separator">,</span>') + '<span class="math-paranthesis math-round-parenthesis">)</span>';
            }
          }
        };
        OperatorNode.prototype._toTex = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var implicit = options && options.implicit ? options.implicit : "hide";
          var args = this.args;
          var parens = calculateNecessaryParentheses(this, parenthesis, implicit, args, true);
          var op = latex.operators[this.fn];
          op = typeof op === "undefined" ? this.op : op;
          if (args.length === 1) {
            var assoc = operators.getAssociativity(this, parenthesis);
            var operand = args[0].toTex(options);
            if (parens[0]) {
              operand = "\\left(".concat(operand, "\\right)");
            }
            if (assoc === "right") {
              return op + operand;
            } else if (assoc === "left") {
              return operand + op;
            }
            return operand + op;
          } else if (args.length === 2) {
            var lhs = args[0];
            var lhsTex = lhs.toTex(options);
            if (parens[0]) {
              lhsTex = "\\left(".concat(lhsTex, "\\right)");
            }
            var rhs = args[1];
            var rhsTex = rhs.toTex(options);
            if (parens[1]) {
              rhsTex = "\\left(".concat(rhsTex, "\\right)");
            }
            var lhsIdentifier;
            if (parenthesis === "keep") {
              lhsIdentifier = lhs.getIdentifier();
            } else {
              lhsIdentifier = lhs.getContent().getIdentifier();
            }
            switch (this.getIdentifier()) {
              case "OperatorNode:divide":
                return op + "{" + lhsTex + "}{" + rhsTex + "}";
              case "OperatorNode:pow":
                lhsTex = "{" + lhsTex + "}";
                rhsTex = "{" + rhsTex + "}";
                switch (lhsIdentifier) {
                  case "ConditionalNode":
                  //
                  case "OperatorNode:divide":
                    lhsTex = "\\left(".concat(lhsTex, "\\right)");
                }
                break;
              case "OperatorNode:multiply":
                if (this.implicit && implicit === "hide") {
                  return lhsTex + "~" + rhsTex;
                }
            }
            return lhsTex + op + rhsTex;
          } else if (args.length > 2 && (this.getIdentifier() === "OperatorNode:add" || this.getIdentifier() === "OperatorNode:multiply")) {
            var texifiedArgs = args.map(function(arg, index) {
              arg = arg.toTex(options);
              if (parens[index]) {
                arg = "\\left(".concat(arg, "\\right)");
              }
              return arg;
            });
            if (this.getIdentifier() === "OperatorNode:multiply" && this.implicit) {
              return texifiedArgs.join("~");
            }
            return texifiedArgs.join(op);
          } else {
            return "\\mathrm{" + this.fn + "}\\left(" + args.map(function(arg) {
              return arg.toTex(options);
            }).join(",") + "\\right)";
          }
        };
        OperatorNode.prototype.getIdentifier = function() {
          return this.type + ":" + this.fn;
        };
        return OperatorNode;
      }
      exports.name = "OperatorNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/ParenthesisNode.js
  var require_ParenthesisNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/ParenthesisNode.js"(exports) {
      "use strict";
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        function ParenthesisNode(content) {
          if (!(this instanceof ParenthesisNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          if (!type.isNode(content)) {
            throw new TypeError('Node expected for parameter "content"');
          }
          this.content = content;
        }
        ParenthesisNode.prototype = new Node();
        ParenthesisNode.prototype.type = "ParenthesisNode";
        ParenthesisNode.prototype.isParenthesisNode = true;
        ParenthesisNode.prototype._compile = function(math2, argNames) {
          return this.content._compile(math2, argNames);
        };
        ParenthesisNode.prototype.getContent = function() {
          return this.content.getContent();
        };
        ParenthesisNode.prototype.forEach = function(callback) {
          callback(this.content, "content", this);
        };
        ParenthesisNode.prototype.map = function(callback) {
          var content = callback(this.content, "content", this);
          return new ParenthesisNode(content);
        };
        ParenthesisNode.prototype.clone = function() {
          return new ParenthesisNode(this.content);
        };
        ParenthesisNode.prototype._toString = function(options) {
          if (!options || options && !options.parenthesis || options && options.parenthesis === "keep") {
            return "(" + this.content.toString(options) + ")";
          }
          return this.content.toString(options);
        };
        ParenthesisNode.prototype.toJSON = function() {
          return {
            mathjs: "ParenthesisNode",
            content: this.content
          };
        };
        ParenthesisNode.fromJSON = function(json) {
          return new ParenthesisNode(json.content);
        };
        ParenthesisNode.prototype.toHTML = function(options) {
          if (!options || options && !options.parenthesis || options && options.parenthesis === "keep") {
            return '<span class="math-parenthesis math-round-parenthesis">(</span>' + this.content.toHTML(options) + '<span class="math-parenthesis math-round-parenthesis">)</span>';
          }
          return this.content.toHTML(options);
        };
        ParenthesisNode.prototype._toTex = function(options) {
          if (!options || options && !options.parenthesis || options && options.parenthesis === "keep") {
            return "\\left(".concat(this.content.toTex(options), "\\right)");
          }
          return this.content.toTex(options);
        };
        return ParenthesisNode;
      }
      exports.name = "ParenthesisNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/SymbolNode.js
  var require_SymbolNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/SymbolNode.js"(exports) {
      "use strict";
      var latex = require_latex();
      var escape = require_string().escape;
      var hasOwnProperty = require_object().hasOwnProperty;
      var getSafeProperty = require_customs().getSafeProperty;
      function factory(type, config, load, typed, math2) {
        var Node = load(require_Node());
        function isValuelessUnit(name) {
          return type.Unit ? type.Unit.isValuelessUnit(name) : false;
        }
        function SymbolNode(name) {
          if (!(this instanceof SymbolNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          if (typeof name !== "string") throw new TypeError('String expected for parameter "name"');
          this.name = name;
        }
        SymbolNode.prototype = new Node();
        SymbolNode.prototype.type = "SymbolNode";
        SymbolNode.prototype.isSymbolNode = true;
        SymbolNode.prototype._compile = function(math3, argNames) {
          var name = this.name;
          if (hasOwnProperty(argNames, name)) {
            return function(scope, args, context) {
              return args[name];
            };
          } else if (name in math3) {
            return function(scope, args, context) {
              return name in scope ? getSafeProperty(scope, name) : getSafeProperty(math3, name);
            };
          } else {
            var isUnit = isValuelessUnit(name);
            return function(scope, args, context) {
              return name in scope ? getSafeProperty(scope, name) : isUnit ? new type.Unit(null, name) : undef(name);
            };
          }
        };
        SymbolNode.prototype.forEach = function(callback) {
        };
        SymbolNode.prototype.map = function(callback) {
          return this.clone();
        };
        function undef(name) {
          throw new Error("Undefined symbol " + name);
        }
        SymbolNode.prototype.clone = function() {
          return new SymbolNode(this.name);
        };
        SymbolNode.prototype._toString = function(options) {
          return this.name;
        };
        SymbolNode.prototype.toHTML = function(options) {
          var name = escape(this.name);
          if (name === "true" || name === "false") {
            return '<span class="math-symbol math-boolean">' + name + "</span>";
          } else if (name === "i") {
            return '<span class="math-symbol math-imaginary-symbol">' + name + "</span>";
          } else if (name === "Infinity") {
            return '<span class="math-symbol math-infinity-symbol">' + name + "</span>";
          } else if (name === "NaN") {
            return '<span class="math-symbol math-nan-symbol">' + name + "</span>";
          } else if (name === "null") {
            return '<span class="math-symbol math-null-symbol">' + name + "</span>";
          } else if (name === "undefined") {
            return '<span class="math-symbol math-undefined-symbol">' + name + "</span>";
          }
          return '<span class="math-symbol">' + name + "</span>";
        };
        SymbolNode.prototype.toJSON = function() {
          return {
            mathjs: "SymbolNode",
            name: this.name
          };
        };
        SymbolNode.fromJSON = function(json) {
          return new SymbolNode(json.name);
        };
        SymbolNode.prototype._toTex = function(options) {
          var isUnit = false;
          if (typeof math2[this.name] === "undefined" && isValuelessUnit(this.name)) {
            isUnit = true;
          }
          var symbol = latex.toSymbol(this.name, isUnit);
          if (symbol[0] === "\\") {
            return symbol;
          }
          return " " + symbol;
        };
        return SymbolNode;
      }
      exports.name = "SymbolNode";
      exports.path = "expression.node";
      exports.math = true;
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/FunctionNode.js
  var require_FunctionNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/FunctionNode.js"(exports) {
      "use strict";
      function _typeof(obj) {
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _extends() {
        _extends = Object.assign || function(target) {
          for (var i = 1; i < arguments.length; i++) {
            var source = arguments[i];
            for (var key in source) {
              if (Object.prototype.hasOwnProperty.call(source, key)) {
                target[key] = source[key];
              }
            }
          }
          return target;
        };
        return _extends.apply(this, arguments);
      }
      var latex = require_latex();
      var escape = require_string().escape;
      var hasOwnProperty = require_object().hasOwnProperty;
      var map = require_array().map;
      var validateSafeMethod = require_customs().validateSafeMethod;
      var getSafeProperty = require_customs().getSafeProperty;
      function factory(type, config, load, typed, math2) {
        var Node = load(require_Node());
        var SymbolNode = load(require_SymbolNode());
        function FunctionNode(fn, args) {
          if (!(this instanceof FunctionNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          if (typeof fn === "string") {
            fn = new SymbolNode(fn);
          }
          if (!type.isNode(fn)) throw new TypeError('Node expected as parameter "fn"');
          if (!Array.isArray(args) || !args.every(type.isNode)) {
            throw new TypeError('Array containing Nodes expected for parameter "args"');
          }
          this.fn = fn;
          this.args = args || [];
          Object.defineProperty(this, "name", {
            get: function() {
              return this.fn.name || "";
            }.bind(this),
            set: function set() {
              throw new Error("Cannot assign a new name, name is read-only");
            }
          });
          var deprecated = function deprecated2() {
            throw new Error("Property `FunctionNode.object` is deprecated, use `FunctionNode.fn` instead");
          };
          Object.defineProperty(this, "object", {
            get: deprecated,
            set: deprecated
          });
        }
        FunctionNode.prototype = new Node();
        FunctionNode.prototype.type = "FunctionNode";
        FunctionNode.prototype.isFunctionNode = true;
        FunctionNode.prototype._compile = function(math3, argNames) {
          if (!(this instanceof FunctionNode)) {
            throw new TypeError("No valid FunctionNode");
          }
          var evalArgs = map(this.args, function(arg) {
            return arg._compile(math3, argNames);
          });
          if (type.isSymbolNode(this.fn)) {
            var name = this.fn.name;
            var fn = name in math3 ? getSafeProperty(math3, name) : void 0;
            var isRaw = typeof fn === "function" && fn.rawArgs === true;
            if (isRaw) {
              var rawArgs = this.args;
              return function evalFunctionNode(scope, args, context) {
                return (name in scope ? getSafeProperty(scope, name) : fn)(rawArgs, math3, _extends({}, scope, args));
              };
            } else {
              if (evalArgs.length === 1) {
                var evalArg0 = evalArgs[0];
                return function evalFunctionNode(scope, args, context) {
                  return (name in scope ? getSafeProperty(scope, name) : fn)(evalArg0(scope, args, context));
                };
              } else if (evalArgs.length === 2) {
                var _evalArg = evalArgs[0];
                var evalArg1 = evalArgs[1];
                return function evalFunctionNode(scope, args, context) {
                  return (name in scope ? getSafeProperty(scope, name) : fn)(_evalArg(scope, args, context), evalArg1(scope, args, context));
                };
              } else {
                return function evalFunctionNode(scope, args, context) {
                  return (name in scope ? getSafeProperty(scope, name) : fn).apply(null, map(evalArgs, function(evalArg) {
                    return evalArg(scope, args, context);
                  }));
                };
              }
            }
          } else if (type.isAccessorNode(this.fn) && type.isIndexNode(this.fn.index) && this.fn.index.isObjectProperty()) {
            var evalObject = this.fn.object._compile(math3, argNames);
            var prop = this.fn.index.getObjectProperty();
            var _rawArgs = this.args;
            return function evalFunctionNode(scope, args, context) {
              var object = evalObject(scope, args, context);
              validateSafeMethod(object, prop);
              var isRaw2 = object[prop] && object[prop].rawArgs;
              return isRaw2 ? object[prop](_rawArgs, math3, _extends({}, scope, args)) : object[prop].apply(object, map(evalArgs, function(evalArg) {
                return evalArg(scope, args, context);
              }));
            };
          } else {
            var evalFn = this.fn._compile(math3, argNames);
            var _rawArgs2 = this.args;
            return function evalFunctionNode(scope, args, context) {
              var fn2 = evalFn(scope, args, context);
              var isRaw2 = fn2 && fn2.rawArgs;
              return isRaw2 ? fn2(_rawArgs2, math3, _extends({}, scope, args)) : fn2.apply(fn2, map(evalArgs, function(evalArg) {
                return evalArg(scope, args, context);
              }));
            };
          }
        };
        FunctionNode.prototype.forEach = function(callback) {
          callback(this.fn, "fn", this);
          for (var i = 0; i < this.args.length; i++) {
            callback(this.args[i], "args[" + i + "]", this);
          }
        };
        FunctionNode.prototype.map = function(callback) {
          var fn = this._ifNode(callback(this.fn, "fn", this));
          var args = [];
          for (var i = 0; i < this.args.length; i++) {
            args[i] = this._ifNode(callback(this.args[i], "args[" + i + "]", this));
          }
          return new FunctionNode(fn, args);
        };
        FunctionNode.prototype.clone = function() {
          return new FunctionNode(this.fn, this.args.slice(0));
        };
        var nodeToString = FunctionNode.prototype.toString;
        FunctionNode.prototype.toString = function(options) {
          var customString;
          var name = this.fn.toString(options);
          if (options && _typeof(options.handler) === "object" && hasOwnProperty(options.handler, name)) {
            customString = options.handler[name](this, options);
          }
          if (typeof customString !== "undefined") {
            return customString;
          }
          return nodeToString.call(this, options);
        };
        FunctionNode.prototype._toString = function(options) {
          var args = this.args.map(function(arg) {
            return arg.toString(options);
          });
          var fn = type.isFunctionAssignmentNode(this.fn) ? "(" + this.fn.toString(options) + ")" : this.fn.toString(options);
          return fn + "(" + args.join(", ") + ")";
        };
        FunctionNode.prototype.toJSON = function() {
          return {
            mathjs: "FunctionNode",
            fn: this.fn,
            args: this.args
          };
        };
        FunctionNode.fromJSON = function(json) {
          return new FunctionNode(json.fn, json.args);
        };
        FunctionNode.prototype.toHTML = function(options) {
          var args = this.args.map(function(arg) {
            return arg.toHTML(options);
          });
          return '<span class="math-function">' + escape(this.fn) + '</span><span class="math-paranthesis math-round-parenthesis">(</span>' + args.join('<span class="math-separator">,</span>') + '<span class="math-paranthesis math-round-parenthesis">)</span>';
        };
        function expandTemplate(template, node, options) {
          var latex2 = "";
          var regex = new RegExp("\\$(?:\\{([a-z_][a-z_0-9]*)(?:\\[([0-9]+)\\])?\\}|\\$)", "ig");
          var inputPos = 0;
          var match;
          while ((match = regex.exec(template)) !== null) {
            latex2 += template.substring(inputPos, match.index);
            inputPos = match.index;
            if (match[0] === "$$") {
              latex2 += "$";
              inputPos++;
            } else {
              inputPos += match[0].length;
              var property = node[match[1]];
              if (!property) {
                throw new ReferenceError("Template: Property " + match[1] + " does not exist.");
              }
              if (match[2] === void 0) {
                switch (_typeof(property)) {
                  case "string":
                    latex2 += property;
                    break;
                  case "object":
                    if (type.isNode(property)) {
                      latex2 += property.toTex(options);
                    } else if (Array.isArray(property)) {
                      latex2 += property.map(function(arg, index) {
                        if (type.isNode(arg)) {
                          return arg.toTex(options);
                        }
                        throw new TypeError("Template: " + match[1] + "[" + index + "] is not a Node.");
                      }).join(",");
                    } else {
                      throw new TypeError("Template: " + match[1] + " has to be a Node, String or array of Nodes");
                    }
                    break;
                  default:
                    throw new TypeError("Template: " + match[1] + " has to be a Node, String or array of Nodes");
                }
              } else {
                if (type.isNode(property[match[2]] && property[match[2]])) {
                  latex2 += property[match[2]].toTex(options);
                } else {
                  throw new TypeError("Template: " + match[1] + "[" + match[2] + "] is not a Node.");
                }
              }
            }
          }
          latex2 += template.slice(inputPos);
          return latex2;
        }
        var nodeToTex = FunctionNode.prototype.toTex;
        FunctionNode.prototype.toTex = function(options) {
          var customTex;
          if (options && _typeof(options.handler) === "object" && hasOwnProperty(options.handler, this.name)) {
            customTex = options.handler[this.name](this, options);
          }
          if (typeof customTex !== "undefined") {
            return customTex;
          }
          return nodeToTex.call(this, options);
        };
        FunctionNode.prototype._toTex = function(options) {
          var args = this.args.map(function(arg) {
            return arg.toTex(options);
          });
          var latexConverter;
          if (math2[this.name] && (typeof math2[this.name].toTex === "function" || _typeof(math2[this.name].toTex) === "object" || typeof math2[this.name].toTex === "string")) {
            latexConverter = math2[this.name].toTex;
          }
          var customToTex;
          switch (_typeof(latexConverter)) {
            case "function":
              customToTex = latexConverter(this, options);
              break;
            case "string":
              customToTex = expandTemplate(latexConverter, this, options);
              break;
            case "object":
              switch (_typeof(latexConverter[args.length])) {
                case "function":
                  customToTex = latexConverter[args.length](this, options);
                  break;
                case "string":
                  customToTex = expandTemplate(latexConverter[args.length], this, options);
                  break;
              }
          }
          if (typeof customToTex !== "undefined") {
            return customToTex;
          }
          return expandTemplate(latex.defaultTemplate, this, options);
        };
        FunctionNode.prototype.getIdentifier = function() {
          return this.type + ":" + this.name;
        };
        return FunctionNode;
      }
      exports.name = "FunctionNode";
      exports.path = "expression.node";
      exports.math = true;
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/RangeNode.js
  var require_RangeNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/RangeNode.js"(exports) {
      "use strict";
      var operators = require_operators();
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        function RangeNode(start, end, step) {
          if (!(this instanceof RangeNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          if (!type.isNode(start)) throw new TypeError("Node expected");
          if (!type.isNode(end)) throw new TypeError("Node expected");
          if (step && !type.isNode(step)) throw new TypeError("Node expected");
          if (arguments.length > 3) throw new Error("Too many arguments");
          this.start = start;
          this.end = end;
          this.step = step || null;
        }
        RangeNode.prototype = new Node();
        RangeNode.prototype.type = "RangeNode";
        RangeNode.prototype.isRangeNode = true;
        RangeNode.prototype.needsEnd = function() {
          var endSymbols = this.filter(function(node) {
            return type.isSymbolNode(node) && node.name === "end";
          });
          return endSymbols.length > 0;
        };
        RangeNode.prototype._compile = function(math2, argNames) {
          var range = math2.range;
          var evalStart = this.start._compile(math2, argNames);
          var evalEnd = this.end._compile(math2, argNames);
          if (this.step) {
            var evalStep = this.step._compile(math2, argNames);
            return function evalRangeNode(scope, args, context) {
              return range(evalStart(scope, args, context), evalEnd(scope, args, context), evalStep(scope, args, context));
            };
          } else {
            return function evalRangeNode(scope, args, context) {
              return range(evalStart(scope, args, context), evalEnd(scope, args, context));
            };
          }
        };
        RangeNode.prototype.forEach = function(callback) {
          callback(this.start, "start", this);
          callback(this.end, "end", this);
          if (this.step) {
            callback(this.step, "step", this);
          }
        };
        RangeNode.prototype.map = function(callback) {
          return new RangeNode(this._ifNode(callback(this.start, "start", this)), this._ifNode(callback(this.end, "end", this)), this.step && this._ifNode(callback(this.step, "step", this)));
        };
        RangeNode.prototype.clone = function() {
          return new RangeNode(this.start, this.end, this.step && this.step);
        };
        function calculateNecessaryParentheses(node, parenthesis) {
          var precedence = operators.getPrecedence(node, parenthesis);
          var parens = {};
          var startPrecedence = operators.getPrecedence(node.start, parenthesis);
          parens.start = startPrecedence !== null && startPrecedence <= precedence || parenthesis === "all";
          if (node.step) {
            var stepPrecedence = operators.getPrecedence(node.step, parenthesis);
            parens.step = stepPrecedence !== null && stepPrecedence <= precedence || parenthesis === "all";
          }
          var endPrecedence = operators.getPrecedence(node.end, parenthesis);
          parens.end = endPrecedence !== null && endPrecedence <= precedence || parenthesis === "all";
          return parens;
        }
        RangeNode.prototype._toString = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var parens = calculateNecessaryParentheses(this, parenthesis);
          var str;
          var start = this.start.toString(options);
          if (parens.start) {
            start = "(" + start + ")";
          }
          str = start;
          if (this.step) {
            var step = this.step.toString(options);
            if (parens.step) {
              step = "(" + step + ")";
            }
            str += ":" + step;
          }
          var end = this.end.toString(options);
          if (parens.end) {
            end = "(" + end + ")";
          }
          str += ":" + end;
          return str;
        };
        RangeNode.prototype.toJSON = function() {
          return {
            mathjs: "RangeNode",
            start: this.start,
            end: this.end,
            step: this.step
          };
        };
        RangeNode.fromJSON = function(json) {
          return new RangeNode(json.start, json.end, json.step);
        };
        RangeNode.prototype.toHTML = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var parens = calculateNecessaryParentheses(this, parenthesis);
          var str;
          var start = this.start.toHTML(options);
          if (parens.start) {
            start = '<span class="math-parenthesis math-round-parenthesis">(</span>' + start + '<span class="math-parenthesis math-round-parenthesis">)</span>';
          }
          str = start;
          if (this.step) {
            var step = this.step.toHTML(options);
            if (parens.step) {
              step = '<span class="math-parenthesis math-round-parenthesis">(</span>' + step + '<span class="math-parenthesis math-round-parenthesis">)</span>';
            }
            str += '<span class="math-operator math-range-operator">:</span>' + step;
          }
          var end = this.end.toHTML(options);
          if (parens.end) {
            end = '<span class="math-parenthesis math-round-parenthesis">(</span>' + end + '<span class="math-parenthesis math-round-parenthesis">)</span>';
          }
          str += '<span class="math-operator math-range-operator">:</span>' + end;
          return str;
        };
        RangeNode.prototype._toTex = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var parens = calculateNecessaryParentheses(this, parenthesis);
          var str = this.start.toTex(options);
          if (parens.start) {
            str = "\\left(".concat(str, "\\right)");
          }
          if (this.step) {
            var step = this.step.toTex(options);
            if (parens.step) {
              step = "\\left(".concat(step, "\\right)");
            }
            str += ":" + step;
          }
          var end = this.end.toTex(options);
          if (parens.end) {
            end = "\\left(".concat(end, "\\right)");
          }
          str += ":" + end;
          return str;
        };
        return RangeNode;
      }
      exports.name = "RangeNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/node/RelationalNode.js
  var require_RelationalNode = __commonJS({
    "node_modules/mathjs/lib/expression/node/RelationalNode.js"(exports) {
      "use strict";
      var operators = require_operators();
      var latex = require_latex();
      var escape = require_string().escape;
      function factory(type, config, load, typed) {
        var Node = load(require_Node());
        var getSafeProperty = require_customs().getSafeProperty;
        function RelationalNode(conditionals, params) {
          if (!(this instanceof RelationalNode)) {
            throw new SyntaxError("Constructor must be called with the new operator");
          }
          if (!Array.isArray(conditionals)) throw new TypeError("Parameter conditionals must be an array");
          if (!Array.isArray(params)) throw new TypeError("Parameter params must be an array");
          if (conditionals.length !== params.length - 1) throw new TypeError("Parameter params must contain exactly one more element than parameter conditionals");
          this.conditionals = conditionals;
          this.params = params;
        }
        RelationalNode.prototype = new Node();
        RelationalNode.prototype.type = "RelationalNode";
        RelationalNode.prototype.isRelationalNode = true;
        RelationalNode.prototype._compile = function(math2, argNames) {
          var self = this;
          var compiled = this.params.map(function(p) {
            return p._compile(math2, argNames);
          });
          return function evalRelationalNode(scope, args, context) {
            var evalLhs;
            var evalRhs = compiled[0](scope, args, context);
            for (var i = 0; i < self.conditionals.length; i++) {
              evalLhs = evalRhs;
              evalRhs = compiled[i + 1](scope, args, context);
              var condFn = getSafeProperty(math2, self.conditionals[i]);
              if (!condFn(evalLhs, evalRhs)) {
                return false;
              }
            }
            return true;
          };
        };
        RelationalNode.prototype.forEach = function(callback) {
          var _this = this;
          this.params.forEach(function(n, i) {
            return callback(n, "params[" + i + "]", _this);
          }, this);
        };
        RelationalNode.prototype.map = function(callback) {
          var _this2 = this;
          return new RelationalNode(this.conditionals.slice(), this.params.map(function(n, i) {
            return _this2._ifNode(callback(n, "params[" + i + "]", _this2));
          }, this));
        };
        RelationalNode.prototype.clone = function() {
          return new RelationalNode(this.conditionals, this.params);
        };
        RelationalNode.prototype._toString = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var precedence = operators.getPrecedence(this, parenthesis);
          var paramStrings = this.params.map(function(p, index) {
            var paramPrecedence = operators.getPrecedence(p, parenthesis);
            return parenthesis === "all" || paramPrecedence !== null && paramPrecedence <= precedence ? "(" + p.toString(options) + ")" : p.toString(options);
          });
          var operatorMap = {
            "equal": "==",
            "unequal": "!=",
            "smaller": "<",
            "larger": ">",
            "smallerEq": "<=",
            "largerEq": ">="
          };
          var ret = paramStrings[0];
          for (var i = 0; i < this.conditionals.length; i++) {
            ret += " " + operatorMap[this.conditionals[i]] + " " + paramStrings[i + 1];
          }
          return ret;
        };
        RelationalNode.prototype.toJSON = function() {
          return {
            mathjs: "RelationalNode",
            conditionals: this.conditionals,
            params: this.params
          };
        };
        RelationalNode.fromJSON = function(json) {
          return new RelationalNode(json.conditionals, json.params);
        };
        RelationalNode.prototype.toHTML = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var precedence = operators.getPrecedence(this, parenthesis);
          var paramStrings = this.params.map(function(p, index) {
            var paramPrecedence = operators.getPrecedence(p, parenthesis);
            return parenthesis === "all" || paramPrecedence !== null && paramPrecedence <= precedence ? '<span class="math-parenthesis math-round-parenthesis">(</span>' + p.toHTML(options) + '<span class="math-parenthesis math-round-parenthesis">)</span>' : p.toHTML(options);
          });
          var operatorMap = {
            "equal": "==",
            "unequal": "!=",
            "smaller": "<",
            "larger": ">",
            "smallerEq": "<=",
            "largerEq": ">="
          };
          var ret = paramStrings[0];
          for (var i = 0; i < this.conditionals.length; i++) {
            ret += '<span class="math-operator math-binary-operator math-explicit-binary-operator">' + escape(operatorMap[this.conditionals[i]]) + "</span>" + paramStrings[i + 1];
          }
          return ret;
        };
        RelationalNode.prototype._toTex = function(options) {
          var parenthesis = options && options.parenthesis ? options.parenthesis : "keep";
          var precedence = operators.getPrecedence(this, parenthesis);
          var paramStrings = this.params.map(function(p, index) {
            var paramPrecedence = operators.getPrecedence(p, parenthesis);
            return parenthesis === "all" || paramPrecedence !== null && paramPrecedence <= precedence ? "\\left(" + p.toTex(options) + "\right)" : p.toTex(options);
          });
          var ret = paramStrings[0];
          for (var i = 0; i < this.conditionals.length; i++) {
            ret += latex.operators[this.conditionals[i]] + paramStrings[i + 1];
          }
          return ret;
        };
        return RelationalNode;
      }
      exports.name = "RelationalNode";
      exports.path = "expression.node";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/parse.js
  var require_parse = __commonJS({
    "node_modules/mathjs/lib/expression/parse.js"(exports) {
      "use strict";
      function _extends() {
        _extends = Object.assign || function(target) {
          for (var i = 1; i < arguments.length; i++) {
            var source = arguments[i];
            for (var key in source) {
              if (Object.prototype.hasOwnProperty.call(source, key)) {
                target[key] = source[key];
              }
            }
          }
          return target;
        };
        return _extends.apply(this, arguments);
      }
      var ArgumentsError = require_ArgumentsError();
      var deepMap = require_deepMap();
      function factory(type, config, load, typed) {
        var numeric = load(require_numeric());
        var AccessorNode = load(require_AccessorNode());
        var ArrayNode = load(require_ArrayNode());
        var AssignmentNode = load(require_AssignmentNode());
        var BlockNode = load(require_BlockNode());
        var ConditionalNode = load(require_ConditionalNode());
        var ConstantNode = load(require_ConstantNode());
        var FunctionAssignmentNode = load(require_FunctionAssignmentNode());
        var IndexNode = load(require_IndexNode());
        var ObjectNode = load(require_ObjectNode());
        var OperatorNode = load(require_OperatorNode());
        var ParenthesisNode = load(require_ParenthesisNode());
        var FunctionNode = load(require_FunctionNode());
        var RangeNode = load(require_RangeNode());
        var RelationalNode = load(require_RelationalNode());
        var SymbolNode = load(require_SymbolNode());
        function parse2(expr, options) {
          if (arguments.length !== 1 && arguments.length !== 2) {
            throw new ArgumentsError("parse", arguments.length, 1, 2);
          }
          var extraNodes = options && options.nodes ? options.nodes : {};
          if (typeof expr === "string") {
            return parseStart(expr, extraNodes);
          } else if (Array.isArray(expr) || expr instanceof type.Matrix) {
            return deepMap(expr, function(elem) {
              if (typeof elem !== "string") throw new TypeError("String expected");
              return parseStart(elem, extraNodes);
            });
          } else {
            throw new TypeError("String or matrix expected");
          }
        }
        var TOKENTYPE = {
          NULL: 0,
          DELIMITER: 1,
          NUMBER: 2,
          SYMBOL: 3,
          UNKNOWN: 4
          // map with all delimiters
        };
        var DELIMITERS = {
          ",": true,
          "(": true,
          ")": true,
          "[": true,
          "]": true,
          "{": true,
          "}": true,
          '"': true,
          "'": true,
          ";": true,
          "+": true,
          "-": true,
          "*": true,
          ".*": true,
          "/": true,
          "./": true,
          "%": true,
          "^": true,
          ".^": true,
          "~": true,
          "!": true,
          "&": true,
          "|": true,
          "^|": true,
          "=": true,
          ":": true,
          "?": true,
          "==": true,
          "!=": true,
          "<": true,
          ">": true,
          "<=": true,
          ">=": true,
          "<<": true,
          ">>": true,
          ">>>": true
          // map with all named delimiters
        };
        var NAMED_DELIMITERS = {
          "mod": true,
          "to": true,
          "in": true,
          "and": true,
          "xor": true,
          "or": true,
          "not": true
        };
        var CONSTANTS = {
          "true": true,
          "false": false,
          "null": null,
          "undefined": void 0
        };
        var NUMERIC_CONSTANTS = ["NaN", "Infinity"];
        function initialState() {
          return {
            extraNodes: {},
            // current extra nodes, must be careful not to mutate
            expression: "",
            // current expression
            comment: "",
            // last parsed comment
            index: 0,
            // current index in expr
            token: "",
            // current token
            tokenType: TOKENTYPE.NULL,
            // type of the token
            nestingLevel: 0,
            // level of nesting inside parameters, used to ignore newline characters
            conditionalLevel: null
            // when a conditional is being parsed, the level of the conditional is stored here
          };
        }
        function currentString(state, length) {
          return state.expression.substr(state.index, length);
        }
        function currentCharacter(state) {
          return currentString(state, 1);
        }
        function next(state) {
          state.index++;
        }
        function prevCharacter(state) {
          return state.expression.charAt(state.index - 1);
        }
        function nextCharacter(state) {
          return state.expression.charAt(state.index + 1);
        }
        function getToken(state) {
          state.tokenType = TOKENTYPE.NULL;
          state.token = "";
          state.comment = "";
          while (parse2.isWhitespace(currentCharacter(state), state.nestingLevel)) {
            next(state);
          }
          if (currentCharacter(state) === "#") {
            while (currentCharacter(state) !== "\n" && currentCharacter(state) !== "") {
              state.comment += currentCharacter(state);
              next(state);
            }
          }
          if (currentCharacter(state) === "") {
            state.tokenType = TOKENTYPE.DELIMITER;
            return;
          }
          if (currentCharacter(state) === "\n" && !state.nestingLevel) {
            state.tokenType = TOKENTYPE.DELIMITER;
            state.token = currentCharacter(state);
            next(state);
            return;
          }
          var c1 = currentCharacter(state);
          var c2 = currentString(state, 2);
          var c3 = currentString(state, 3);
          if (c3.length === 3 && DELIMITERS[c3]) {
            state.tokenType = TOKENTYPE.DELIMITER;
            state.token = c3;
            next(state);
            next(state);
            next(state);
            return;
          }
          if (c2.length === 2 && DELIMITERS[c2]) {
            state.tokenType = TOKENTYPE.DELIMITER;
            state.token = c2;
            next(state);
            next(state);
            return;
          }
          if (DELIMITERS[c1]) {
            state.tokenType = TOKENTYPE.DELIMITER;
            state.token = c1;
            next(state);
            return;
          }
          if (parse2.isDigitDot(c1)) {
            state.tokenType = TOKENTYPE.NUMBER;
            if (currentCharacter(state) === ".") {
              state.token += currentCharacter(state);
              next(state);
              if (!parse2.isDigit(currentCharacter(state))) {
                state.tokenType = TOKENTYPE.DELIMITER;
              }
            } else {
              while (parse2.isDigit(currentCharacter(state))) {
                state.token += currentCharacter(state);
                next(state);
              }
              if (parse2.isDecimalMark(currentCharacter(state), nextCharacter(state))) {
                state.token += currentCharacter(state);
                next(state);
              }
            }
            while (parse2.isDigit(currentCharacter(state))) {
              state.token += currentCharacter(state);
              next(state);
            }
            if (currentCharacter(state) === "E" || currentCharacter(state) === "e") {
              if (parse2.isDigit(nextCharacter(state)) || nextCharacter(state) === "-" || nextCharacter(state) === "+") {
                state.token += currentCharacter(state);
                next(state);
                if (currentCharacter(state) === "+" || currentCharacter(state) === "-") {
                  state.token += currentCharacter(state);
                  next(state);
                }
                if (!parse2.isDigit(currentCharacter(state))) {
                  throw createSyntaxError(state, 'Digit expected, got "' + currentCharacter(state) + '"');
                }
                while (parse2.isDigit(currentCharacter(state))) {
                  state.token += currentCharacter(state);
                  next(state);
                }
                if (parse2.isDecimalMark(currentCharacter(state), nextCharacter(state))) {
                  throw createSyntaxError(state, 'Digit expected, got "' + currentCharacter(state) + '"');
                }
              } else if (nextCharacter(state) === ".") {
                next(state);
                throw createSyntaxError(state, 'Digit expected, got "' + currentCharacter(state) + '"');
              }
            }
            return;
          }
          if (parse2.isAlpha(currentCharacter(state), prevCharacter(state), nextCharacter(state))) {
            while (parse2.isAlpha(currentCharacter(state), prevCharacter(state), nextCharacter(state)) || parse2.isDigit(currentCharacter(state))) {
              state.token += currentCharacter(state);
              next(state);
            }
            if (NAMED_DELIMITERS.hasOwnProperty(state.token)) {
              state.tokenType = TOKENTYPE.DELIMITER;
            } else {
              state.tokenType = TOKENTYPE.SYMBOL;
            }
            return;
          }
          state.tokenType = TOKENTYPE.UNKNOWN;
          while (currentCharacter(state) !== "") {
            state.token += currentCharacter(state);
            next(state);
          }
          throw createSyntaxError(state, 'Syntax error in part "' + state.token + '"');
        }
        function getTokenSkipNewline(state) {
          do {
            getToken(state);
          } while (state.token === "\n");
        }
        function openParams(state) {
          state.nestingLevel++;
        }
        function closeParams(state) {
          state.nestingLevel--;
        }
        parse2.isAlpha = function isAlpha(c, cPrev, cNext) {
          return parse2.isValidLatinOrGreek(c) || parse2.isValidMathSymbol(c, cNext) || parse2.isValidMathSymbol(cPrev, c);
        };
        parse2.isValidLatinOrGreek = function isValidLatinOrGreek(c) {
          return /^[a-zA-Z_$\u00C0-\u02AF\u0370-\u03FF\u2100-\u214F]$/.test(c);
        };
        parse2.isValidMathSymbol = function isValidMathSymbol(high, low) {
          return /^[\uD835]$/.test(high) && /^[\uDC00-\uDFFF]$/.test(low) && /^[^\uDC55\uDC9D\uDCA0\uDCA1\uDCA3\uDCA4\uDCA7\uDCA8\uDCAD\uDCBA\uDCBC\uDCC4\uDD06\uDD0B\uDD0C\uDD15\uDD1D\uDD3A\uDD3F\uDD45\uDD47-\uDD49\uDD51\uDEA6\uDEA7\uDFCC\uDFCD]$/.test(low);
        };
        parse2.isWhitespace = function isWhitespace(c, nestingLevel) {
          return c === " " || c === "	" || c === "\n" && nestingLevel > 0;
        };
        parse2.isDecimalMark = function isDecimalMark(c, cNext) {
          return c === "." && cNext !== "/" && cNext !== "*" && cNext !== "^";
        };
        parse2.isDigitDot = function isDigitDot(c) {
          return c >= "0" && c <= "9" || c === ".";
        };
        parse2.isDigit = function isDigit(c) {
          return c >= "0" && c <= "9";
        };
        function parseStart(expression, extraNodes) {
          var state = initialState();
          _extends(state, {
            expression,
            extraNodes
          });
          getToken(state);
          var node = parseBlock(state);
          if (state.token !== "") {
            if (state.tokenType === TOKENTYPE.DELIMITER) {
              throw createError(state, "Unexpected operator " + state.token);
            } else {
              throw createSyntaxError(state, 'Unexpected part "' + state.token + '"');
            }
          }
          return node;
        }
        function parseBlock(state) {
          var node;
          var blocks = [];
          var visible;
          if (state.token !== "" && state.token !== "\n" && state.token !== ";") {
            node = parseAssignment(state);
            node.comment = state.comment;
          }
          while (state.token === "\n" || state.token === ";") {
            if (blocks.length === 0 && node) {
              visible = state.token !== ";";
              blocks.push({
                node,
                visible
              });
            }
            getToken(state);
            if (state.token !== "\n" && state.token !== ";" && state.token !== "") {
              node = parseAssignment(state);
              node.comment = state.comment;
              visible = state.token !== ";";
              blocks.push({
                node,
                visible
              });
            }
          }
          if (blocks.length > 0) {
            return new BlockNode(blocks);
          } else {
            if (!node) {
              node = new ConstantNode(void 0);
              node.comment = state.comment;
            }
            return node;
          }
        }
        function parseAssignment(state) {
          var name, args, value, valid;
          var node = parseConditional(state);
          if (state.token === "=") {
            if (type.isSymbolNode(node)) {
              name = node.name;
              getTokenSkipNewline(state);
              value = parseAssignment(state);
              return new AssignmentNode(new SymbolNode(name), value);
            } else if (type.isAccessorNode(node)) {
              getTokenSkipNewline(state);
              value = parseAssignment(state);
              return new AssignmentNode(node.object, node.index, value);
            } else if (type.isFunctionNode(node) && type.isSymbolNode(node.fn)) {
              valid = true;
              args = [];
              name = node.name;
              node.args.forEach(function(arg, index) {
                if (type.isSymbolNode(arg)) {
                  args[index] = arg.name;
                } else {
                  valid = false;
                }
              });
              if (valid) {
                getTokenSkipNewline(state);
                value = parseAssignment(state);
                return new FunctionAssignmentNode(name, args, value);
              }
            }
            throw createSyntaxError(state, "Invalid left hand side of assignment operator =");
          }
          return node;
        }
        function parseConditional(state) {
          var node = parseLogicalOr(state);
          while (state.token === "?") {
            var prev = state.conditionalLevel;
            state.conditionalLevel = state.nestingLevel;
            getTokenSkipNewline(state);
            var condition = node;
            var trueExpr = parseAssignment(state);
            if (state.token !== ":") throw createSyntaxError(state, "False part of conditional expression expected");
            state.conditionalLevel = null;
            getTokenSkipNewline(state);
            var falseExpr = parseAssignment(state);
            node = new ConditionalNode(condition, trueExpr, falseExpr);
            state.conditionalLevel = prev;
          }
          return node;
        }
        function parseLogicalOr(state) {
          var node = parseLogicalXor(state);
          while (state.token === "or") {
            getTokenSkipNewline(state);
            node = new OperatorNode("or", "or", [node, parseLogicalXor(state)]);
          }
          return node;
        }
        function parseLogicalXor(state) {
          var node = parseLogicalAnd(state);
          while (state.token === "xor") {
            getTokenSkipNewline(state);
            node = new OperatorNode("xor", "xor", [node, parseLogicalAnd(state)]);
          }
          return node;
        }
        function parseLogicalAnd(state) {
          var node = parseBitwiseOr(state);
          while (state.token === "and") {
            getTokenSkipNewline(state);
            node = new OperatorNode("and", "and", [node, parseBitwiseOr(state)]);
          }
          return node;
        }
        function parseBitwiseOr(state) {
          var node = parseBitwiseXor(state);
          while (state.token === "|") {
            getTokenSkipNewline(state);
            node = new OperatorNode("|", "bitOr", [node, parseBitwiseXor(state)]);
          }
          return node;
        }
        function parseBitwiseXor(state) {
          var node = parseBitwiseAnd(state);
          while (state.token === "^|") {
            getTokenSkipNewline(state);
            node = new OperatorNode("^|", "bitXor", [node, parseBitwiseAnd(state)]);
          }
          return node;
        }
        function parseBitwiseAnd(state) {
          var node = parseRelational(state);
          while (state.token === "&") {
            getTokenSkipNewline(state);
            node = new OperatorNode("&", "bitAnd", [node, parseRelational(state)]);
          }
          return node;
        }
        function parseRelational(state) {
          var params = [parseShift(state)];
          var conditionals = [];
          var operators = {
            "==": "equal",
            "!=": "unequal",
            "<": "smaller",
            ">": "larger",
            "<=": "smallerEq",
            ">=": "largerEq"
          };
          while (operators.hasOwnProperty(state.token)) {
            var cond = {
              name: state.token,
              fn: operators[state.token]
            };
            conditionals.push(cond);
            getTokenSkipNewline(state);
            params.push(parseShift(state));
          }
          if (params.length === 1) {
            return params[0];
          } else if (params.length === 2) {
            return new OperatorNode(conditionals[0].name, conditionals[0].fn, params);
          } else {
            return new RelationalNode(conditionals.map(function(c) {
              return c.fn;
            }), params);
          }
        }
        function parseShift(state) {
          var node, operators, name, fn, params;
          node = parseConversion(state);
          operators = {
            "<<": "leftShift",
            ">>": "rightArithShift",
            ">>>": "rightLogShift"
          };
          while (operators.hasOwnProperty(state.token)) {
            name = state.token;
            fn = operators[name];
            getTokenSkipNewline(state);
            params = [node, parseConversion(state)];
            node = new OperatorNode(name, fn, params);
          }
          return node;
        }
        function parseConversion(state) {
          var node, operators, name, fn, params;
          node = parseRange(state);
          operators = {
            "to": "to",
            "in": "to"
            // alias of 'to'
          };
          while (operators.hasOwnProperty(state.token)) {
            name = state.token;
            fn = operators[name];
            getTokenSkipNewline(state);
            if (name === "in" && state.token === "") {
              node = new OperatorNode("*", "multiply", [node, new SymbolNode("in")], true);
            } else {
              params = [node, parseRange(state)];
              node = new OperatorNode(name, fn, params);
            }
          }
          return node;
        }
        function parseRange(state) {
          var node;
          var params = [];
          if (state.token === ":") {
            node = new ConstantNode(1);
          } else {
            node = parseAddSubtract(state);
          }
          if (state.token === ":" && state.conditionalLevel !== state.nestingLevel) {
            params.push(node);
            while (state.token === ":" && params.length < 3) {
              getTokenSkipNewline(state);
              if (state.token === ")" || state.token === "]" || state.token === "," || state.token === "") {
                params.push(new SymbolNode("end"));
              } else {
                params.push(parseAddSubtract(state));
              }
            }
            if (params.length === 3) {
              node = new RangeNode(params[0], params[2], params[1]);
            } else {
              node = new RangeNode(params[0], params[1]);
            }
          }
          return node;
        }
        function parseAddSubtract(state) {
          var node, operators, name, fn, params;
          node = parseMultiplyDivide(state);
          operators = {
            "+": "add",
            "-": "subtract"
          };
          while (operators.hasOwnProperty(state.token)) {
            name = state.token;
            fn = operators[name];
            getTokenSkipNewline(state);
            params = [node, parseMultiplyDivide(state)];
            node = new OperatorNode(name, fn, params);
          }
          return node;
        }
        function parseMultiplyDivide(state) {
          var node, last, operators, name, fn;
          node = parseImplicitMultiplication(state);
          last = node;
          operators = {
            "*": "multiply",
            ".*": "dotMultiply",
            "/": "divide",
            "./": "dotDivide",
            "%": "mod",
            "mod": "mod"
          };
          while (true) {
            if (operators.hasOwnProperty(state.token)) {
              name = state.token;
              fn = operators[name];
              getTokenSkipNewline(state);
              last = parseImplicitMultiplication(state);
              node = new OperatorNode(name, fn, [node, last]);
            } else {
              break;
            }
          }
          return node;
        }
        function parseImplicitMultiplication(state) {
          var node, last;
          node = parseRule2(state);
          last = node;
          while (true) {
            if (state.tokenType === TOKENTYPE.SYMBOL || state.token === "in" && type.isConstantNode(node) || state.tokenType === TOKENTYPE.NUMBER && !type.isConstantNode(last) && (!type.isOperatorNode(last) || last.op === "!") || state.token === "(") {
              last = parseRule2(state);
              node = new OperatorNode(
                "*",
                "multiply",
                [node, last],
                true
                /* implicit */
              );
            } else {
              break;
            }
          }
          return node;
        }
        function parseRule2(state) {
          var node = parseUnary(state);
          var last = node;
          var tokenStates = [];
          while (true) {
            if (state.token === "/" && type.isConstantNode(last)) {
              tokenStates.push(_extends({}, state));
              getTokenSkipNewline(state);
              if (state.tokenType === TOKENTYPE.NUMBER) {
                tokenStates.push(_extends({}, state));
                getTokenSkipNewline(state);
                if (state.tokenType === TOKENTYPE.SYMBOL || state.token === "(") {
                  _extends(state, tokenStates.pop());
                  tokenStates.pop();
                  last = parseUnary(state);
                  node = new OperatorNode("/", "divide", [node, last]);
                } else {
                  tokenStates.pop();
                  _extends(state, tokenStates.pop());
                  break;
                }
              } else {
                _extends(state, tokenStates.pop());
                break;
              }
            } else {
              break;
            }
          }
          return node;
        }
        function parseUnary(state) {
          var name, params, fn;
          var operators = {
            "-": "unaryMinus",
            "+": "unaryPlus",
            "~": "bitNot",
            "not": "not"
          };
          if (operators.hasOwnProperty(state.token)) {
            fn = operators[state.token];
            name = state.token;
            getTokenSkipNewline(state);
            params = [parseUnary(state)];
            return new OperatorNode(name, fn, params);
          }
          return parsePow(state);
        }
        function parsePow(state) {
          var node, name, fn, params;
          node = parseLeftHandOperators(state);
          if (state.token === "^" || state.token === ".^") {
            name = state.token;
            fn = name === "^" ? "pow" : "dotPow";
            getTokenSkipNewline(state);
            params = [node, parseUnary(state)];
            node = new OperatorNode(name, fn, params);
          }
          return node;
        }
        function parseLeftHandOperators(state) {
          var node, operators, name, fn, params;
          node = parseCustomNodes(state);
          operators = {
            "!": "factorial",
            "'": "ctranspose"
          };
          while (operators.hasOwnProperty(state.token)) {
            name = state.token;
            fn = operators[name];
            getToken(state);
            params = [node];
            node = new OperatorNode(name, fn, params);
            node = parseAccessors(state, node);
          }
          return node;
        }
        function parseCustomNodes(state) {
          var params = [];
          if (state.tokenType === TOKENTYPE.SYMBOL && state.extraNodes.hasOwnProperty(state.token)) {
            var CustomNode = state.extraNodes[state.token];
            getToken(state);
            if (state.token === "(") {
              params = [];
              openParams(state);
              getToken(state);
              if (state.token !== ")") {
                params.push(parseAssignment(state));
                while (state.token === ",") {
                  getToken(state);
                  params.push(parseAssignment(state));
                }
              }
              if (state.token !== ")") {
                throw createSyntaxError(state, "Parenthesis ) expected");
              }
              closeParams(state);
              getToken(state);
            }
            return new CustomNode(params);
          }
          return parseSymbol(state);
        }
        function parseSymbol(state) {
          var node, name;
          if (state.tokenType === TOKENTYPE.SYMBOL || state.tokenType === TOKENTYPE.DELIMITER && state.token in NAMED_DELIMITERS) {
            name = state.token;
            getToken(state);
            if (CONSTANTS.hasOwnProperty(name)) {
              node = new ConstantNode(CONSTANTS[name]);
            } else if (NUMERIC_CONSTANTS.indexOf(name) !== -1) {
              node = new ConstantNode(numeric(name, "number"));
            } else {
              node = new SymbolNode(name);
            }
            node = parseAccessors(state, node);
            return node;
          }
          return parseDoubleQuotesString(state);
        }
        function parseAccessors(state, node, types) {
          var params;
          while ((state.token === "(" || state.token === "[" || state.token === ".") && (!types || types.indexOf(state.token) !== -1)) {
            params = [];
            if (state.token === "(") {
              if (type.isSymbolNode(node) || type.isAccessorNode(node)) {
                openParams(state);
                getToken(state);
                if (state.token !== ")") {
                  params.push(parseAssignment(state));
                  while (state.token === ",") {
                    getToken(state);
                    params.push(parseAssignment(state));
                  }
                }
                if (state.token !== ")") {
                  throw createSyntaxError(state, "Parenthesis ) expected");
                }
                closeParams(state);
                getToken(state);
                node = new FunctionNode(node, params);
              } else {
                return node;
              }
            } else if (state.token === "[") {
              openParams(state);
              getToken(state);
              if (state.token !== "]") {
                params.push(parseAssignment(state));
                while (state.token === ",") {
                  getToken(state);
                  params.push(parseAssignment(state));
                }
              }
              if (state.token !== "]") {
                throw createSyntaxError(state, "Parenthesis ] expected");
              }
              closeParams(state);
              getToken(state);
              node = new AccessorNode(node, new IndexNode(params));
            } else {
              getToken(state);
              if (state.tokenType !== TOKENTYPE.SYMBOL) {
                throw createSyntaxError(state, "Property name expected after dot");
              }
              params.push(new ConstantNode(state.token));
              getToken(state);
              var dotNotation = true;
              node = new AccessorNode(node, new IndexNode(params, dotNotation));
            }
          }
          return node;
        }
        function parseDoubleQuotesString(state) {
          var node, str;
          if (state.token === '"') {
            str = parseDoubleQuotesStringToken(state);
            node = new ConstantNode(str);
            node = parseAccessors(state, node);
            return node;
          }
          return parseSingleQuotesString(state);
        }
        function parseDoubleQuotesStringToken(state) {
          var str = "";
          while (currentCharacter(state) !== "" && currentCharacter(state) !== '"') {
            if (currentCharacter(state) === "\\") {
              str += currentCharacter(state);
              next(state);
            }
            str += currentCharacter(state);
            next(state);
          }
          getToken(state);
          if (state.token !== '"') {
            throw createSyntaxError(state, 'End of string " expected');
          }
          getToken(state);
          return JSON.parse('"' + str + '"');
        }
        function parseSingleQuotesString(state) {
          var node, str;
          if (state.token === "'") {
            str = parseSingleQuotesStringToken(state);
            node = new ConstantNode(str);
            node = parseAccessors(state, node);
            return node;
          }
          return parseMatrix(state);
        }
        function parseSingleQuotesStringToken(state) {
          var str = "";
          while (currentCharacter(state) !== "" && currentCharacter(state) !== "'") {
            if (currentCharacter(state) === "\\") {
              str += currentCharacter(state);
              next(state);
            }
            str += currentCharacter(state);
            next(state);
          }
          getToken(state);
          if (state.token !== "'") {
            throw createSyntaxError(state, "End of string ' expected");
          }
          getToken(state);
          return JSON.parse('"' + str + '"');
        }
        function parseMatrix(state) {
          var array, params, rows, cols;
          if (state.token === "[") {
            openParams(state);
            getToken(state);
            if (state.token !== "]") {
              var row = parseRow(state);
              if (state.token === ";") {
                rows = 1;
                params = [row];
                while (state.token === ";") {
                  getToken(state);
                  params[rows] = parseRow(state);
                  rows++;
                }
                if (state.token !== "]") {
                  throw createSyntaxError(state, "End of matrix ] expected");
                }
                closeParams(state);
                getToken(state);
                cols = params[0].items.length;
                for (var r = 1; r < rows; r++) {
                  if (params[r].items.length !== cols) {
                    throw createError(state, "Column dimensions mismatch (" + params[r].items.length + " !== " + cols + ")");
                  }
                }
                array = new ArrayNode(params);
              } else {
                if (state.token !== "]") {
                  throw createSyntaxError(state, "End of matrix ] expected");
                }
                closeParams(state);
                getToken(state);
                array = row;
              }
            } else {
              closeParams(state);
              getToken(state);
              array = new ArrayNode([]);
            }
            return parseAccessors(state, array);
          }
          return parseObject(state);
        }
        function parseRow(state) {
          var params = [parseAssignment(state)];
          var len = 1;
          while (state.token === ",") {
            getToken(state);
            params[len] = parseAssignment(state);
            len++;
          }
          return new ArrayNode(params);
        }
        function parseObject(state) {
          if (state.token === "{") {
            openParams(state);
            var key;
            var properties = {};
            do {
              getToken(state);
              if (state.token !== "}") {
                if (state.token === '"') {
                  key = parseDoubleQuotesStringToken(state);
                } else if (state.token === "'") {
                  key = parseSingleQuotesStringToken(state);
                } else if (state.tokenType === TOKENTYPE.SYMBOL) {
                  key = state.token;
                  getToken(state);
                } else {
                  throw createSyntaxError(state, "Symbol or string expected as object key");
                }
                if (state.token !== ":") {
                  throw createSyntaxError(state, "Colon : expected after object key");
                }
                getToken(state);
                properties[key] = parseAssignment(state);
              }
            } while (state.token === ",");
            if (state.token !== "}") {
              throw createSyntaxError(state, "Comma , or bracket } expected after object value");
            }
            closeParams(state);
            getToken(state);
            var node = new ObjectNode(properties);
            node = parseAccessors(state, node);
            return node;
          }
          return parseNumber(state);
        }
        function parseNumber(state) {
          var numberStr;
          if (state.tokenType === TOKENTYPE.NUMBER) {
            numberStr = state.token;
            getToken(state);
            return new ConstantNode(numeric(numberStr, config.number));
          }
          return parseParentheses(state);
        }
        function parseParentheses(state) {
          var node;
          if (state.token === "(") {
            openParams(state);
            getToken(state);
            node = parseAssignment(state);
            if (state.token !== ")") {
              throw createSyntaxError(state, "Parenthesis ) expected");
            }
            closeParams(state);
            getToken(state);
            node = new ParenthesisNode(node);
            node = parseAccessors(state, node);
            return node;
          }
          return parseEnd(state);
        }
        function parseEnd(state) {
          if (state.token === "") {
            throw createSyntaxError(state, "Unexpected end of expression");
          } else {
            throw createSyntaxError(state, "Value expected");
          }
        }
        function col(state) {
          return state.index - state.token.length + 1;
        }
        function createSyntaxError(state, message) {
          var c = col(state);
          var error = new SyntaxError(message + " (char " + c + ")");
          error["char"] = c;
          return error;
        }
        function createError(state, message) {
          var c = col(state);
          var error = new SyntaxError(message + " (char " + c + ")");
          error["char"] = c;
          return error;
        }
        return parse2;
      }
      exports.name = "parse";
      exports.path = "expression";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/function/parse.js
  var require_parse2 = __commonJS({
    "node_modules/mathjs/lib/expression/function/parse.js"(exports) {
      "use strict";
      function factory(type, config, load, typed) {
        var parse2 = load(require_parse());
        return typed("parse", {
          "string | Array | Matrix": parse2,
          "string | Array | Matrix, Object": parse2
        });
      }
      exports.name = "parse";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/function/compile.js
  var require_compile = __commonJS({
    "node_modules/mathjs/lib/expression/function/compile.js"(exports) {
      "use strict";
      var deepMap = require_deepMap();
      function factory(type, config, load, typed) {
        var parse2 = load(require_parse());
        return typed("compile", {
          "string": function string(expr) {
            return parse2(expr).compile();
          },
          "Array | Matrix": function ArrayMatrix(expr) {
            return deepMap(expr, function(entry) {
              return parse2(entry).compile();
            });
          }
        });
      }
      exports.name = "compile";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/expression/function/eval.js
  var require_eval = __commonJS({
    "node_modules/mathjs/lib/expression/function/eval.js"(exports) {
      "use strict";
      var deepMap = require_deepMap();
      function factory(type, config, load, typed) {
        var parse2 = load(require_parse());
        return typed("compile", {
          "string": function string(expr) {
            var scope = {};
            return parse2(expr).compile().eval(scope);
          },
          "string, Object": function stringObject(expr, scope) {
            return parse2(expr).compile().eval(scope);
          },
          "Array | Matrix": function ArrayMatrix(expr) {
            var scope = {};
            return deepMap(expr, function(entry) {
              return parse2(entry).compile().eval(scope);
            });
          },
          "Array | Matrix, Object": function ArrayMatrixObject(expr, scope) {
            return deepMap(expr, function(entry) {
              return parse2(entry).compile().eval(scope);
            });
          }
        });
      }
      exports.name = "eval";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs/lib/function/string/format.js
  var require_format = __commonJS({
    "node_modules/mathjs/lib/function/string/format.js"(exports) {
      "use strict";
      var string = require_string();
      function factory(type, config, load, typed) {
        var format = typed("format", {
          "any": string.format,
          "any, Object | function | number": string.format
        });
        format.toTex = void 0;
        return format;
      }
      exports.name = "format";
      exports.factory = factory;
    }
  });

  // node_modules/mathjs-expression-parser/index.js
  var require_mathjs_expression_parser = __commonJS({
    "node_modules/mathjs-expression-parser/index.js"(exports, module) {
      var core = require_core2();
      var math2 = core.create();
      math2.import(require_parse2());
      math2.import(require_compile());
      math2.import(require_eval());
      math2.import(require_format());
      math2.import({
        // arithmetic
        add: function(a, b) {
          return a + b;
        },
        subtract: function(a, b) {
          return a - b;
        },
        multiply: function(a, b) {
          return a * b;
        },
        divide: function(a, b) {
          return a / b;
        },
        mod: function(a, b) {
          return a % b;
        },
        unaryPlus: function(a) {
          return a;
        },
        unaryMinus: function(a) {
          return -a;
        },
        // bitwise
        bitOr: function(a, b) {
          return a | b;
        },
        bitXor: function(a, b) {
          return a ^ b;
        },
        bitAnd: function(a, b) {
          return a & b;
        },
        bitNot: function(a) {
          return ~a;
        },
        leftShift: function(a, b) {
          return a << b;
        },
        rightArithShift: function(a, b) {
          return a >> b;
        },
        rightLogShift: function(a, b) {
          return a >>> b;
        },
        // logical
        or: function(a, b) {
          return !!(a || b);
        },
        xor: function(a, b) {
          return !!a !== !!b;
        },
        and: function(a, b) {
          return !!(a && b);
        },
        not: function(a) {
          return !a;
        },
        // relational
        equal: function(a, b) {
          return a == b;
        },
        unequal: function(a, b) {
          return a != b;
        },
        smaller: function(a, b) {
          return a < b;
        },
        larger: function(a, b) {
          return a > b;
        },
        smallerEq: function(a, b) {
          return a <= b;
        },
        largerEq: function(a, b) {
          return a >= b;
        },
        // matrix
        // matrix: function (a) { return a },
        matrix: function() {
          throw new Error("Matrices not supported");
        },
        index: function() {
          throw new Error("Matrix indexes not supported");
        },
        // add pi and e as lowercase
        pi: Math.PI,
        e: Math.E,
        "true": true,
        "false": false,
        "null": null
      });
      var allFromMath = {};
      Object.getOwnPropertyNames(Math).forEach(function(name) {
        if (!Object.prototype.hasOwnProperty(name)) {
          allFromMath[name] = Math[name];
        }
      });
      math2.import(allFromMath);
      module.exports = math2;
    }
  });

  // node_modules/interactive-shader-format/src/ISFGLState.js
  var ISFGLState, ISFGLState_default;
  var init_ISFGLState = __esm({
    "node_modules/interactive-shader-format/src/ISFGLState.js"() {
      ISFGLState = function ISFGLState2(gl) {
        this.gl = gl;
        this.textureIndex = 0;
      };
      ISFGLState.prototype.newTextureIndex = function newTextureIndex() {
        const i = this.textureIndex;
        this.textureIndex += 1;
        return i;
      };
      ISFGLState.prototype.reset = function reset() {
        this.textureIndex = 0;
      };
      ISFGLState_default = ISFGLState;
    }
  });

  // node_modules/interactive-shader-format/src/ISFGLProgram.js
  function ISFGLProgram(gl, vs, fs) {
    this.gl = gl;
    this.vShader = this.createShader(vs, this.gl.VERTEX_SHADER);
    this.fShader = this.createShader(fs, this.gl.FRAGMENT_SHADER);
    this.program = this.createProgram(this.vShader, this.fShader);
    this.locations = {};
  }
  var ISFGLProgram_default;
  var init_ISFGLProgram = __esm({
    "node_modules/interactive-shader-format/src/ISFGLProgram.js"() {
      ISFGLProgram.prototype.use = function glProgramUse() {
        this.gl.useProgram(this.program);
      };
      ISFGLProgram.prototype.getUniformLocation = function getUniformLocation(name) {
        return this.gl.getUniformLocation(this.program, name);
      };
      ISFGLProgram.prototype.bindVertices = function bindVertices() {
        this.use();
        const positionLocation = this.gl.getAttribLocation(this.program, "isf_position");
        this.buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.buffer);
        const vertexArray = new Float32Array(
          [
            -1,
            -1,
            1,
            -1,
            -1,
            1,
            -1,
            1,
            1,
            -1,
            1,
            1
          ]
        );
        this.gl.bufferData(this.gl.ARRAY_BUFFER, vertexArray, this.gl.STATIC_DRAW);
        this.gl.enableVertexAttribArray(positionLocation);
        this.gl.vertexAttribPointer(positionLocation, 2, this.gl.FLOAT, false, 0, 0);
      };
      ISFGLProgram.prototype.cleanup = function cleanup() {
        this.gl.deleteShader(this.fShader);
        this.gl.deleteShader(this.vShader);
        this.gl.deleteProgram(this.program);
        this.gl.deleteBuffer(this.buffer);
      };
      ISFGLProgram.prototype.createShader = function createShader(src, type) {
        const shader = this.gl.createShader(type);
        this.gl.shaderSource(shader, src);
        this.gl.compileShader(shader);
        const compiled = this.gl.getShaderParameter(shader, this.gl.COMPILE_STATUS);
        if (!compiled) {
          const lastError = this.gl.getShaderInfoLog(shader);
          console.log("Error Compiling Shader ", lastError);
          throw new Error({
            message: lastError,
            type: "shader"
          });
        }
        return shader;
      };
      ISFGLProgram.prototype.createProgram = function createProgram(vShader, fShader) {
        const program = this.gl.createProgram();
        this.gl.attachShader(program, vShader);
        this.gl.attachShader(program, fShader);
        this.gl.linkProgram(program);
        const linked = this.gl.getProgramParameter(program, this.gl.LINK_STATUS);
        if (!linked) {
          const lastError = this.gl.getProgramInfoLog(program);
          console.log("Error in program linking", lastError);
          throw new Error({
            message: lastError,
            type: "program"
          });
        }
        return program;
      };
      ISFGLProgram_default = ISFGLProgram;
    }
  });

  // node_modules/interactive-shader-format/src/ISFTexture.js
  function ISFTexture(params, contextState) {
    if (params == null) {
      params = {};
    }
    this.contextState = contextState;
    this.float = params.float;
    this.gl = this.contextState.gl;
    this.texture = this.gl.createTexture();
    this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, this.gl.LINEAR);
    this.gl.pixelStorei(this.gl.UNPACK_FLIP_Y_WEBGL, true);
    this.gl.bindTexture(this.gl.TEXTURE_2D, null);
  }
  var ISFTexture_default;
  var init_ISFTexture = __esm({
    "node_modules/interactive-shader-format/src/ISFTexture.js"() {
      ISFTexture.prototype.bind = function textureBind(location) {
        if (location === null || location === void 0) {
          location = -1;
        }
        const newTexUnit = this.contextState.newTextureIndex();
        this.gl.activeTexture(this.gl.TEXTURE0 + newTexUnit);
        this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
        if (location !== -1) {
          this.gl.uniform1i(location, newTexUnit);
        }
      };
      ISFTexture.prototype.setSize = function setSize(w, h) {
        if (this.width !== w || this.height !== h) {
          this.width = w;
          this.height = h;
          const pixelType = this.float ? this.gl.FLOAT : this.gl.UNSIGNED_BYTE;
          this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
          this.gl.texImage2D(this.gl.TEXTURE_2D, 0, this.gl.RGBA, w, h, 0, this.gl.RGBA, pixelType, null);
        }
      };
      ISFTexture.prototype.destroy = function destroy() {
        this.gl.deleteTexture(this.texture);
      };
      ISFTexture_default = ISFTexture;
    }
  });

  // node_modules/interactive-shader-format/src/ISFBuffer.js
  function ISFBuffer(pass, contextState) {
    this.contextState = contextState;
    this.gl = this.contextState.gl;
    this.persistent = pass.persistent;
    this.name = pass.target;
    this.textures = [];
    this.textures.push(new ISFTexture_default(pass, this.contextState));
    this.textures.push(new ISFTexture_default(pass, this.contextState));
    this.flipFlop = false;
    this.fbo = this.gl.createFramebuffer();
    this.flipFlop = false;
  }
  var ISFBuffer_default;
  var init_ISFBuffer = __esm({
    "node_modules/interactive-shader-format/src/ISFBuffer.js"() {
      init_ISFTexture();
      ISFBuffer.prototype.setSize = function setSize2(w, h) {
        if (this.width !== w || this.height !== h) {
          this.width = w;
          this.height = h;
          for (let i = 0; i < this.textures.length; i++) {
            const texture = this.textures[i];
            texture.setSize(w, h);
          }
        }
      };
      ISFBuffer.prototype.readTexture = function readTexture() {
        if (this.flipFlop) {
          return this.textures[1];
        }
        return this.textures[0];
      };
      ISFBuffer.prototype.writeTexture = function writeTexture() {
        if (!this.flipFlop) {
          return this.textures[1];
        }
        return this.textures[0];
      };
      ISFBuffer.prototype.flip = function flip() {
        this.flipFlop = !this.flipFlop;
      };
      ISFBuffer.prototype.destroy = function destroy2() {
        for (let i = 0; i < this.textures.length; i++) {
          const texture = this.textures[i];
          texture.destroy();
        }
        this.gl.deleteFramebuffer(this.fbo);
      };
      ISFBuffer_default = ISFBuffer;
    }
  });

  // node_modules/interactive-shader-format/vendor/json_parse.js
  var require_json_parse = __commonJS({
    "node_modules/interactive-shader-format/vendor/json_parse.js"(exports, module) {
      module.exports = (function() {
        "use strict";
        var at;
        var ch;
        var escapee = {
          '"': '"',
          "\\": "\\",
          "/": "/",
          b: "\b",
          f: "\f",
          n: "\n",
          r: "\r",
          t: "	"
        };
        var text;
        var error = function(m) {
          throw {
            name: "SyntaxError",
            message: m,
            at,
            text
          };
        };
        var next = function(c) {
          if (c && c !== ch) {
            error("Expected '" + c + "' instead of '" + ch + "'");
          }
          ch = text.charAt(at);
          at += 1;
          return ch;
        };
        var number = function() {
          var value2;
          var string2 = "";
          if (ch === "-") {
            string2 = "-";
            next("-");
          }
          while (ch >= "0" && ch <= "9") {
            string2 += ch;
            next();
          }
          if (ch === ".") {
            string2 += ".";
            while (next() && ch >= "0" && ch <= "9") {
              string2 += ch;
            }
          }
          if (ch === "e" || ch === "E") {
            string2 += ch;
            next();
            if (ch === "-" || ch === "+") {
              string2 += ch;
              next();
            }
            while (ch >= "0" && ch <= "9") {
              string2 += ch;
              next();
            }
          }
          value2 = +string2;
          if (!isFinite(value2)) {
            error("Bad number");
          } else {
            return value2;
          }
        };
        var string = function() {
          var hex;
          var i;
          var value2 = "";
          var uffff;
          if (ch === '"') {
            while (next()) {
              if (ch === '"') {
                next();
                return value2;
              }
              if (ch === "\\") {
                next();
                if (ch === "u") {
                  uffff = 0;
                  for (i = 0; i < 4; i += 1) {
                    hex = parseInt(next(), 16);
                    if (!isFinite(hex)) {
                      break;
                    }
                    uffff = uffff * 16 + hex;
                  }
                  value2 += String.fromCharCode(uffff);
                } else if (typeof escapee[ch] === "string") {
                  value2 += escapee[ch];
                } else {
                  break;
                }
              } else {
                value2 += ch;
              }
            }
          }
          error("Bad string");
        };
        var white = function() {
          while (ch && ch <= " ") {
            next();
          }
        };
        var word = function() {
          switch (ch) {
            case "t":
              next("t");
              next("r");
              next("u");
              next("e");
              return true;
            case "f":
              next("f");
              next("a");
              next("l");
              next("s");
              next("e");
              return false;
            case "n":
              next("n");
              next("u");
              next("l");
              next("l");
              return null;
          }
          error("Unexpected '" + ch + "'");
        };
        var value;
        var array = function() {
          var arr = [];
          if (ch === "[") {
            next("[");
            white();
            if (ch === "]") {
              next("]");
              return arr;
            }
            while (ch) {
              arr.push(value());
              white();
              if (ch === "]") {
                next("]");
                return arr;
              }
              next(",");
              white();
            }
          }
          error("Bad array");
        };
        var object = function() {
          var key;
          var obj = {};
          if (ch === "{") {
            next("{");
            white();
            if (ch === "}") {
              next("}");
              return obj;
            }
            while (ch) {
              key = string();
              white();
              next(":");
              if (Object.hasOwnProperty.call(obj, key)) {
                error("Duplicate key '" + key + "'");
              }
              obj[key] = value();
              white();
              if (ch === "}") {
                next("}");
                return obj;
              }
              next(",");
              white();
            }
          }
          error("Bad object");
        };
        value = function() {
          white();
          switch (ch) {
            case "{":
              return object();
            case "[":
              return array();
            case '"':
              return string();
            case "-":
              return number();
            default:
              return ch >= "0" && ch <= "9" ? number() : word();
          }
        };
        return function(source, reviver) {
          var result;
          text = source;
          at = 0;
          ch = " ";
          result = value();
          white();
          if (ch) {
            error("Syntax error");
          }
          return typeof reviver === "function" ? (function walk(holder, key) {
            var k;
            var v;
            var val = holder[key];
            if (val && typeof val === "object") {
              for (k in val) {
                if (Object.prototype.hasOwnProperty.call(val, k)) {
                  v = walk(val, k);
                  if (v !== void 0) {
                    val[k] = v;
                  } else {
                    delete val[k];
                  }
                }
              }
            }
            return reviver.call(holder, key, val);
          })({ "": result }, "") : result;
        };
      })();
    }
  });

  // node_modules/interactive-shader-format/src/MetadataExtractor.js
  function MetadataExtractor(rawFragmentShader) {
    const regex = /\*([^*]|[\r\n]|(\*+([^*/]|[\r\n])))*\*+/;
    const results = regex.exec(rawFragmentShader);
    if (!results) {
      throw new Error("There is no metadata here.");
    }
    let metadataString = results[0];
    metadataString = metadataString.substring(1, metadataString.length - 1);
    let metadata;
    try {
      metadata = (0, import_json_parse.default)(metadataString);
    } catch (e) {
      const loc = e.at;
      const message = e.message || "Invalid JSON";
      if (loc) {
        const lines = (metadataString || "").substring(0, loc).split(/\r\n|\r|\n/);
        const lineNumber = lines.length;
        const position = lines[lineNumber - 1].length;
        const errorText = `${METADATA_ERROR_PREFIX}: ${message}        at line ${lineNumber} and position ${position}`;
        const enrichedError = new Error(errorText);
        enrichedError.lineNumber = lineNumber;
        enrichedError.position = position;
        throw enrichedError;
      }
      throw new Error(`${METADATA_ERROR_PREFIX}: ${message}`);
    }
    const startIndex = rawFragmentShader.indexOf("/*");
    const endIndex = rawFragmentShader.indexOf("*/");
    return {
      objectValue: metadata,
      stringValue: metadataString,
      startIndex,
      endIndex
    };
  }
  var import_json_parse, METADATA_ERROR_PREFIX;
  var init_MetadataExtractor = __esm({
    "node_modules/interactive-shader-format/src/MetadataExtractor.js"() {
      import_json_parse = __toESM(require_json_parse());
      METADATA_ERROR_PREFIX = "Something is wrong with your ISF metadata";
    }
  });

  // node_modules/interactive-shader-format/src/ISFParser.js
  var typeUniformMap, ISFParser, ISFParser_default;
  var init_ISFParser = __esm({
    "node_modules/interactive-shader-format/src/ISFParser.js"() {
      init_MetadataExtractor();
      typeUniformMap = {
        float: "float",
        image: "sampler2D",
        bool: "bool",
        event: "bool",
        long: "int",
        color: "vec4",
        point2D: "vec2"
      };
      ISFParser = function ISFParser2() {
      };
      ISFParser.prototype.parse = function parse(rawFragmentShader, rawVertexShader) {
        try {
          this.valid = true;
          this.rawFragmentShader = rawFragmentShader;
          this.rawVertexShader = rawVertexShader || ISFParser.vertexShaderDefault;
          this.error = null;
          const metadataInfo = MetadataExtractor(this.rawFragmentShader);
          const metadata = metadataInfo.objectValue;
          const metadataString = metadataInfo.stringValue;
          this.metadata = metadata;
          this.credit = metadata.CREDIT;
          this.categories = metadata.CATEGORIES;
          this.inputs = metadata.INPUTS;
          this.imports = metadata.IMPORTED || {};
          this.description = metadata.DESCRIPTION;
          const passesArray = metadata.PASSES || [{}];
          this.passes = this.parsePasses(passesArray);
          const endOfMetadata = this.rawFragmentShader.indexOf(metadataString) + metadataString.length + 2;
          this.rawFragmentMain = this.rawFragmentShader.substring(endOfMetadata);
          this.generateShaders();
          this.inferFilterType();
          this.isfVersion = this.inferISFVersion();
        } catch (e) {
          this.valid = false;
          this.error = e;
          this.inputs = [];
          this.categories = [];
          this.credit = "";
          this.errorLine = e.lineNumber;
        }
      };
      ISFParser.prototype.parsePasses = function parsePasses(passesArray) {
        const passes = [];
        for (let i = 0; i < passesArray.length; ++i) {
          const passDefinition = passesArray[i];
          const pass = {};
          if (passDefinition.TARGET) pass.target = passDefinition.TARGET;
          pass.persistent = !!passDefinition.PERSISTENT;
          pass.width = passDefinition.WIDTH || "$WIDTH";
          pass.height = passDefinition.HEIGHT || "$HEIGHT";
          pass.float = !!passDefinition.FLOAT;
          passes.push(pass);
        }
        return passes;
      };
      ISFParser.prototype.generateShaders = function generateShaders() {
        this.uniformDefs = "";
        for (let i = 0; i < this.inputs.length; ++i) {
          this.addUniform(this.inputs[i]);
        }
        for (let i = 0; i < this.passes.length; ++i) {
          if (this.passes[i].target) {
            this.addUniform({ NAME: this.passes[i].target, TYPE: "image" });
          }
        }
        for (const k in this.imports) {
          if ({}.hasOwnProperty.call(this.imports, k)) {
            this.addUniform({ NAME: k, TYPE: "image" });
          }
        }
        this.fragmentShader = this.buildFragmentShader();
        this.vertexShader = this.buildVertexShader();
      };
      ISFParser.prototype.addUniform = function addUniform(input) {
        const type = this.inputToType(input.TYPE);
        this.addUniformLine(`uniform ${type} ${input.NAME};`);
        if (type === "sampler2D") {
          this.addUniformLine(this.samplerUniforms(input));
        }
      };
      ISFParser.prototype.addUniformLine = function addUniformLine(line) {
        this.uniformDefs += `${line}
`;
      };
      ISFParser.prototype.samplerUniforms = function samplerUniforms(input) {
        const name = input.NAME;
        let lines = "";
        lines += `uniform vec4 _${name}_imgRect;
`;
        lines += `uniform vec2 _${name}_imgSize;
`;
        lines += `uniform bool _${name}_flip;
`;
        lines += `varying vec2 _${name}_normTexCoord;
`;
        lines += `varying vec2 _${name}_texCoord;
`;
        lines += "\n";
        return lines;
      };
      ISFParser.prototype.buildFragmentShader = function buildFragmentShader() {
        const main = this.replaceSpecialFunctions(this.rawFragmentMain);
        return ISFParser.fragmentShaderSkeleton.replace("[[uniforms]]", this.uniformDefs).replace("[[main]]", main);
      };
      ISFParser.prototype.replaceSpecialFunctions = function replaceSpecialFunctions(source) {
        let regex;
        regex = /IMG_THIS_PIXEL\((.+?)\)/g;
        source = source.replace(regex, (fullMatch, innerMatch) => `texture2D(${innerMatch}, isf_FragNormCoord)`);
        regex = /IMG_THIS_NORM_PIXEL\((.+?)\)/g;
        source = source.replace(regex, (fullMatch, innerMatch) => `texture2D(${innerMatch}, isf_FragNormCoord)`);
        regex = /IMG_PIXEL\((.+?)\)/g;
        source = source.replace(regex, (fullMatch, innerMatch) => {
          const results = innerMatch.split(",");
          const sampler = results[0];
          const coord = results[1];
          return `texture2D(${sampler}, (${coord}) / RENDERSIZE)`;
        });
        regex = /IMG_NORM_PIXEL\((.+?)\)/g;
        source = source.replace(regex, (fullMatch, innerMatch) => {
          const results = innerMatch.split(",");
          const sampler = results[0];
          const coord = results[1];
          return `VVSAMPLER_2DBYNORM(${sampler}, _${sampler}_imgRect, _${sampler}_imgSize, _${sampler}_flip, ${coord})`;
        });
        regex = /IMG_SIZE\((.+?)\)/g;
        source = source.replace(regex, (fullMatch, imgName) => {
          return `_${imgName}_imgSize`;
        });
        return source;
      };
      ISFParser.prototype.buildVertexShader = function buildVertexShader() {
        let functionLines = "\n";
        for (let i = 0; i < this.inputs.length; ++i) {
          const input = this.inputs[i];
          if (input.TYPE === "image") {
            functionLines += `${this.texCoordFunctions(input)}
`;
          }
        }
        return ISFParser.vertexShaderSkeleton.replace("[[functions]]", functionLines).replace("[[uniforms]]", this.uniformDefs).replace("[[main]]", this.rawVertexShader);
      };
      ISFParser.prototype.texCoordFunctions = function texCoordFunctions(input) {
        const name = input.NAME;
        return [
          "_[[name]]_texCoord =",
          "    vec2(((isf_fragCoord.x / _[[name]]_imgSize.x * _[[name]]_imgRect.z) + _[[name]]_imgRect.x), ",
          "          (isf_fragCoord.y / _[[name]]_imgSize.y * _[[name]]_imgRect.w) + _[[name]]_imgRect.y);",
          "",
          "_[[name]]_normTexCoord =",
          "  vec2((((isf_FragNormCoord.x * _[[name]]_imgSize.x) / _[[name]]_imgSize.x * _[[name]]_imgRect.z) + _[[name]]_imgRect.x),",
          "          ((isf_FragNormCoord.y * _[[name]]_imgSize.y) / _[[name]]_imgSize.y * _[[name]]_imgRect.w) + _[[name]]_imgRect.y);"
        ].join("\n").replace(/\[\[name\]\]/g, name);
      };
      ISFParser.prototype.inferFilterType = function inferFilterType() {
        function any(arr, test) {
          return arr.filter(test).length > 0;
        }
        const isFilter = any(this.inputs, (input) => input.TYPE === "image" && input.NAME === "inputImage");
        const isTransition = any(this.inputs, (input) => input.TYPE === "image" && input.NAME === "startImage") && any(this.inputs, (input) => input.TYPE === "image" && input.NAME === "endImage") && any(this.inputs, (input) => input.TYPE === "float" && input.NAME === "progress");
        if (isFilter) {
          this.type = "filter";
        } else if (isTransition) {
          this.type = "transition";
        } else {
          this.type = "generator";
        }
      };
      ISFParser.prototype.inferISFVersion = function inferISFVersion() {
        let v = 2;
        if (this.metadata.PERSISTENT_BUFFERS || this.rawFragmentShader.indexOf("vv_FragNormCoord") !== -1 || this.rawVertexShader.indexOf("vv_vertShaderInit") !== -1 || this.rawVertexShader.indexOf("vv_FragNormCoord") !== -1) {
          v = 1;
        }
        return v;
      };
      ISFParser.prototype.inputToType = function inputToType(inputType) {
        const type = typeUniformMap[inputType];
        if (!type) throw new Error(`Unknown input type [${inputType}]`);
        return type;
      };
      ISFParser.fragmentShaderSkeleton = `
precision highp float;
precision highp int;

uniform int PASSINDEX;
uniform vec2 RENDERSIZE;
varying vec2 isf_FragNormCoord;
varying vec2 isf_FragCoord;
uniform float TIME;
uniform float TIMEDELTA;
uniform int FRAMEINDEX;
uniform vec4 DATE;

[[uniforms]]

// We don't need 2DRect functions since we control all inputs.  Don't need flip either, but leaving
// for consistency sake.
vec4 VVSAMPLER_2DBYPIXEL(sampler2D sampler, vec4 samplerImgRect, vec2 samplerImgSize, bool samplerFlip, vec2 loc) {
  return (samplerFlip)
    ? texture2D   (sampler,vec2(((loc.x/samplerImgSize.x*samplerImgRect.z)+samplerImgRect.x), (samplerImgRect.w-(loc.y/samplerImgSize.y*samplerImgRect.w)+samplerImgRect.y)))
    : texture2D   (sampler,vec2(((loc.x/samplerImgSize.x*samplerImgRect.z)+samplerImgRect.x), ((loc.y/samplerImgSize.y*samplerImgRect.w)+samplerImgRect.y)));
}
vec4 VVSAMPLER_2DBYNORM(sampler2D sampler, vec4 samplerImgRect, vec2 samplerImgSize, bool samplerFlip, vec2 normLoc)  {
  vec4    returnMe = VVSAMPLER_2DBYPIXEL(   sampler,samplerImgRect,samplerImgSize,samplerFlip,vec2(normLoc.x*samplerImgSize.x, normLoc.y*samplerImgSize.y));
  return returnMe;
}

[[main]]

`;
      ISFParser.vertexShaderDefault = `
void main() {
  isf_vertShaderInit();
}
`;
      ISFParser.vertexShaderSkeleton = `
precision highp float;
precision highp int;
void isf_vertShaderInit();

attribute vec2 isf_position; // -1..1

uniform int     PASSINDEX;
uniform vec2    RENDERSIZE;
varying vec2    isf_FragNormCoord; // 0..1
vec2    isf_fragCoord; // Pixel Space

[[uniforms]]

[[main]]
void isf_vertShaderInit(void)  {
gl_Position = vec4( isf_position, 0.0, 1.0 );
  isf_FragNormCoord = vec2((gl_Position.x+1.0)/2.0, (gl_Position.y+1.0)/2.0);
  isf_fragCoord = floor(isf_FragNormCoord * RENDERSIZE);
  [[functions]]
}
`;
      ISFParser_default = ISFParser;
    }
  });

  // node_modules/interactive-shader-format/src/ISFLineMapper.js
  function getMainLine(src) {
    const lines = src.split("\n");
    for (let i = 0; i < lines.length; i++) {
      console.log("line", lines[i]);
      if (lines[i].indexOf("main()") !== -1) return i;
    }
    return -1;
  }
  function mapGLErrorToISFLine(error, glsl, isf) {
    const glslMainLine = getMainLine(glsl);
    const isfMainLine = getMainLine(isf);
    const regex = /ERROR: (\d+):(\d+): (.*)/g;
    const matches = regex.exec(error.message);
    const glslErrorLine = matches[2];
    const isfErrorLine = parseInt(glslErrorLine, 10) + isfMainLine - glslMainLine;
    return isfErrorLine;
  }
  var init_ISFLineMapper = __esm({
    "node_modules/interactive-shader-format/src/ISFLineMapper.js"() {
    }
  });

  // node_modules/interactive-shader-format/src/ISFRenderer.js
  function ISFRenderer(gl) {
    this.gl = gl;
    this.uniforms = [];
    this.contextState = new ISFGLState_default(this.gl);
    this.setupPaintToScreen();
    this.startTime = Date.now();
    this.lastRenderTime = Date.now();
    this.frameIndex = 0;
  }
  var import_mathjs_expression_parser, mathJsEval, ISFRenderer_default;
  var init_ISFRenderer = __esm({
    "node_modules/interactive-shader-format/src/ISFRenderer.js"() {
      import_mathjs_expression_parser = __toESM(require_mathjs_expression_parser());
      init_ISFGLState();
      init_ISFGLProgram();
      init_ISFBuffer();
      init_ISFParser();
      init_ISFTexture();
      init_ISFLineMapper();
      mathJsEval = import_mathjs_expression_parser.default.eval;
      ISFRenderer.prototype.loadSource = function loadSource(fragmentISF, vertexISFOpt) {
        const parser = new ISFParser_default();
        parser.parse(fragmentISF, vertexISFOpt);
        this.sourceChanged(parser.fragmentShader, parser.vertexShader, parser);
      };
      ISFRenderer.prototype.sourceChanged = function sourceChanged(fragmentShader, vertexShader, model) {
        this.fragmentShader = fragmentShader;
        this.vertexShader = vertexShader;
        this.model = model;
        if (!this.model.valid) {
          this.valid = false;
          this.error = this.model.error;
          this.errorLine = this.model.errorLine;
          return;
        }
        try {
          this.valid = true;
          this.error = null;
          this.errorLine = null;
          this.setupGL();
          this.initUniforms();
          for (let i = 0; i < model.inputs.length; i++) {
            const input = model.inputs[i];
            if (input.DEFAULT !== void 0) {
              this.setValue(input.NAME, input.DEFAULT);
            }
          }
        } catch (e) {
          this.valid = false;
          this.error = e;
          this.errorLine = mapGLErrorToISFLine(e, this.fragmentShader, this.model.rawFragmentShader);
        }
      };
      ISFRenderer.prototype.initUniforms = function initUniforms() {
        this.uniforms = this.findUniforms(this.fragmentShader);
        const inputs = this.model.inputs;
        for (let i = 0; i < inputs.length; ++i) {
          const input = inputs[i];
          const uniform = this.uniforms[input.NAME];
          if (!uniform) {
            continue;
          }
          uniform.value = this.model[input.NAME];
          if (uniform.type === "t") {
            uniform.texture = new ISFTexture_default({}, this.contextState);
          }
        }
        this.pushTextures();
      };
      ISFRenderer.prototype.setValue = function setValue(name, value) {
        this.program.use();
        const uniform = this.uniforms[name];
        if (!uniform) {
          console.error(`No uniform named ${name}`);
          return;
        }
        uniform.value = value;
        if (uniform.type === "t") {
          uniform.textureLoaded = false;
        }
        this.pushUniform(uniform);
      };
      ISFRenderer.prototype.setNormalizedValue = function setNormalizedValue(name, normalizedValue) {
        const inputs = this.model.inputs;
        let input = null;
        for (let i = 0; i < inputs.length; i++) {
          const thisInput = inputs[i];
          if (thisInput.NAME === name) {
            input = thisInput;
            break;
          }
        }
        if (input && input.MIN !== void 0 && input.MAX !== void 0) {
          this.setValue(name, input.MIN + (input.MAX - input.MIN) * normalizedValue);
        } else {
          console.log("Trying to set normalized value without MIN and MAX input", name, input);
        }
      };
      ISFRenderer.prototype.setupPaintToScreen = function setupPaintToScreen() {
        this.paintProgram = new ISFGLProgram_default(this.gl, this.basicVertexShader, this.basicFragmentShader);
        return this.paintProgram.bindVertices();
      };
      ISFRenderer.prototype.setupGL = function setupGL() {
        this.cleanup();
        this.program = new ISFGLProgram_default(this.gl, this.vertexShader, this.fragmentShader);
        this.program.bindVertices();
        this.generatePersistentBuffers();
      };
      ISFRenderer.prototype.generatePersistentBuffers = function generatePersistentBuffers() {
        this.renderBuffers = [];
        const passes = this.model.passes;
        for (let i = 0; i < passes.length; ++i) {
          const pass = passes[i];
          const buffer = new ISFBuffer_default(pass, this.contextState);
          pass.buffer = buffer;
          this.renderBuffers.push(buffer);
        }
      };
      ISFRenderer.prototype.paintToScreen = function paintToScreen(destination, target) {
        this.paintProgram.use();
        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
        this.gl.viewport(0, 0, destination.width, destination.height);
        const loc = this.paintProgram.getUniformLocation("tex");
        target.readTexture().bind(loc);
        this.gl.drawArrays(this.gl.TRIANGLES, 0, 6);
        this.program.use();
      };
      ISFRenderer.prototype.pushTextures = function pushTextures() {
        Object.keys(this.uniforms).forEach((u) => {
          const uniform = this.uniforms[u];
          if (uniform.type === "t") this.pushTexture(uniform);
        });
      };
      ISFRenderer.prototype.pushTexture = function pushTexture(uniform) {
        if (!uniform.value) {
          return;
        }
        if (uniform.value.constructor.name !== "OffscreenCanvas" && (uniform.value.tagName !== "CANVAS" && !uniform.value.complete && uniform.value.readyState !== 4)) {
          return;
        }
        const loc = this.program.getUniformLocation(uniform.name);
        uniform.texture.bind(loc);
        this.gl.texImage2D(
          this.gl.TEXTURE_2D,
          0,
          this.gl.RGBA,
          this.gl.RGBA,
          this.gl.UNSIGNED_BYTE,
          uniform.value
        );
        if (!uniform.textureLoaded) {
          const img = uniform.value;
          uniform.textureLoaded = true;
          const w = img.naturalWidth || img.width || img.videoWidth;
          const h = img.naturalHeight || img.height || img.videoHeight;
          this.setValue(`_${uniform.name}_imgSize`, [w, h]);
          this.setValue(`_${uniform.name}_imgRect`, [0, 0, 1, 1]);
          this.setValue(`_${uniform.name}_flip`, false);
        }
      };
      ISFRenderer.prototype.pushUniforms = function pushUniforms() {
        for (const uniform of this.uniforms) {
          this.pushUniform(uniform);
        }
      };
      ISFRenderer.prototype.pushUniform = function pushUniform(uniform) {
        const loc = this.program.getUniformLocation(uniform.name);
        if (loc !== -1) {
          if (uniform.type === "t") {
            this.pushTexture(uniform);
            return;
          }
          const v = uniform.value;
          switch (uniform.type) {
            case "f":
              this.gl.uniform1f(loc, v);
              break;
            case "v2":
              this.gl.uniform2f(loc, v[0], v[1]);
              break;
            case "v3":
              this.gl.uniform3f(loc, v[0], v[1], v[2]);
              break;
            case "v4":
              this.gl.uniform4f(loc, v[0], v[1], v[2], v[3]);
              break;
            case "i":
              this.gl.uniform1i(loc, v);
              break;
            case "color":
              this.gl.uniform4f(loc, v[0], v[1], v[2], v[3]);
              break;
            default:
              console.log(`Unknown type for uniform setting ${uniform.type}`, uniform);
              break;
          }
        }
      };
      ISFRenderer.prototype.findUniforms = function findUniforms(shader) {
        const lines = shader.split("\n");
        const uniforms = {};
        const len = lines.length;
        for (let i = 0; i < len; ++i) {
          const line = lines[i].trim();
          if (line.indexOf("uniform") === 0) {
            const tokens = line.split(" ");
            const name = tokens[2].substring(0, tokens[2].length - 1);
            const uniform = this.typeToUniform(tokens[1]);
            uniform.name = name;
            uniforms[name] = uniform;
          }
        }
        return uniforms;
      };
      ISFRenderer.prototype.typeToUniform = function typeToUniform(type) {
        switch (type) {
          case "float":
            return {
              type: "f",
              value: 0
            };
          case "vec2":
            return {
              type: "v2",
              value: [0, 0]
            };
          case "vec3":
            return {
              type: "v3",
              value: [0, 0, 0]
            };
          case "vec4":
            return {
              type: "v4",
              value: [0, 0, 0, 0]
            };
          case "bool":
            return {
              type: "i",
              value: 0
            };
          case "int":
            return {
              type: "i",
              value: 0
            };
          case "color":
            return {
              type: "v4",
              value: [0, 0, 0, 0]
            };
          case "point2D":
            return {
              type: "v2",
              value: [0, 0],
              isPoint: true
            };
          case "sampler2D":
            return {
              type: "t",
              value: {
                complete: false,
                readyState: 0
              },
              texture: null,
              textureUnit: null
            };
          default:
            throw new Error(`Unknown uniform type in ISFRenderer.typeToUniform: ${type}`);
        }
      };
      ISFRenderer.prototype.setDateUniforms = function setDateUniforms() {
        const now = Date.now();
        this.setValue("TIME", (now - this.startTime) / 1e3);
        this.setValue("TIMEDELTA", (now - this.lastRenderTime) / 1e3);
        this.setValue("FRAMEINDEX", this.frameIndex++);
        const date = /* @__PURE__ */ new Date();
        this.setValue("DATE", [date.getFullYear(), date.getMonth() + 1, date.getDate(), date.getHours() * 3600 + date.getMinutes() * 60 + date.getSeconds()]);
        this.lastRenderTime = now;
      };
      ISFRenderer.prototype.draw = function draw(destination) {
        this.contextState.reset();
        this.program.use();
        this.setDateUniforms();
        const buffers = this.renderBuffers;
        for (let i = 0; i < buffers.length; ++i) {
          const buffer = buffers[i];
          const readTexture2 = buffer.readTexture();
          const loc = this.program.getUniformLocation(buffer.name);
          readTexture2.bind(loc);
          if (buffer.name) {
            this.setValue(`_${buffer.name}_imgSize`, [buffer.width, buffer.height]);
            this.setValue(`_${buffer.name}_imgRect`, [0, 0, 1, 1]);
            this.setValue(`_${buffer.name}_flip`, false);
          }
        }
        let lastTarget = null;
        const passes = this.model.passes;
        for (let i = 0; i < passes.length; ++i) {
          const pass = passes[i];
          this.setValue("PASSINDEX", i);
          const buffer = pass.buffer;
          if (pass.target) {
            const w = this.evaluateSize(destination, pass.width);
            const h = this.evaluateSize(destination, pass.height);
            buffer.setSize(w, h);
            const writeTexture2 = buffer.writeTexture();
            this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, buffer.fbo);
            this.gl.framebufferTexture2D(
              this.gl.FRAMEBUFFER,
              this.gl.COLOR_ATTACHMENT0,
              this.gl.TEXTURE_2D,
              writeTexture2.texture,
              0
            );
            this.setValue("RENDERSIZE", [buffer.width, buffer.height]);
            lastTarget = buffer;
            this.gl.viewport(0, 0, w, h);
          } else {
            const renderWidth = destination.width;
            const renderHeight = destination.height;
            this.gl.bindTexture(this.gl.TEXTURE_2D, null);
            this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
            this.setValue("RENDERSIZE", [renderWidth, renderHeight]);
            lastTarget = null;
            this.gl.viewport(0, 0, renderWidth, renderHeight);
          }
          this.gl.drawArrays(this.gl.TRIANGLES, 0, 6);
          this.gl.bindTexture(this.gl.TEXTURE_2D, null);
          this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
        }
        for (let i = 0; i < buffers.length; ++i) {
          buffers[i].flip();
        }
        if (lastTarget) {
          this.paintToScreen(destination, lastTarget);
        }
      };
      ISFRenderer.prototype.evaluateSize = function evaluateSize(destination, formula) {
        formula += "";
        let s = formula.replace("$WIDTH", destination.offsetWidth || destination.width).replace("$HEIGHT", destination.offsetHeight || destination.height);
        for (const name in this.uniforms) {
          if ({}.hasOwnProperty.call(this.uniforms, name)) {
            const uniform = this.uniforms[name];
            s = s.replace(`$${name}`, uniform.value);
          }
        }
        return mathJsEval(s);
      };
      ISFRenderer.prototype.cleanup = function cleanup2() {
        this.contextState.reset();
        if (this.renderBuffers) {
          for (let i = 0; i < this.renderBuffers.length; ++i) {
            this.renderBuffers[i].destroy();
          }
        }
      };
      ISFRenderer.prototype.basicVertexShader = "precision mediump float;\nprecision mediump int;\nattribute vec2 isf_position; // -1..1\nvarying vec2 texCoord;\n\nvoid main(void) {\n  // Since webgl doesn't support ftransform, we do this by hand.\n  gl_Position = vec4(isf_position, 0, 1);\n  texCoord = isf_position;\n}\n";
      ISFRenderer.prototype.basicFragmentShader = "precision mediump float;\nuniform sampler2D tex;\nvarying vec2 texCoord;\nvoid main()\n{\n  gl_FragColor = texture2D(tex, texCoord * 0.5 + 0.5);\n  //gl_FragColor = vec4(texCoord.x);\n}";
      ISFRenderer_default = ISFRenderer;
    }
  });

  // node_modules/interactive-shader-format/src/ISFUpgrader.js
  var init_ISFUpgrader = __esm({
    "node_modules/interactive-shader-format/src/ISFUpgrader.js"() {
      init_MetadataExtractor();
    }
  });

  // node_modules/interactive-shader-format/src/main.js
  var init_main = __esm({
    "node_modules/interactive-shader-format/src/main.js"() {
      init_ISFRenderer();
      init_ISFParser();
      init_ISFUpgrader();
      init_MetadataExtractor();
    }
  });

  // isf-entry.js
  var require_isf_entry = __commonJS({
    "isf-entry.js"() {
      init_main();
      window.ISFRenderer = ISFRenderer_default;
      window.ISFParser = ISFParser_default;
      window.ISFMetadataExtractor = MetadataExtractor;
    }
  });
  require_isf_entry();
})();
