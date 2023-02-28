/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVThemeableBrowser.h"
#import <Cordova/CDVPluginResult.h>

#if __has_include("CDVWKProcessPoolFactory.h")
#import "CDVWKProcessPoolFactory.h"
#endif

#define    kThemeableBrowserTargetSelf @"_self"
#define    kThemeableBrowserTargetSystem @"_system"
#define    kThemeableBrowserTargetBlank @"_blank"

#define    kThemeableBrowserToolbarBarPositionBottom @"bottom"
#define    kThemeableBrowserToolbarBarPositionTop @"top"

#define    IAB_BRIDGE_NAME @"cordova_iab"

#define    kThemeableBrowserAlignLeft @"left"
#define    kThemeableBrowserAlignRight @"right"

#define    kThemeableBrowserPropEvent @"event"
#define    kThemeableBrowserPropLabel @"label"
#define    kThemeableBrowserPropColor @"color"
#define    kThemeableBrowserPropHeight @"height"
#define    kThemeableBrowserPropImage @"image"
#define    kThemeableBrowserPropWwwImage @"wwwImage"
#define    kThemeableBrowserPropImagePressed @"imagePressed"
#define    kThemeableBrowserPropWwwImagePressed @"wwwImagePressed"
#define    kThemeableBrowserPropWwwImageDensity @"wwwImageDensity"
#define    kThemeableBrowserPropStaticText @"staticText"
#define    kThemeableBrowserPropShowProgress @"showProgress"
#define    kThemeableBrowserPropProgressBgColor @"progressBgColor"
#define    kThemeableBrowserPropProgressColor @"progressColor"
#define    kThemeableBrowserPropShowPageTitle @"showPageTitle"
#define    kThemeableBrowserPropAlign @"align"
#define    kThemeableBrowserPropTitle @"title"
#define    kThemeableBrowserPropTitleFontSize @"fontSize"
#define    kThemeableBrowserPropCancel @"cancel"
#define    kThemeableBrowserPropItems @"items"
#define    kThemeableBrowserPropAccessibilityDescription @"accessibilityDescription"
#define    kThemeableBrowserPropStatusBarStyle @"style"
#define    kThemeableBrowserPropToolbarPaddingX @"paddingX"

#define    kThemeableBrowserEmitError @"ThemeableBrowserError"
#define    kThemeableBrowserEmitWarning @"ThemeableBrowserWarning"
#define    kThemeableBrowserEmitCodeCritical @"critical"
#define    kThemeableBrowserEmitCodeLoadFail @"loadfail"
#define    kThemeableBrowserEmitCodeUnexpected @"unexpected"
#define    kThemeableBrowserEmitCodeUndefined @"undefined"

#define    TOOLBAR_HEIGHT 44.0
#define    LOCATIONBAR_HEIGHT 21.0
#define    FOOTER_HEIGHT ((TOOLBAR_HEIGHT) + (LOCATIONBAR_HEIGHT))

#pragma mark CDVThemeableBrowser

@interface CDVThemeableBrowser () {
    BOOL _isShown;
    int _framesOpened;  // number of frames opened since the last time browser exited
    NSURL *initUrl;  // initial URL ThemeableBrowser opened with
    NSURL *originalUrl;
}
@end

@implementation CDVThemeableBrowser

- (void)pluginInitialize
{
    _isShown = NO;
    _framesOpened = 0;
    _callbackIdPattern = nil;
}


- (void)onReset
{
    [self close:nil];
}

- (void)close:(CDVInvokedUrlCommand*)command
{
    if (self.themeableBrowserViewController == nil) {
        [self emitWarning:kThemeableBrowserEmitCodeUnexpected
              withMessage:@"Close called but already closed."];
        return;
    }
    // Things are cleaned up in browserExit.
    [self.themeableBrowserViewController close];
}

- (BOOL) isSystemUrl:(NSURL*)url
{
    NSDictionary *systemUrls = @{
                                 @"itunes.apple.com": @YES,
                                 @"search.itunes.apple.com": @YES,
                                 @"appsto.re": @YES
                                 };
    
    if (systemUrls[[url host]]) {
        return YES;
    }
    
    return NO;
}

- (void)open:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult;
    
    NSString* url = [command argumentAtIndex:0];
    NSString* target = [command argumentAtIndex:1 withDefault:kThemeableBrowserTargetSelf];
    NSString* options = [command argumentAtIndex:2 withDefault:@"" andClass:[NSString class]];
    
    self.callbackId = command.callbackId;
    
    if (url != nil) {
#ifdef __CORDOVA_4_0_0
        NSURL* baseUrl = [self.webViewEngine URL];
#else
        NSURL* baseUrl = [self.webView.request URL];
#endif
        NSURL* absoluteUrl = [[NSURL URLWithString:url relativeToURL:baseUrl] absoluteURL];
        
        initUrl = absoluteUrl;
        
        if ([self isSystemUrl:absoluteUrl]) {
            target = kThemeableBrowserTargetSystem;
        }
        
        if ([target isEqualToString:kThemeableBrowserTargetSelf]) {
            [self openInCordovaWebView:absoluteUrl withOptions:options];
        } else if ([target isEqualToString:kThemeableBrowserTargetSystem]) {
            [self openInSystem:absoluteUrl];
        } else { // _blank or anything else
            [self openInThemeableBrowser:absoluteUrl withOptions:options];
        }
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"incorrect number of arguments"];
    }
    
    [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)reload:(CDVInvokedUrlCommand*)command
{
    if (self.themeableBrowserViewController) {
        [self.themeableBrowserViewController reload];
    }
}

- (CDVThemeableBrowserOptions*)parseOptions:(NSString*)options
{
    CDVThemeableBrowserOptions* obj = [[CDVThemeableBrowserOptions alloc] init];
    
    if (options && [options length] > 0) {
        // Min support, iOS 5. We will use the JSON parser that comes with iOS
        // 5.
        NSError *error = nil;
        NSData *data = [options dataUsingEncoding:NSUTF8StringEncoding];
        id jsonObj = [NSJSONSerialization
                      JSONObjectWithData:data
                      options:0
                      error:&error];
        
        if(error) {
            [self emitError:kThemeableBrowserEmitCodeCritical
                withMessage:[NSString stringWithFormat:@"Invalid JSON %@", error]];
        } else if([jsonObj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = jsonObj;
            for (NSString *key in dict) {
                if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                    [obj setValue:dict[key] forKey:key];
                }
            }
        }
    } else {
        [self emitWarning:kThemeableBrowserEmitCodeUndefined
              withMessage:@"No config was given, defaults will be used, which is quite boring."];
    }
    
    return obj;
}

