//  ISFMSLSafeBridge.h
//  Crash-safe wrapper around ISFMSLKit's transpiler. Some ISF shaders make ISFGLSLGenerator
//  throw an uncaught C++ exception (e.g. nlohmann::json type_error on a malformed header),
//  which would terminate the whole app. Swift cannot catch C++ exceptions; this Obj-C++ shim
//  wraps the risky create/load/error-read in a C++ try/catch and reports failure instead.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@class ISFMSLScene;

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// Creates an ISFMSLScene for `device` and loads `url`, catching any C++ exception thrown by the
/// transpiler. Returns the loaded scene on success, or nil if a C++ exception was thrown.
/// - `compileError` (out): YES if the shader has an ISF compile error (scene is still returned non-nil
///   so the caller can decide; but typically a compile error means don't render it).
/// - `message` (out): the compiler-error text, or the C++ exception text on a thrown exception, else nil.
ISFMSLScene * _Nullable ISFMSLSafeCreateAndLoad(id<MTLDevice> device,
                                                NSURL *url,
                                                BOOL *compileError,
                                                NSString * _Nullable * _Nullable message);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
