//  ISFMSLSafeBridge.mm
#import "ISFMSLSafeBridge.h"
#import <ISFMSLKit/ISFMSLKit.h>
#include <exception>

ISFMSLScene * _Nullable ISFMSLSafeCreateAndLoad(id<MTLDevice> device,
                                                NSURL *url,
                                                BOOL *compileError,
                                                NSString * _Nullable * _Nullable message)
{
    if (compileError) { *compileError = NO; }
    if (message) { *message = nil; }

    try {
        ISFMSLScene *scene = [[ISFMSLScene alloc] initWithDevice:device];
        if (scene == nil) {
            if (message) { *message = @"Failed to create Metal scene."; }
            if (compileError) { *compileError = YES; }
            return nil;
        }
        [scene loadURL:url];

        BOOL hadError = scene.compilerError;
        if (compileError) { *compileError = hadError; }
        if (hadError && message) {
            ISFMSLTranspilerError *te = [ISFMSLTranspilerError createWithURL:url device:device];
            NSString *msg = te.fragGLSLErrString;
            if (msg.length == 0) { msg = te.fragSPIRVErrString; }
            if (msg.length == 0) { msg = te.fragMSLErrString; }
            if (msg.length == 0) { msg = te.vertGLSLErrString; }
            if (msg.length == 0) { msg = [te generateStringForLogFile]; }
            if (msg.length == 0) { msg = @"Shader failed to compile."; }
            *message = msg;
        }
        return scene;
    }
    catch (const std::exception &e) {
        if (compileError) { *compileError = YES; }
        if (message) { *message = [NSString stringWithFormat:@"Transpiler exception: %s", e.what()]; }
        return nil;
    }
    catch (...) {
        if (compileError) { *compileError = YES; }
        if (message) { *message = @"Unknown transpiler exception."; }
        return nil;
    }
}

id<MTLTexture> _Nullable ISFMSLSafeRender(ISFMSLScene *scene,
                                          NSSize size,
                                          id<MTLCommandBuffer> commandBuffer,
                                          NSString * _Nullable * _Nullable errorOut)
{
    if (errorOut) { *errorOut = nil; }
    try {
        id<VVMTLTextureImage> img = [scene createAndRenderToTextureSized:size inCommandBuffer:commandBuffer];
        if (img == nil) { return nil; }
        // VVMTLRecycleable returns the backing texture to VVMTLPool when the wrapper deallocates
        // (VVMTLRecycleable.h: "returned to this pool upon deletion") — dropping `img` at scope
        // end would let the pool recycle the texture while this command buffer is still rendering
        // into it and the caller is still displaying it. Keep the wrapper alive until the GPU is
        // done with the frame.
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull cb) { (void)img; }];
        return img.texture;
    }
    catch (const std::exception &e) {
        if (errorOut) { *errorOut = [NSString stringWithFormat:@"Render exception: %s", e.what()]; }
        return nil;
    }
    catch (...) {
        if (errorOut) { *errorOut = @"Unknown render exception."; }
        return nil;
    }
}

id<MTLTexture> _Nullable ISFMSLSafeRenderAtTime(ISFMSLScene *scene,
                                                NSSize size,
                                                double time,
                                                id<MTLCommandBuffer> commandBuffer,
                                                NSString * _Nullable * _Nullable errorOut)
{
    if (errorOut) { *errorOut = nil; }
    try {
        id<VVMTLTextureImage> img = [scene createAndRenderToTextureSized:size
                                                                  atTime:time
                                                         inCommandBuffer:commandBuffer];
        if (img == nil) { return nil; }
        // Same pool-recycle guard as ISFMSLSafeRender: keep the VVMTLTextureImage wrapper alive
        // until the GPU is done, or VVMTLPool may recycle the backing texture mid-render.
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull cb) { (void)img; }];
        return img.texture;
    }
    catch (const std::exception &e) {
        if (errorOut) { *errorOut = [NSString stringWithFormat:@"Render exception: %s", e.what()]; }
        return nil;
    }
    catch (...) {
        if (errorOut) { *errorOut = @"Unknown render exception."; }
        return nil;
    }
}