- (void)openInThemeableBrowser:(NSURL*)url withOptions:(NSString*)options
{
    CDVThemeableBrowserOptions* browserOptions = [self parseOptions:options];
    
    // Among all the options, there are a few that ThemedBrowser would like to
    // disable, since ThemedBrowser's purpose is to provide an integrated look
    // and feel that is consistent across platforms. We'd do this hack to
    // minimize changes from the original ThemeableBrowser so when merge from the
    // ThemeableBrowser is needed, it wouldn't be super pain in the ass.
    browserOptions.toolbarposition = kThemeableBrowserToolbarBarPositionTop;
    
    WKWebsiteDataStore* dataStore = [WKWebsiteDataStore defaultDataStore];
    
        if (browserOptions.clearcache) {
            bool isAtLeastiOS11 = false;
    #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
            if (@available(iOS 11.0, *)) {
                isAtLeastiOS11 = true;
            }
    #endif
                
            if(isAtLeastiOS11){
    #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
                // Deletes all cookies
                WKHTTPCookieStore* cookieStore = dataStore.httpCookieStore;
                [cookieStore getAllCookies:^(NSArray* cookies) {
                    NSHTTPCookie* cookie;
                    for(cookie in cookies){
                        [cookieStore deleteCookie:cookie completionHandler:nil];
                    }
                }];
    #endif
            }else{
                // https://stackoverflow.com/a/31803708/777265
                // Only deletes domain cookies (not session cookies)
                [dataStore fetchDataRecordsOfTypes:[WKWebsiteDataStore allWebsiteDataTypes]
                 completionHandler:^(NSArray<WKWebsiteDataRecord *> * __nonnull records) {
                     for (WKWebsiteDataRecord *record  in records){
                         NSSet<NSString*>* dataTypes = record.dataTypes;
                         if([dataTypes containsObject:WKWebsiteDataTypeCookies]){
                             [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:record.dataTypes
                                   forDataRecords:@[record]
                                   completionHandler:^{}];
                         }
                     }
                 }];
            }
        }
        
        if (browserOptions.clearsessioncache) {
            bool isAtLeastiOS11 = false;
    #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
            if (@available(iOS 11.0, *)) {
                isAtLeastiOS11 = true;
            }
    #endif
            if (isAtLeastiOS11) {
    #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
                // Deletes session cookies
                WKHTTPCookieStore* cookieStore = dataStore.httpCookieStore;
                [cookieStore getAllCookies:^(NSArray* cookies) {
                    NSHTTPCookie* cookie;
                    for(cookie in cookies){
                        if(cookie.sessionOnly){
                            [cookieStore deleteCookie:cookie completionHandler:nil];
                        }
                    }
                }];
    #endif
            }else{
                NSLog(@"clearsessioncache not available below iOS 11.0");
            }
        }
    
    UIStatusBarStyle statusBarStyle = UIStatusBarStyleDefault;
    if(browserOptions.statusbar[kThemeableBrowserPropStatusBarStyle]){
        NSString* style = browserOptions.statusbar[kThemeableBrowserPropStatusBarStyle];
        if([style isEqualToString:@"lightcontent"]){
            statusBarStyle = UIStatusBarStyleLightContent;
        }else if([style isEqualToString:@"darkcontent"]){
            if (@available(iOS 13.0, *)) {
                statusBarStyle = UIStatusBarStyleDarkContent;
            }
        }
    }
    
    if (self.themeableBrowserViewController == nil) {
        self.themeableBrowserViewController = [[CDVThemeableBrowserViewController alloc]
                                               init: browserOptions
                                               navigationDelete:self
                                               statusBarStyle:statusBarStyle];
        self.themeableBrowserViewController.navigationDelegate = self;
        
        if ([self.viewController conformsToProtocol:@protocol(CDVScreenOrientationDelegate)]) {
            self.themeableBrowserViewController.orientationDelegate = (UIViewController <CDVScreenOrientationDelegate>*)self.viewController;
        }
    }
    
    [self.themeableBrowserViewController showLocationBar:browserOptions.location];
    [self.themeableBrowserViewController showToolBar:YES:browserOptions.toolbarposition];
    if (browserOptions.closebuttoncaption != nil) {
        // [self.themeableBrowserViewController setCloseButtonTitle:browserOptions.closebuttoncaption];
    }
    // Set Presentation Style
    UIModalPresentationStyle presentationStyle = UIModalPresentationFullScreen; // default
    if (browserOptions.presentationstyle != nil) {
        if ([[browserOptions.presentationstyle lowercaseString] isEqualToString:@"pagesheet"]) {
            presentationStyle = UIModalPresentationPageSheet;
        } else if ([[browserOptions.presentationstyle lowercaseString] isEqualToString:@"formsheet"]) {
            presentationStyle = UIModalPresentationFormSheet;
        }
    }
    self.themeableBrowserViewController.modalPresentationStyle = presentationStyle;
    
    // Set Transition Style
    UIModalTransitionStyle transitionStyle = UIModalTransitionStyleCoverVertical; // default
    if (browserOptions.transitionstyle != nil) {
        if ([[browserOptions.transitionstyle lowercaseString] isEqualToString:@"fliphorizontal"]) {
            transitionStyle = UIModalTransitionStyleFlipHorizontal;
        } else if ([[browserOptions.transitionstyle lowercaseString] isEqualToString:@"crossdissolve"]) {
            transitionStyle = UIModalTransitionStyleCrossDissolve;
        }
    }
    self.themeableBrowserViewController.modalTransitionStyle = transitionStyle;
    
    // prevent webView from bouncing
    if (browserOptions.disallowoverscroll) {
        if ([self.themeableBrowserViewController.webView respondsToSelector:@selector(scrollView)]) {
            ((UIScrollView*)[self.themeableBrowserViewController.webView scrollView]).bounces = NO;
        } else {
            for (id subview in self.themeableBrowserViewController.webView.subviews) {
                if ([[subview class] isSubclassOfClass:[UIScrollView class]]) {
                    ((UIScrollView*)subview).bounces = NO;
                }
            }
        }
    }
    
    [self.themeableBrowserViewController navigateTo:url];
    if (!browserOptions.hidden) {
        [self show:nil withAnimation:!browserOptions.disableAnimation];
    }
}

- (void)show:(CDVInvokedUrlCommand*)command
{
    [self show:command withAnimation:YES];
}

- (void)show:(CDVInvokedUrlCommand*)command withAnimation:(BOOL)animated
{
    if (self.themeableBrowserViewController == nil) {
        [self emitWarning:kThemeableBrowserEmitCodeUnexpected
              withMessage:@"Show called but already closed."];
        return;
    }
    if (_isShown) {
        [self emitWarning:kThemeableBrowserEmitCodeUnexpected
              withMessage:@"Show called but already shown"];
        return;
    }
    
    _isShown = YES;
    
    CDVThemeableBrowserNavigationController* nav = [[CDVThemeableBrowserNavigationController alloc]
                                                    initWithRootViewController:self.themeableBrowserViewController];
    nav.orientationDelegate = self.themeableBrowserViewController;
    nav.navigationBarHidden = YES;
    if (@available(iOS 13.0, *)) {
        nav.modalPresentationStyle = UIModalPresentationOverFullScreen;
    }
    
    __weak CDVThemeableBrowser* weakSelf = self;
    
    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.themeableBrowserViewController != nil) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf->tmpWindow) {
                CGRect frame = [[UIScreen mainScreen] bounds];
                strongSelf->tmpWindow = [[UIWindow alloc] initWithFrame:frame];
            }
            
            UIViewController *tmpController = [[UIViewController alloc] init];
            [strongSelf->tmpWindow setRootViewController:tmpController];
            
            
            [strongSelf->tmpWindow makeKeyAndVisible];
            [tmpController presentViewController:nav animated:YES completion:nil];
        }
    });
}

- (void)openInCordovaWebView:(NSURL*)url withOptions:(NSString*)options
{
    NSURLRequest* request = [NSURLRequest requestWithURL:url];
    
#ifdef __CORDOVA_4_0_0
    // the webview engine itself will filter for this according to <allow-navigation> policy
    // in config.xml for cordova-ios-4.0
    [self.webViewEngine loadRequest:request];
#else
    if ([self.commandDelegate URLIsWhitelisted:url]) {
        [self.webView loadRequest:request];
    } else { // this assumes the openInThemeableBrowser can be excepted from the white-list
        [self openInThemeableBrowser:url withOptions:options];
    }
#endif
}

- (void)openInSystem:(NSURL*)url
{
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url];
    } else { // handle any custom schemes to plugins
        [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:CDVPluginHandleOpenURLNotification object:url]];
    }
}

// This is a helper method for the inject{Script|Style}{Code|File} API calls, which
// provides a consistent method for injecting JavaScript code into the document.
//
// If a wrapper string is supplied, then the source string will be JSON-encoded (adding
// quotes) and wrapped using string formatting. (The wrapper string should have a single
// '%@' marker).
//
// If no wrapper is supplied, then the source string is executed directly.

- (void)injectDeferredObject:(NSString*)source withWrapper:(NSString*)jsWrapper
{
    // Ensure a message handler bridge is created to communicate with the CDVWKthemeableBrowserViewController
    [self evaluateJavaScript: [NSString stringWithFormat:@"(function(w){if(!w._cdvMessageHandler) {w._cdvMessageHandler = function(id,d){w.webkit.messageHandlers.%@.postMessage({d:d, id:id});}}})(window)", IAB_BRIDGE_NAME]];
    
    if (jsWrapper != nil) {
        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:@[source] options:0 error:nil];
        NSString* sourceArrayString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        if (sourceArrayString) {
            NSString* sourceString = [sourceArrayString substringWithRange:NSMakeRange(1, [sourceArrayString length] - 2)];
            NSString* jsToInject = [NSString stringWithFormat:jsWrapper, sourceString];
            [self evaluateJavaScript:jsToInject];
        }
    } else {
        [self evaluateJavaScript:source];
    }
}


//Synchronus helper for javascript evaluation
- (void)evaluateJavaScript:(NSString *)script {
    __block NSString* _script = script;
    [self.themeableBrowserViewController.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error == nil) {
            if (result != nil) {
                NSLog(@"%@", result);
            }
        } else {
            NSLog(@"evaluateJavaScript error : %@ : %@", error.localizedDescription, _script);
        }
    }];
}

