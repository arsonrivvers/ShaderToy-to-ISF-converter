//  ISFRuntime-Bridging-Header.h
//  Shared by every app target that renders ISF. Exposes ISFMSLKit (Obj-C++) and the crash-safe
//  wrapper to Swift. Target-specific bridging headers #import this one and add their own headers.
#import <ISFMSLKit/ISFMSLKit.h>
#import "ISFMSLSafeBridge.h"
