//  ISFMSLSafeBridge.h
//  Crash-safe wrapper around ISFMSLKit's transpiler. Some ISF shaders make ISFGLSLGenerator
//  throw an uncaught C++ exception (e.g. nlohmann::json type_error on a malformed header),
//  which would terminate the whole app. Swift cannot catch C++ exceptions; this Obj-C++ shim
//  wraps the risky create/load/error-read in a C++ try/catch and reports failure instead.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

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

/// Renders `scene` to a texture of `size` on `commandBuffer`, catching any C++ exception thrown by
/// the transpiler/engine at render time (a compiled-but-pathological shader can still throw mid-render
/// during a live set). Returns the rendered MTLTexture, or nil if an exception was thrown (then
/// *errorOut is set). The returned texture's pixel format is whatever the engine produced.
id<MTLTexture> _Nullable ISFMSLSafeRender(ISFMSLScene *scene,
                                          NSSize size,
                                          id<MTLCommandBuffer> commandBuffer,
                                          NSString * _Nullable * _Nullable errorOut);

/// Sets `view.colorPixelFormat`, catching the Obj-C `NSException` that `CAMetalLayer` throws for a
/// pixel format that is not a valid drawable format (e.g. a 32-bit-float ISF output). Swift cannot
/// catch NSExceptions, so an unguarded assignment aborts the app. Returns YES if set, NO if rejected.
BOOL ISFMSLSafeSetColorPixelFormat(MTKView *view, MTLPixelFormat format);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