- (void)injectScriptCode:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper = nil;
    
    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"_cdvMessageHandler('%@',JSON.stringify([eval(%%@)]));", command.callbackId];
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectScriptFile:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;
    
    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('script'); c.src = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('script'); c.src = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectStyleCode:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;
    
    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('style'); c.innerHTML = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('style'); c.innerHTML = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectStyleFile:(CDVInvokedUrlCommand*)command
{
    NSString* jsWrapper;
    
    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %%@; c.onload = function() { _cdvMessageHandler('%@'); }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('link'); c.rel='stylesheet', c.type='text/css'; c.href = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (BOOL)isValidCallbackId:(NSString *)callbackId
{
    NSError *err = nil;
    // Initialize on first use
    if (self.callbackIdPattern == nil) {
        self.callbackIdPattern = [NSRegularExpression regularExpressionWithPattern:@"^ThemeableBrowser[0-9]{1,10}$" options:0 error:&err];
        if (err != nil) {
            // Couldn't initialize Regex; No is safer than Yes.
            return NO;
        }
    }
    if ([self.callbackIdPattern firstMatchInString:callbackId options:0 range:NSMakeRange(0, [callbackId length])]) {
        return YES;
    }
    return NO;
}

/**
 * The message handler bridge provided for the InAppBrowser is capable of executing any oustanding callback belonging
 * to the InAppBrowser plugin. Care has been taken that other callbacks cannot be triggered, and that no
 * other code execution is possible.
 */
- (void)webView:(WKWebView *)theWebView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    NSURL* url = navigationAction.request.URL;
    NSURL* mainDocumentURL = navigationAction.request.mainDocumentURL;
    BOOL isTopLevelNavigation = [url isEqual:mainDocumentURL];
    BOOL shouldStart = YES;
    
    //if is an app store link, let the system handle it, otherwise it fails to load it
    if ([[ url scheme] isEqualToString:@"itms-appss"] || [[ url scheme] isEqualToString:@"itms-apps"]) {
        [theWebView stopLoading];
        [self openInSystem:url];
        shouldStart = NO;
    }
    else if ((self.callbackId != nil) && isTopLevelNavigation) {
        // Send a loadstart event for each top-level navigation (includes redirects).
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"loadstart", @"url":[url absoluteString]}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
    
    if(shouldStart){
        // Fix GH-417 & GH-424: Handle non-default target attribute
        // Based on https://stackoverflow.com/a/25713070/777265
        if (!navigationAction.targetFrame){
            [theWebView loadRequest:navigationAction.request];
            decisionHandler(WKNavigationActionPolicyCancel);
        }else{
            decisionHandler(WKNavigationActionPolicyAllow);
        }
    }else{
        decisionHandler(WKNavigationActionPolicyCancel);
    }
}

#pragma mark WKScriptMessageHandler delegate
- (void)userContentController:(nonnull WKUserContentController *)userContentController didReceiveScriptMessage:(nonnull WKScriptMessage *)message {
    
    CDVPluginResult* pluginResult = nil;
    
    if([message.body isKindOfClass:[NSDictionary class]]){
        NSDictionary* messageContent = (NSDictionary*) message.body;
        NSString* scriptCallbackId = messageContent[@"id"];
        
        if([messageContent objectForKey:@"d"]){
            NSString* scriptResult = messageContent[@"d"];
            NSError* __autoreleasing error = nil;
            NSData* decodedResult = [NSJSONSerialization JSONObjectWithData:[scriptResult dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
            if ((error == nil) && [decodedResult isKindOfClass:[NSArray class]]) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:(NSArray*)decodedResult];
            } else {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_JSON_EXCEPTION];
            }
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:@[]];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:scriptCallbackId];
    }else if(self.callbackId != nil){
        // Send a message event
        NSString* messageContent = (NSString*) message.body;
        NSError* __autoreleasing error = nil;
        NSData* decodedResult = [NSJSONSerialization JSONObjectWithData:[messageContent dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
        if (error == nil) {
            NSMutableDictionary* dResult = [NSMutableDictionary new];
            [dResult setValue:@"message" forKey:@"type"];
            [dResult setObject:decodedResult forKey:@"data"];
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dResult];
            [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        }
    }
}

- (void)didStartProvisionalNavigation:(WKWebView*)theWebView
{
    NSLog(@"didStartProvisionalNavigation");
//    self.inAppBrowserViewController.currentURL = theWebView.URL;
}

- (void)didFinishNavigation:(WKWebView*)theWebView
{
    if (self.callbackId != nil) {
        NSString* url = [theWebView.URL absoluteString];
        if(url == nil){
            if(self.themeableBrowserViewController.currentURL != nil){
                url = [self.themeableBrowserViewController.currentURL absoluteString];
            }else{
                url = @"";
            }
        }
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"loadstop", @"url":url}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

- (void)webView:(WKWebView*)theWebView didFailNavigation:(NSError*)error
{
    if (self.callbackId != nil) {
        NSString* url = [theWebView.URL absoluteString];
        if(url == nil){
            if(self.themeableBrowserViewController.currentURL != nil){
                url = [self.themeableBrowserViewController.currentURL absoluteString];
            }else{
                url = @"";
            }
        }
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsDictionary:@{@"type":@"loaderror", @"url":url, @"code": [NSNumber numberWithInteger:error.code], @"message": error.localizedDescription}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

- (UIWindow*)getTmpWindow
{
    // Set tmpWindow to hidden to make main webview responsive to touch again
    // Based on https://stackoverflow.com/questions/4544489/how-to-remove-a-uiwindow
    return self->tmpWindow;
}

- (void) nilTmpWindow{
    self->tmpWindow = nil;
}

- (void)browserExit
{
    if (self.callbackId != nil) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"exit"}];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
    }
    
    [self.themeableBrowserViewController.configuration.userContentController removeScriptMessageHandlerForName:IAB_BRIDGE_NAME];
    self.themeableBrowserViewController.configuration = nil;
    
    [self.themeableBrowserViewController.webView stopLoading];
    [self.themeableBrowserViewController.webView removeFromSuperview];
    [self.themeableBrowserViewController.webView setUIDelegate:nil];
    [self.themeableBrowserViewController.webView setNavigationDelegate:nil];
    self.themeableBrowserViewController.webView = nil;
    
    // Set navigationDelegate to nil to ensure no callbacks are received from it.
    self.themeableBrowserViewController.navigationDelegate = nil;
    // Don't recycle the ViewController since it may be consuming a lot of memory.
    // Also - this is required for the PDF/User-Agent bug work-around.
    self.themeableBrowserViewController = nil;
    
    
    self.callbackId = nil;
    self.callbackIdPattern = nil;
    
    _framesOpened = 0;
    _isShown = NO;
}

- (void)emitEvent:(NSDictionary*)event
{
    if (self.callbackId != nil) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:event];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

- (void)emitError:(NSString*)code withMessage:(NSString*)message
{
    NSDictionary *event = @{
                            @"type": kThemeableBrowserEmitError,
                            @"code": code,
                            @"message": message
                            };
    
    [self emitEvent:event];
}

- (void)emitWarning:(NSString*)code withMessage:(NSString*)message
{
    NSDictionary *event = @{
                            @"type": kThemeableBrowserEmitWarning,
                            @"code": code,
                            @"message": message
                            };
    
    [self emitEvent:event];
}

@end

#pragma mark CDVThemeableBrowserViewController

@implementation CDVThemeableBrowserViewController

@synthesize currentURL;

- (id)init:(CDVThemeableBrowserOptions*) browserOptions navigationDelete:(CDVThemeableBrowser*) navigationDelegate statusBarStyle:(UIStatusBarStyle) statusBarStyle
{
    self = [super init];
    if (self != nil) {
        _lastReducedStatusBarHeight = 0.0;
        _browserOptions = browserOptions;
        self.webViewUIDelegate = [[CDVThemeableBrowserUIDelegate alloc] initWithTitle:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"]];
        [self.webViewUIDelegate setViewController:self];
        _navigationDelegate = navigationDelegate;
        _statusBarStyle = statusBarStyle;
        _initialStatusBarHeight = [self getStatusBarHeight];
        [self createViews];
    }
    
    return self;
}

- (void)createViews
{
    // We create the views in code for primarily for ease of upgrades and not requiring an external .xib to be included
    
    CGRect webViewBounds = self.view.bounds;
    BOOL toolbarIsAtBottom = ![_browserOptions.toolbarposition isEqualToString:kThemeableBrowserToolbarBarPositionTop];
    NSDictionary* toolbarProps = _browserOptions.toolbar;
    CGFloat toolbarOffsetHeight = [self getOffsetToolbarHeight];
    
    WKUserContentController* userContentController = [[WKUserContentController alloc] init];
    
    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    configuration.userContentController = userContentController;
#if __has_include("CDVWKProcessPoolFactory.h")
    configuration.processPool = [[CDVWKProcessPoolFactory sharedFactory] sharedProcessPool];
#endif
    [configuration.userContentController addScriptMessageHandler:self name:IAB_BRIDGE_NAME];
    
    //WKWebView options
    configuration.allowsInlineMediaPlayback = _browserOptions.allowinlinemediaplayback;
    if (IsAtLeastiOSVersion(@"10.0")) {
        if(_browserOptions.mediaplaybackrequiresuseraction == YES){
            configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        }else{
            configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
        }
    }else{ // iOS 9
        configuration.mediaPlaybackRequiresUserAction = _browserOptions.mediaplaybackrequiresuseraction;
    }
    
    self.webView = [[WKWebView alloc] initWithFrame:webViewBounds configuration:configuration];
    
    self.webView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    
    [self.view addSubview:self.webView];
    [self.view sendSubviewToBack:self.webView];
    
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self.webViewUIDelegate;
    self.webView.backgroundColor = [UIColor whiteColor];
    
    self.webView.clearsContextBeforeDrawing = YES;
    self.webView.clipsToBounds = YES;
    self.webView.contentMode = UIViewContentModeScaleToFill;
    self.webView.multipleTouchEnabled = YES;
    self.webView.opaque = YES;
    self.webView.userInteractionEnabled = YES;
    self.automaticallyAdjustsScrollViewInsets = YES ;
    [self.webView setAutoresizingMask:UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth];
    self.webView.allowsLinkPreview = NO;
    self.webView.allowsBackForwardNavigationGestures = NO;
        
    #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
       if (@available(iOS 11.0, *)) {
           [self.webView.scrollView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentNever];
       }
    #endif
    
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.alpha = 1.000;
    self.spinner.autoresizesSubviews = YES;
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    self.spinner.clearsContextBeforeDrawing = NO;
    self.spinner.clipsToBounds = NO;
    self.spinner.contentMode = UIViewContentModeScaleToFill;
    self.spinner.frame = CGRectMake(454.0, 231.0, 20.0, 20.0);
    self.spinner.hidden = YES;
    self.spinner.hidesWhenStopped = YES;
    self.spinner.multipleTouchEnabled = NO;
    self.spinner.opaque = NO;
    self.spinner.userInteractionEnabled = NO;
    [self.spinner stopAnimating];
    
    CGFloat toolbarY = toolbarIsAtBottom ? self.view.bounds.size.height - toolbarOffsetHeight : 0.0;
    CGRect toolbarFrame = CGRectMake(0.0, toolbarY, self.view.bounds.size.width, toolbarOffsetHeight);
    
    self.toolbar = [[UIView alloc] initWithFrame:toolbarFrame];
    self.toolbar.alpha = 1.000;
    self.toolbar.autoresizesSubviews = YES;
    self.toolbar.autoresizingMask = toolbarIsAtBottom ? (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin) : UIViewAutoresizingFlexibleWidth;
    self.toolbar.clearsContextBeforeDrawing = NO;
    self.toolbar.clipsToBounds = YES;
    self.toolbar.contentMode = UIViewContentModeScaleToFill;
    self.toolbar.hidden = NO;
    self.toolbar.multipleTouchEnabled = NO;
    self.toolbar.opaque = NO;
    self.toolbar.userInteractionEnabled = YES;
    self.toolbar.backgroundColor = [CDVThemeableBrowserViewController colorFromRGBA:[self getStringFromDict:toolbarProps withKey:kThemeableBrowserPropColor withDefault:@"#ffffffff"]];
    
    if (toolbarProps[kThemeableBrowserPropImage] || toolbarProps[kThemeableBrowserPropWwwImage]) {
        UIImage *image = [self getImage:toolbarProps[kThemeableBrowserPropImage]
                                altPath:toolbarProps[kThemeableBrowserPropWwwImage]
                             altDensity:[toolbarProps[kThemeableBrowserPropWwwImageDensity] doubleValue]
               accessibilityDescription:@""];
        
        if (image) {
            self.toolbar.backgroundColor = [UIColor colorWithPatternImage:image];
        } else {
            [self.navigationDelegate emitError:kThemeableBrowserEmitCodeLoadFail
                                   withMessage:[NSString stringWithFormat:@"Image for toolbar, %@, failed to load.",
                                                toolbarProps[kThemeableBrowserPropImage]
                                                ? toolbarProps[kThemeableBrowserPropImage] : toolbarProps[kThemeableBrowserPropWwwImage]]];
        }
    }
    
    CGFloat labelInset = 5.0;
    float locationBarY = self.view.bounds.size.height - LOCATIONBAR_HEIGHT;
    
    self.addressLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelInset, locationBarY, self.view.bounds.size.width - labelInset, LOCATIONBAR_HEIGHT)];
    self.addressLabel.adjustsFontSizeToFitWidth = NO;
    self.addressLabel.alpha = 1.000;
    self.addressLabel.autoresizesSubviews = YES;
    self.addressLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.addressLabel.backgroundColor = [UIColor clearColor];
    self.addressLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    self.addressLabel.clearsContextBeforeDrawing = YES;
    self.addressLabel.clipsToBounds = YES;
    self.addressLabel.contentMode = UIViewContentModeScaleToFill;
    self.addressLabel.enabled = YES;
    self.addressLabel.hidden = NO;
    self.addressLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    
    if ([self.addressLabel respondsToSelector:NSSelectorFromString(@"setMinimumScaleFactor:")]) {
        [self.addressLabel setValue:@(10.0/[UIFont labelFontSize]) forKey:@"minimumScaleFactor"];
    } else if ([self.addressLabel respondsToSelector:NSSelectorFromString(@"setMinimumFontSize:")]) {
        [self.addressLabel setValue:@(10.0) forKey:@"minimumFontSize"];
    }
    
    self.addressLabel.multipleTouchEnabled = NO;
    self.addressLabel.numberOfLines = 1;
    self.addressLabel.opaque = NO;
    self.addressLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    self.addressLabel.text = NSLocalizedString(@"Loading...", nil);
    self.addressLabel.textAlignment = NSTextAlignmentLeft;
    self.addressLabel.textColor = [UIColor colorWithWhite:1.000 alpha:1.000];
    self.addressLabel.userInteractionEnabled = NO;
    
    self.closeButton = [self createButton:_browserOptions.closeButton action:@selector(close) withDescription:@"close button"];
    self.backButton = [self createButton:_browserOptions.backButton action:@selector(goBack:) withDescription:@"back button"];
    self.forwardButton = [self createButton:_browserOptions.forwardButton action:@selector(goForward:) withDescription:@"forward button"];
    self.menuButton = [self createButton:_browserOptions.menu action:@selector(goMenu:) withDescription:@"menu button"];
    
    // Arramge toolbar buttons with respect to user configuration.
    CGFloat leftWidth = 0;
    CGFloat rightWidth = 0;
    
    // Both left and right side buttons will be ordered from outside to inside.
    NSMutableArray* leftButtons = [NSMutableArray new];
    NSMutableArray* rightButtons = [NSMutableArray new];
    
    if (self.closeButton) {
        CGFloat width = [self getWidthFromButton:self.closeButton];
        
        if ([kThemeableBrowserAlignRight isEqualToString:_browserOptions.closeButton[kThemeableBrowserPropAlign]]) {
            [rightButtons addObject:self.closeButton];
            rightWidth += width;
        } else {
            [leftButtons addObject:self.closeButton];
            leftWidth += width;
        }
    }
    
    if (self.menuButton) {
        CGFloat width = [self getWidthFromButton:self.menuButton];
        
        if ([kThemeableBrowserAlignRight isEqualToString:_browserOptions.menu[kThemeableBrowserPropAlign]]) {
            [rightButtons addObject:self.menuButton];
            rightWidth += width;
        } else {
            [leftButtons addObject:self.menuButton];
            leftWidth += width;
        }
    }
    
    // Back and forward buttons must be added with special ordering logic such
    // that back button is always on the left of forward button if both buttons
    // are on the same side.
    if (self.backButton && ![kThemeableBrowserAlignRight isEqualToString:_browserOptions.backButton[kThemeableBrowserPropAlign]]) {
        CGFloat width = [self getWidthFromButton:self.backButton];
        [leftButtons addObject:self.backButton];
        leftWidth += width;
    }
    
    if (self.forwardButton && [kThemeableBrowserAlignRight isEqualToString:_browserOptions.forwardButton[kThemeableBrowserPropAlign]]) {
        CGFloat width = [self getWidthFromButton:self.forwardButton];
        [rightButtons addObject:self.forwardButton];
        rightWidth += width;
    }
    
    if (self.forwardButton && ![kThemeableBrowserAlignRight isEqualToString:_browserOptions.forwardButton[kThemeableBrowserPropAlign]]) {
        CGFloat width = [self getWidthFromButton:self.forwardButton];
        [leftButtons addObject:self.forwardButton];
        leftWidth += width;
    }
    
    if (self.backButton && [kThemeableBrowserAlignRight isEqualToString:_browserOptions.backButton[kThemeableBrowserPropAlign]]) {
        CGFloat width = [self getWidthFromButton:self.backButton];
        [rightButtons addObject:self.backButton];
        rightWidth += width;
    }
    
    NSArray* customButtons = _browserOptions.customButtons;
    if (customButtons) {
        NSInteger cnt = 0;
        // Reverse loop because we are laying out from outer to inner.
        for (NSDictionary* customButton in [customButtons reverseObjectEnumerator]) {
            UIButton* button = [self createButton:customButton action:@selector(goCustomButton:) withDescription:[NSString stringWithFormat:@"custom button at %ld", (long)cnt]];
            if (button) {
                button.tag = cnt;
                CGFloat width = [self getWidthFromButton:button];
                if ([kThemeableBrowserAlignRight isEqualToString:customButton[kThemeableBrowserPropAlign]]) {
                    [rightButtons addObject:button];
                    rightWidth += width;
                } else {
                    [leftButtons addObject:button];
                    leftWidth += width;
                }
            }
            
            cnt += 1;
        }
    }
    
    self.rightButtons = rightButtons;
    self.leftButtons = leftButtons;
    
    for (UIButton* button in self.leftButtons) {
        [self.toolbar addSubview:button];
    }
    
    for (UIButton* button in self.rightButtons) {
        [self.toolbar addSubview:button];
    }
    
    [self layoutButtons];
    
    self.titleOffsetLeft = leftWidth;
    self.titleOffsetRight = rightWidth;
    self.toolbarPaddingX = 0;
    if (_browserOptions.toolbar[kThemeableBrowserPropToolbarPaddingX]) {
        self.toolbarPaddingX = [_browserOptions.toolbar[kThemeableBrowserPropToolbarPaddingX] floatValue];
    }
    
    
    // The correct positioning of title is not that important right now, since
    // rePositionViews will take care of it a bit later.
    self.titleLabel = nil;
    if (_browserOptions.title) {
        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 10, toolbarOffsetHeight)];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.numberOfLines = 1;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.titleLabel.textColor = [CDVThemeableBrowserViewController colorFromRGBA:[self getStringFromDict:_browserOptions.title withKey:kThemeableBrowserPropColor withDefault:@"#000000ff"]];
        
        if (_browserOptions.title[kThemeableBrowserPropStaticText]) {
            self.titleLabel.text = _browserOptions.title[kThemeableBrowserPropStaticText];
        }
        
        if (_browserOptions.title[kThemeableBrowserPropTitleFontSize]) {
            CGFloat fontSize = [_browserOptions.title[kThemeableBrowserPropTitleFontSize] floatValue];
            self.titleLabel.font = [self.titleLabel.font fontWithSize:fontSize];
        }
        
        [self.toolbar addSubview:self.titleLabel];
    }
    
    self.view.backgroundColor = [CDVThemeableBrowserViewController colorFromRGBA:[self getStringFromDict:_browserOptions.statusbar withKey:kThemeableBrowserPropColor withDefault:@"#ffffffff"]];
    [self.view addSubview:self.toolbar];
    self.progressView=[[UIProgressView   alloc] initWithFrame:CGRectMake(0.0, toolbarY+toolbarOffsetHeight+[self getStatusBarOffset], self.view.bounds.size.width, 20.0)];
    self.progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.progressView.progressViewStyle=UIProgressViewStyleDefault;
    self.progressView.progressTintColor=[CDVThemeableBrowserViewController colorFromRGBA:[self getStringFromDict:_browserOptions.browserProgress withKey: kThemeableBrowserPropProgressColor withDefault:@"#0000FF"]];
    self.progressView.trackTintColor=[CDVThemeableBrowserViewController colorFromRGBA:[self getStringFromDict:_browserOptions.browserProgress withKey:kThemeableBrowserPropProgressBgColor withDefault:@"#808080"]];
    if ([self getBoolFromDict:_browserOptions.browserProgress withKey:kThemeableBrowserPropShowProgress]) {
        UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        [swipeRight setDirection:UISwipeGestureRecognizerDirectionRight];
        [self.view addGestureRecognizer:swipeRight];
        [self.view addSubview:self.progressView];
        [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
    }
    // [self.view addSubview:self.addressLabel];
    // [self.view addSubview:self.spinner];
}

- (void)handleSwipe:(UISwipeGestureRecognizer *)swipe {
    // If there is no back history and backButtonCanClose is enabled, close the browser.
    if (swipe.direction == UISwipeGestureRecognizerDirectionRight && !self.webView.canGoBack && _browserOptions.backButtonCanClose) {
        [self close];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        // Update progress bar when estimatedProgress changes
         self.progressView.alpha = 1.0;
        [self.progressView setProgress:self.webView.estimatedProgress animated:YES];
        if(self.webView.estimatedProgress >= 1.0f) {
            [UIView animateWithDuration:0.3 delay:0.3 options:UIViewAnimationOptionCurveEaseOut animations:^{
              [self.progressView setAlpha:0.0f];
            } completion:^(BOOL finished) {
              [self.progressView setProgress:0.0f animated:NO];
            }];
         }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }

}

/**
 * This is a rather unintuitive helper method to load images. The reason why this method exists
 * is because due to some service limitations, one may not be able to add images to native
 * resource bundle. So this method offers a way to load image from www contents instead.
 * However loading from native resource bundle is already preferred over loading from www. So
 * if name is given, then it simply loads from resource bundle and the other two parameters are
 * ignored. If name is not given, then altPath is assumed to be a file path _under_ www and
 * altDensity is the desired density of the given image file, because without native resource
 * bundle, we can't tell what densitiy the image is supposed to be so it needs to be given
 * explicitly.
 */
- (UIImage*) getImage:(NSString*) name altPath:(NSString*) altPath altDensity:(CGFloat) altDensity accessibilityDescription:(NSString*) accessibilityDescription
{
    UIImage* result = nil;
    if (name) {
        result = [UIImage imageNamed:name];
    } else if (altPath) {
        NSString* path = [[[NSBundle mainBundle] bundlePath]
                          stringByAppendingPathComponent:[NSString pathWithComponents:@[@"www", altPath]]];
        if (!altDensity) {
            altDensity = 1.0;
        }
        NSData* data = [NSData dataWithContentsOfFile:path];
        result = [UIImage imageWithData:data scale:altDensity];
        result.accessibilityLabel = accessibilityDescription;
        result.isAccessibilityElement = true;
    }
    
    return result;
}

- (UIButton*) createButton:(NSDictionary*) buttonProps action:(SEL)action withDescription:(NSString*)description
{
    UIButton* result = nil;
    if (buttonProps) {
        UIImage *buttonImage = nil;
        NSString* accessibilityDescription = description;
        if(buttonProps[kThemeableBrowserPropAccessibilityDescription]){
            accessibilityDescription = buttonProps[kThemeableBrowserPropAccessibilityDescription];
        }
        if (buttonProps[kThemeableBrowserPropImage] || buttonProps[kThemeableBrowserPropWwwImage]) {
            buttonImage = [self getImage:buttonProps[kThemeableBrowserPropImage]
                                 altPath:buttonProps[kThemeableBrowserPropWwwImage]
                              altDensity:[buttonProps[kThemeableBrowserPropWwwImageDensity] doubleValue]
                accessibilityDescription: accessibilityDescription
                           ];
            
            if (!buttonImage) {
                [self.navigationDelegate emitError:kThemeableBrowserEmitCodeLoadFail
                                       withMessage:[NSString stringWithFormat:@"Image for %@, %@, failed to load.",
                                                    description,
                                                    buttonProps[kThemeableBrowserPropImage]
                                                    ? buttonProps[kThemeableBrowserPropImage] : buttonProps[kThemeableBrowserPropWwwImage]]];
            }
        } else {
            [self.navigationDelegate emitWarning:kThemeableBrowserEmitCodeUndefined
                                     withMessage:[NSString stringWithFormat:@"Image for %@ is not defined. Button will not be shown.", description]];
        }
        
        UIImage *buttonImagePressed = nil;
        if (buttonProps[kThemeableBrowserPropImagePressed] || buttonProps[kThemeableBrowserPropWwwImagePressed]) {
            buttonImagePressed = [self getImage:buttonProps[kThemeableBrowserPropImagePressed]
                                        altPath:buttonProps[kThemeableBrowserPropWwwImagePressed]
                                     altDensity:[buttonProps[kThemeableBrowserPropWwwImageDensity] doubleValue]
                       accessibilityDescription: accessibilityDescription
                                  ];;
            
            if (!buttonImagePressed) {
                [self.navigationDelegate emitError:kThemeableBrowserEmitCodeLoadFail
                                       withMessage:[NSString stringWithFormat:@"Pressed image for %@, %@, failed to load.",
                                                    description,
                                                    buttonProps[kThemeableBrowserPropImagePressed]
                                                    ? buttonProps[kThemeableBrowserPropImagePressed] : buttonProps[kThemeableBrowserPropWwwImagePressed]]];
            }
        } else {
            [self.navigationDelegate emitWarning:kThemeableBrowserEmitCodeUndefined
                                     withMessage:[NSString stringWithFormat:@"Pressed image for %@ is not defined.", description]];
        }
        
        if (buttonImage) {
            result = [UIButton buttonWithType:UIButtonTypeCustom];
            result.bounds = CGRectMake(0, 0, buttonImage.size.width, buttonImage.size.height);
            
            if (buttonImagePressed) {
                [result setImage:buttonImagePressed forState:UIControlStateHighlighted];
                result.adjustsImageWhenHighlighted = NO;
            }
            
            [result setImage:buttonImage forState:UIControlStateNormal];
            [result addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        }
    } else if (!buttonProps) {
        [self.navigationDelegate emitWarning:kThemeableBrowserEmitCodeUndefined
                                 withMessage:[NSString stringWithFormat:@"%@ is not defined. Button will not be shown.", description]];
    } else if (!buttonProps[kThemeableBrowserPropImage]) {
    }
    
    return result;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    
    // Reposition views.
    [self rePositionViews];
}

- (void) setWebViewFrame : (CGRect) frame {
    [self.webView setFrame:frame];
}

- (void)layoutButtons
{
    CGFloat screenWidth = CGRectGetWidth(self.view.frame);
    CGFloat toolbarHeight = self.toolbar.frame.size.height;
    CGFloat toolbarPadding = _browserOptions.fullscreen ? [self getStatusBarHeight] : 0.0;
    
    // Layout leftButtons and rightButtons from outer to inner.
    CGFloat left = self.toolbarPaddingX;
    for (UIButton* button in self.leftButtons) {
        CGSize size = button.frame.size;
        CGFloat yOffset = floorf((toolbarHeight + (toolbarPadding/2) - size.height) / 2);
        button.frame = CGRectMake(left, yOffset, size.width, size.height);
        left += size.width;
    }
    
    CGFloat right = self.toolbarPaddingX;
    for (UIButton* button in self.rightButtons) {
        CGSize size = button.frame.size;
        CGFloat yOffset = floorf((toolbarHeight + (toolbarPadding/2) - size.height) / 2);
        button.frame = CGRectMake(screenWidth - right - size.width, yOffset, size.width, size.height);
        right += size.width;
    }
}

- (void)setCloseButtonTitle:(NSString*)title
{
    // This method is not used by ThemeableBrowser. It is inherited from
    // InAppBrowser and is kept for merge purposes.
    
    // the advantage of using UIBarButtonSystemItemDone is the system will localize it for you automatically
    // but, if you want to set this yourself, knock yourself out (we can't set the title for a system Done button, so we have to create a new one)
    // self.closeButton = nil;
    // self.closeButton = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:self action:@selector(close)];
    // self.closeButton.enabled = YES;
    // self.closeButton.tintColor = [UIColor colorWithRed:60.0 / 255.0 green:136.0 / 255.0 blue:230.0 / 255.0 alpha:1];
    
    // NSMutableArray* items = [self.toolbar.items mutableCopy];
    // [items replaceObjectAtIndex:0 withObject:self.closeButton];
    // [self.toolbar setItems:items];
}

- (void)showLocationBar:(BOOL)show
{
    CGRect locationbarFrame = self.addressLabel.frame;
    CGFloat toolbarHeight = [self getOffsetToolbarHeight];
    
    BOOL toolbarVisible = !self.toolbar.hidden;
    
    // prevent double show/hide
    if (show == !(self.addressLabel.hidden)) {
        return;
    }
    
    if (show) {
        self.addressLabel.hidden = NO;
        
        if (toolbarVisible) {
            // toolBar at the bottom, leave as is
            // put locationBar on top of the toolBar
            
            CGRect webViewBounds = self.view.bounds;
            [self setWebViewFrame:webViewBounds];
            
            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
        } else {
            // no toolBar, so put locationBar at the bottom
            
            CGRect webViewBounds = self.view.bounds;
            webViewBounds.size.height -= LOCATIONBAR_HEIGHT;
            [self setWebViewFrame:webViewBounds];
            
            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
        }
    } else {
        self.addressLabel.hidden = YES;
        
        if (toolbarVisible) {
            // locationBar is on top of toolBar, hide locationBar
            
            // webView take up whole height less toolBar height
            CGRect webViewBounds = self.view.bounds;
            [self setWebViewFrame:webViewBounds];
        } else {
            // no toolBar, expand webView to screen dimensions
            [self setWebViewFrame:self.view.bounds];
        }
    }
}

- (void)showToolBar:(BOOL)show : (NSString *) toolbarPosition
{
    CGRect toolbarFrame = self.toolbar.frame;
    CGRect locationbarFrame = self.addressLabel.frame;
    CGFloat toolbarHeight = [self getOffsetToolbarHeight];
    
    BOOL locationbarVisible = !self.addressLabel.hidden;
    
    // prevent double show/hide
    if (show == !(self.toolbar.hidden)) {
        return;
    }
    
    if (show) {
        self.toolbar.hidden = NO;
        CGRect webViewBounds = self.view.bounds;
        
        if (locationbarVisible) {
            // locationBar at the bottom, move locationBar up
            // put toolBar at the bottom
            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
            self.toolbar.frame = toolbarFrame;
        } else {
            // no locationBar, so put toolBar at the bottom
            self.toolbar.frame = toolbarFrame;
        }
        
        if ([toolbarPosition isEqualToString:kThemeableBrowserToolbarBarPositionTop]) {
            toolbarFrame.origin.y = 0;
            if (!_browserOptions.fullscreen) {
                webViewBounds.origin.y += toolbarFrame.size.height;
            }
            [self setWebViewFrame:webViewBounds];
        } else {
            toolbarFrame.origin.y = (webViewBounds.size.height + LOCATIONBAR_HEIGHT);
        }
        [self setWebViewFrame:webViewBounds];
        
    } else {
        self.toolbar.hidden = YES;
        
        if (locationbarVisible) {
            // locationBar is on top of toolBar, hide toolBar
            // put locationBar at the bottom
            
            // webView take up whole height less locationBar height
            CGRect webViewBounds = self.view.bounds;
            webViewBounds.size.height -= LOCATIONBAR_HEIGHT;
            [self setWebViewFrame:webViewBounds];
            
            // move locationBar down
            locationbarFrame.origin.y = webViewBounds.size.height;
            self.addressLabel.frame = locationbarFrame;
        } else {
            // no locationBar, expand webView to screen dimensions
            [self setWebViewFrame:self.view.bounds];
        }
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewDidUnload
{
    [self.webView loadHTMLString:nil baseURL:nil];
    self.webView.UIDelegate = nil;
    [super viewDidUnload];
}

- (void) viewDidDisappear:(BOOL)animated
{
    _lastReducedStatusBarHeight = 0;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    UIStatusBarStyle statusBarStyle = UIStatusBarStyleDefault;
    if(_browserOptions.statusbar[kThemeableBrowserPropStatusBarStyle]){
        NSString* style = _browserOptions.statusbar[kThemeableBrowserPropStatusBarStyle];
        if([style isEqualToString:@"lightcontent"]){
            statusBarStyle = UIStatusBarStyleLightContent;
        }else if([style isEqualToString:@"darkcontent"]){
            if (@available(iOS 13.0, *)) {
                statusBarStyle = UIStatusBarStyleDarkContent;
            }
        }
    }
    return statusBarStyle;
}

- (BOOL) prefersStatusBarHidden{
    return _browserOptions.fullscreen;
}

- (void)close
{
    [self emitEventForButton:_browserOptions.closeButton];
    
    if ([self getBoolFromDict:_browserOptions.browserProgress withKey:kThemeableBrowserPropShowProgress]) {
        [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    }
    
    self.currentURL = nil;
    self.webView.UIDelegate = nil;
    CDVThemeableBrowser* navigationDelegate = self.navigationDelegate;
    
    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self respondsToSelector:@selector(presentingViewController)]) {
            [[self presentingViewController] dismissViewControllerAnimated:!_browserOptions.disableAnimation completion:^{
                [navigationDelegate nilTmpWindow];
            }];
        } else {
            [[self parentViewController] dismissViewControllerAnimated:!_browserOptions.disableAnimation completion:^{
                [navigationDelegate nilTmpWindow];
            }];
        }
    });
    
    if ((self.navigationDelegate != nil) && [self.navigationDelegate respondsToSelector:@selector(browserExit)]) {
        [self.navigationDelegate browserExit];
    }
    
}

- (void)reload
{
    [self.webView reload];
}

- (void)navigateTo:(NSURL*)url
{
    NSURLRequest* request = [NSURLRequest requestWithURL:url];
    
    [self.webView loadRequest:request];
}

- (void)goBack:(id)sender
{
    [self emitEventForButton:_browserOptions.backButton];
    
    if (self.webView.canGoBack) {
        [self.webView goBack];
        [self updateButton:self.webView];
    } else if (_browserOptions.backButtonCanClose) {
        [self close];
    }
}

- (void)goForward:(id)sender
{
    [self emitEventForButton:_browserOptions.forwardButton];
    
    [self.webView goForward];
    [self updateButton:self.webView];
}

- (void)goCustomButton:(id)sender
{
    UIButton* button = sender;
    NSInteger index = button.tag;
    [self emitEventForButton:_browserOptions.customButtons[index] withIndex:[NSNumber numberWithLong:index]];
}

- (void)goMenu:(id)sender
{
    [self emitEventForButton:_browserOptions.menu];
    
    if (_browserOptions.menu && _browserOptions.menu[kThemeableBrowserPropItems]) {
        NSArray* menuItems = _browserOptions.menu[kThemeableBrowserPropItems];
        if (IsAtLeastiOSVersion(@"8.0")) {
            // iOS > 8 implementation using UIAlertController, which is the new way
            // to do this going forward.
            UIAlertController *alertController = [UIAlertController
                                                  alertControllerWithTitle:_browserOptions.menu[kThemeableBrowserPropTitle]
                                                  message:nil
                                                  preferredStyle:UIAlertControllerStyleActionSheet];
            alertController.popoverPresentationController.sourceView
            = self.menuButton;
            alertController.popoverPresentationController.sourceRect
            = self.menuButton.bounds;
            
            for (NSInteger i = 0; i < menuItems.count; i++) {
                NSInteger index = i;
                NSDictionary *item = menuItems[index];
                
                UIAlertAction *a = [UIAlertAction
                                    actionWithTitle:item[@"label"]
                                    style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction *action) {
                                        [self menuSelected:index];
                                    }];
                [alertController addAction:a];
            }
            
            if (_browserOptions.menu[kThemeableBrowserPropCancel]) {
                UIAlertAction *cancelAction = [UIAlertAction
                                               actionWithTitle:_browserOptions.menu[kThemeableBrowserPropCancel]
                                               style:UIAlertActionStyleCancel
                                               handler:nil];
                [alertController addAction:cancelAction];
            }
            
            [self presentViewController:alertController animated:YES completion:nil];
        } else {
            // iOS < 8 implementation using UIActionSheet, which is deprecated.
            UIActionSheet *popup = [[UIActionSheet alloc]
                                    initWithTitle:_browserOptions.menu[kThemeableBrowserPropTitle]
                                    delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
            
            for (NSDictionary *item in menuItems) {
                [popup addButtonWithTitle:item[@"label"]];
            }
            if (_browserOptions.menu[kThemeableBrowserPropCancel]) {
                [popup addButtonWithTitle:_browserOptions.menu[kThemeableBrowserPropCancel]];
                popup.cancelButtonIndex = menuItems.count;
            }
            
            [popup showFromRect:self.menuButton.frame inView:self.view animated:YES];
        }
    } else {
        [self.navigationDelegate emitWarning:kThemeableBrowserEmitCodeUndefined
                                 withMessage:@"Menu items undefined. No menu will be shown."];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [self menuSelected:buttonIndex];
}

- (void) menuSelected:(NSInteger)index
{
    NSArray* menuItems = _browserOptions.menu[kThemeableBrowserPropItems];
    if (index < menuItems.count) {
        [self emitEventForButton:menuItems[index] withIndex:[NSNumber numberWithLong:index]];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    if (IsAtLeastiOSVersion(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarStyle:[self preferredStatusBarStyle]];
    }
    [self rePositionViews];
    
    [super viewWillAppear:animated];
}


- (CGFloat) getStatusBarHeight {
    return [[UIApplication sharedApplication] statusBarFrame].size.height;
}

- (CGFloat) getStatusBarOffset {
    CGFloat offset = 0;
    if(_browserOptions.fullscreen){
        if(![self isPortrait]){
            offset = [self getTopSafeAreaInset];
        }
    }else{
        offset = [self getStatusBarHeight];
    }
    return offset;
}

- (BOOL) isPortrait{
    return [[UIDevice currentDevice] orientation] == UIDeviceOrientationPortrait;
}

- (BOOL)hasTopNotch {
    return [self getTopSafeAreaInset] > 20.0;
}

- (CGFloat) getTopSafeAreaInset {
    if (@available(iOS 13.0, *)) {
        return [self keyWindow].safeAreaInsets.top;
    }else if (@available(iOS 11.0, *)){
        return [[[UIApplication sharedApplication] delegate] window].safeAreaInsets.top;
    }
    return 0.0;
}

- (UIWindow*)keyWindow {
    UIWindow        *foundWindow = nil;
    NSArray         *windows = [[UIApplication sharedApplication]windows];
    for (UIWindow   *window in windows) {
        if (window.isKeyWindow) {
            foundWindow = window;
            break;
        }
    }
    return foundWindow;
}

-(CGFloat) getToolbarTopSafeAreaOffset {
    return _browserOptions.fullscreen ? [self getTopSafeAreaInset] : 0.0;
}

-(CGFloat) getOffsetToolbarHeight {
    return [self getToolbarHeight] + [self getToolbarTopSafeAreaOffset];
}

-(CGFloat) getToolbarHeight {
    return [self getFloatFromDict:_browserOptions.toolbar withKey:kThemeableBrowserPropHeight withDefault:TOOLBAR_HEIGHT];
}

- (void) rePositionViews {
       
    CGRect viewBounds = [self.webView bounds];
    CGFloat statusBarOffset = [self getStatusBarOffset];
    CGFloat toolbarHeight = [self getToolbarHeight];
    CGFloat toolbarTopSafeAreaOffset = [self getToolbarTopSafeAreaOffset];
    
    // orientation portrait or portraitUpsideDown: status bar is on the top and web view is to be aligned to the bottom of the status bar
    // orientation landscapeLeft or landscapeRight: status bar height is 0 in but lets account for it in case things ever change in the future
    viewBounds.origin.y = statusBarOffset;
    
    // account for web view height portion that may have been reduced by a previous call to this method
    viewBounds.size.height = viewBounds.size.height - statusBarOffset + (_browserOptions.fullscreen ? 0 : _lastReducedStatusBarHeight);
    _lastReducedStatusBarHeight = statusBarOffset;
    
    CGFloat initialWebViewHeight = self.view.frame.size.height;
    
    if ((_browserOptions.toolbar) && ([_browserOptions.toolbarposition isEqualToString:kThemeableBrowserToolbarBarPositionTop])) {
        // if we have to display the toolbar on top of the web view, we need to account for its height
        CGFloat webViewOffset = [self getToolbarHeight] + (_browserOptions.fullscreen || [self isPortrait] ? _initialStatusBarHeight : 0) + (_browserOptions.fullscreen ? _lastReducedStatusBarHeight : 0);
        viewBounds.origin.y = webViewOffset;
        
        CGFloat webViewHeight = initialWebViewHeight - webViewOffset;
        viewBounds.size.height = webViewHeight;
        
        self.toolbar.frame = CGRectMake(self.toolbar.frame.origin.x, statusBarOffset, self.toolbar.frame.size.width, self.toolbar.frame.size.height);
    }
    self.webView.frame = viewBounds;
    
    
    
    
    if (self.titleLabel) {
        CGFloat screenWidth = CGRectGetWidth(self.view.frame);
        NSInteger width = floorf(screenWidth - (self.titleOffsetLeft + self.titleOffsetRight));
        CGFloat leftOffset;
        if(self.titleOffsetLeft > 0 && self.titleOffsetRight > 0){
            leftOffset = floorf((screenWidth - width) / 2.0f);
        }else if(self.titleOffsetLeft > 0){
            leftOffset = self.titleOffsetLeft;
        }else{
            leftOffset = self.toolbarPaddingX;
        }
        
        CGFloat toolbarHeight = self.toolbar.frame.size.height;
        CGFloat toolbarPadding = _browserOptions.fullscreen ? [self getStatusBarHeight] : 0.0;
        CGSize size = self.titleLabel.frame.size;
        CGFloat yOffset = floorf((toolbarHeight + (toolbarPadding/2) - size.height) / 2);
        
        self.titleLabel.frame = CGRectMake(leftOffset, yOffset, width, toolbarHeight);
    }
    
    [self layoutButtons];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context)
    {
        [self rePositionViews];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context)
    {

    }];

    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (CGFloat) getFloatFromDict:(NSDictionary*)dict withKey:(NSString*)key withDefault:(CGFloat)def
{
    CGFloat result = def;
    if (dict && dict[key]) {
        result = [(NSNumber*) dict[key] floatValue];
    }
    return result;
}

- (NSString*) getStringFromDict:(NSDictionary*)dict withKey:(NSString*)key withDefault:(NSString*)def
{
    NSString* result = def;
    if (dict && dict[key]) {
        result = dict[key];
    }
    return result;
}

- (BOOL) getBoolFromDict:(NSDictionary*)dict withKey:(NSString*)key
{
    BOOL result = NO;
    if (dict && dict[key]) {
        result = [(NSNumber*) dict[key] boolValue];
    }
    return result;
}

- (CGFloat) getWidthFromButton:(UIButton*)button
{
    return button.frame.size.width;
}

- (void)emitEventForButton:(NSDictionary*)buttonProps
{
    [self emitEventForButton:buttonProps withIndex:nil];
}

- (void)emitEventForButton:(NSDictionary*)buttonProps withIndex:(NSNumber*)index
{
    @try {
        if (buttonProps) {
            NSString* event = buttonProps[kThemeableBrowserPropEvent];
            if (event) {
                NSMutableDictionary* dict = [NSMutableDictionary new];
                [dict setObject:event forKey:@"type"];
                NSString* url = [self.navigationDelegate.themeableBrowserViewController.currentURL absoluteString];
                if(url != nil){
                    [dict setObject:url forKey:@"url"];
                }
            
                if (index) {
                    [dict setObject:index forKey:@"index"];
                }
                [self.navigationDelegate emitEvent:dict];
            } else {
                [self.navigationDelegate emitWarning:kThemeableBrowserEmitCodeUndefined
                                         withMessage:@"Button clicked, but event property undefined. No event will be raised."];
            }
        }
    }@catch (NSException *exception) {
        NSLog(@"EXCEPTION on emitEventForButton: %@", exception.reason);
    }
}

#pragma mark WKNavigationDelegate

- (void)webView:(WKWebView *)theWebView didStartProvisionalNavigation:(WKNavigation *)navigation{
    
    // loading url, start spinner, update back/forward
    
    self.addressLabel.text = NSLocalizedString(@"Loading...", nil);
    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;
	[self.spinner startAnimating];
    
    return [self.navigationDelegate didStartProvisionalNavigation:theWebView];
}

- (void)webView:(WKWebView *)theWebView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *url = navigationAction.request.URL;
    NSURL *mainDocumentURL = navigationAction.request.mainDocumentURL;
    
    BOOL isTopLevelNavigation = [url isEqual:mainDocumentURL];
    
    if (isTopLevelNavigation) {
        self.currentURL = url;
    }
    
    [self.navigationDelegate webView:theWebView decidePolicyForNavigationAction:navigationAction decisionHandler:decisionHandler];
}

- (void)webView:(WKWebView *)theWebView didFinishNavigation:(WKNavigation *)navigation
{
    // update url, stop spinner, update back/forward
    
    self.addressLabel.text = [self.currentURL absoluteString];
    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;
    theWebView.scrollView.contentInset = UIEdgeInsetsZero;
    
    if (self.titleLabel && _browserOptions.title
        && !_browserOptions.title[kThemeableBrowserPropStaticText]
        && [self getBoolFromDict:_browserOptions.title withKey:kThemeableBrowserPropShowPageTitle]) {
        // Update title text to page title when title is shown and we are not
        // required to show a static text.
        [self.webView evaluateJavaScript:@"document.title" completionHandler:^(NSString* title, NSError* _Nullable error) {
            self.titleLabel.text = title;
        }];
    }
    
    [self.spinner stopAnimating];
   
    
    [self.navigationDelegate didFinishNavigation:theWebView];
}
    
- (void)webView:(WKWebView*)theWebView failedNavigation:(NSString*) delegateName withError:(nonnull NSError *)error{
    // log fail message, stop spinner, update back/forward
    NSLog(@"webView:%@ - %ld: %@", delegateName, (long)error.code, [error localizedDescription]);
    
    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;
    [self.spinner stopAnimating];
    
    self.addressLabel.text = NSLocalizedString(@"Load Error", nil);
    
    [self.navigationDelegate webView:theWebView didFailNavigation:error];
}

- (void)webView:(WKWebView*)theWebView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(nonnull NSError *)error
{
    [self webView:theWebView failedNavigation:@"didFailNavigation" withError:error];
}
    
- (void)webView:(WKWebView*)theWebView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(nonnull NSError *)error
{
    [self webView:theWebView failedNavigation:@"didFailProvisionalNavigation" withError:error];
}

#pragma mark WKScriptMessageHandler delegate
- (void)userContentController:(nonnull WKUserContentController *)userContentController didReceiveScriptMessage:(nonnull WKScriptMessage *)message {
    if (![message.name isEqualToString:IAB_BRIDGE_NAME]) {
        return;
    }
    //NSLog(@"Received script message %@", message.body);
    [self.navigationDelegate userContentController:userContentController didReceiveScriptMessage:message];
}


- (void)updateButton:(WKWebView*)theWebView
{
    if (self.backButton) {
        self.backButton.enabled = _browserOptions.backButtonCanClose || theWebView.canGoBack;
    }
    
    if (self.forwardButton) {
        self.forwardButton.enabled = theWebView.canGoForward;
    }
}


#pragma mark CDVScreenOrientationDelegate

- (BOOL)shouldAutorotate
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotate)]) {
        return [self.orientationDelegate shouldAutorotate];
    }
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(supportedInterfaceOrientations)]) {
        return [self.orientationDelegate supportedInterfaceOrientations];
    }
    
    return 1 << UIInterfaceOrientationPortrait;
}


+ (UIColor *)colorFromRGBA:(NSString *)rgba {
    unsigned rgbaVal = 0;
    
    if ([[rgba substringWithRange:NSMakeRange(0, 1)] isEqualToString:@"#"]) {
        // First char is #, get rid of that.
        rgba = [rgba substringFromIndex:1];
    }
    
    if (rgba.length < 8) {
        // If alpha is not given, just append ff.
        rgba = [NSString stringWithFormat:@"%@ff", rgba];
    }
    
    NSScanner *scanner = [NSScanner scannerWithString:rgba];
    [scanner setScanLocation:0];
    [scanner scanHexInt:&rgbaVal];
    
    return [UIColor colorWithRed:(rgbaVal >> 24 & 0xFF) / 255.0f
                           green:(rgbaVal >> 16 & 0xFF) / 255.0f
                            blue:(rgbaVal >> 8 & 0xFF) / 255.0f
                           alpha:(rgbaVal & 0xFF) / 255.0f];
}

@end

@implementation CDVThemeableBrowserOptions

- (id)init
{
    if (self = [super init]) {
        // default values
        self.location = YES;
        self.closebuttoncaption = nil;
        self.toolbarposition = kThemeableBrowserToolbarBarPositionBottom;
        self.clearcache = NO;
        self.clearsessioncache = NO;
        
        self.zoom = YES;
        self.mediaplaybackrequiresuseraction = NO;
        self.allowinlinemediaplayback = NO;
        self.keyboarddisplayrequiresuseraction = YES;
        self.suppressesincrementalrendering = NO;
        self.hidden = NO;
        self.disallowoverscroll = NO;
        
        self.statusbar = nil;
        self.toolbar = nil;
        self.title = nil;
        self.backButton = nil;
        self.forwardButton = nil;
        self.closeButton = nil;
        self.menu = nil;
        self.backButtonCanClose = NO;
        self.disableAnimation = NO;
        self.fullscreen = NO;
    }
    
    return self;
}

@end

#pragma mark CDVScreenOrientationDelegate

@implementation CDVThemeableBrowserNavigationController : UINavigationController

- (void) dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion {
    if ( self.presentedViewController) {
        [super dismissViewControllerAnimated:flag completion:completion];
    }
}

- (BOOL)shouldAutorotate
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotate)]) {
        return [self.orientationDelegate shouldAutorotate];
    }
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(supportedInterfaceOrientations)]) {
        return [self.orientationDelegate supportedInterfaceOrientations];
    }
    
    return 1 << UIInterfaceOrientationPortrait;
}


@end

