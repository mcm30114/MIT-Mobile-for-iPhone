#import <Security/Security.h>

#import "Foundation+MITAdditions.h"
#import "MITConstants.h"
#import "MITJSON.h"
#import "MITLogging.h"
#import "MITMobileServerConfiguration.h"
#import "MobileKeychainServices.h"
#import "MobileRequestAuthenticationTracker.h"
#import "MobileRequestLoginViewController.h"
#import "MobileRequestOperation.h"
#import "SAMLResponse.h"
#import "TouchstoneAuthResponse.h"

static  MobileRequestAuthenticationTracker* gSecureStateTracker = nil;

typedef enum {
    MobileRequestStateOK = 0,
    MobileRequestStateWAYF,
    MobileRequestStateIDP,
    MobileRequestStateAuthOK,
    MobileRequestStateCanceled,
    MobileRequestStateAuthError
} MobileRequestState;

@interface MobileRequestOperation ()
@property (nonatomic,copy) NSString *command;
@property (nonatomic,copy) NSString *module;
@property (nonatomic,copy) NSDictionary *parameters;
@property (nonatomic,copy) NSURLRequest *initialRequest;

@property (nonatomic) BOOL presetCredentials;
@property BOOL isExecuting;
@property BOOL isFinished;

@property (nonatomic,copy) NSURLRequest *activeRequest;
@property (retain) NSURLConnection *connection;
@property (nonatomic,retain) MobileRequestLoginViewController *loginViewController;
@property (nonatomic,retain) NSMutableData *requestData;
@property (nonatomic,retain) NSError *requestError;
@property (nonatomic) MobileRequestState requestState;
@property (copy) NSString *touchstoneUser;
@property (copy) NSString *touchstonePassword;


@property (retain) NSRunLoop *operationRunLoop;

// Used to prevent the run loop from prematurely exiting
// if there are no active connections and the class
// is waiting for the user to authenticate
@property (retain) NSTimer *runLoopTimer;

+ (NSString*)descriptionForState:(MobileRequestState)state;

- (BOOL)authenticationRequired;
- (NSURLRequest*)buildURLRequest;
- (void)dispatchCompleteBlockWithResult:(id)jsonResult
                                  error:(NSError*)error;
- (void)displayLoginPrompt;

- (void)displayLoginPrompt:(BOOL)forceDisplay;

- (void)finish;
- (void)transitionToState:(MobileRequestState)state
          willSendRequest:(NSURLRequest*)request;

@end

@implementation MobileRequestOperation
@synthesize module = _module,
            command = _command,
            parameters = _parameters,
            usePOST = _usePOST,
            presetCredentials = _presetCredentials,
            completeBlock = _completeBlock,
            progressBlock = _progressBlock;

@synthesize activeRequest = _activeRequest,
            connection = _connection,
            loginViewController = _loginViewController,
            initialRequest = _initialRequest,
            operationRunLoop = _operationRunLoop,
            runLoopTimer = _runLoopTimer,
            requestData = _requestData,
            requestState = _requestState,
            requestError = _requestError,
            touchstoneUser = _touchstoneUser,
            touchstonePassword = _touchstonePassword;

@dynamic isFinished, isExecuting;

#pragma mark - Class Methods
+ (void)initialize {
    gSecureStateTracker = [[MobileRequestAuthenticationTracker alloc] init];
}

+ (id)operationWithModule:(NSString*)aModule command:(NSString*)theCommand parameters:(NSDictionary*)params
{
    MobileRequestOperation *operation = [[self alloc] initWithModule:aModule
                                                             command:theCommand
                                                          parameters:params];
    return [operation autorelease];
}

+ (NSString*)descriptionForState:(MobileRequestState)state
{
    switch(state)
    {
        case MobileRequestStateOK:
            return @"MobileRequestStateOK";
            
        case MobileRequestStateWAYF:
            return @"MobileRequestStateWAYF";
            
        case MobileRequestStateIDP:
            return @"MobileRequestStateIDP";
            
        case MobileRequestStateAuthOK:
            return @"MobileRequestStateAuthOK";
            
        case MobileRequestStateCanceled:
            return @"MobileRequestStateCanceled";
            
        case MobileRequestStateAuthError:
            return @"MobileRequestStateAuthError";

        default:
            return @"MobileRequestStateUnknown";
    }
}

+ (BOOL)isAuthenticationCookie:(NSHTTPCookie*)cookie
{
    NSString *name = [cookie name];
    NSRange range = [name rangeOfString:@"_shib"
                                options:NSCaseInsensitiveSearch];
    return (range.location != NSNotFound);
}

+ (void)clearAuthenticatedSession
{
    NSHTTPCookieStorage *cookieStore = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [cookieStore cookies]) {
        NSRange range = [[cookie name] rangeOfString:@"_saml"
                                             options:NSCaseInsensitiveSearch];
        if ((range.location != NSNotFound) || [self isAuthenticationCookie:cookie]) {
            DLog(@"Deleting cookie: %@[%@]",[cookie name], [cookie domain]);
            [cookieStore deleteCookie:cookie];
        }
    }
}


#pragma mark - Instance Methods        
- (id)initWithModule:(NSString*)aModule command:(NSString*)theCommand parameters:(NSDictionary*)params
{
    self = [super init];
    if (self) {
        self.module = aModule;
        self.command = theCommand;
        self.parameters = params;
        self.usePOST = NO;
        
        self.isExecuting = NO;
        self.isFinished = NO;
        self.presetCredentials = NO;
    }
    
    return self;
}

- (void)dealloc {
    self.module = nil;
    self.command = nil;
    self.parameters = nil;
    self.progressBlock = nil;
    self.completeBlock = nil;
    
    self.activeRequest = nil;
    self.connection = nil;
    self.initialRequest = nil;
    self.operationRunLoop = nil;
    self.requestData = nil;
    self.requestError = nil;
    self.touchstoneUser = nil;
    self.touchstonePassword = nil;
    [super dealloc];
}


#pragma mark - Equality
- (BOOL)isEqual:(NSObject*)object
{
    if ([object isKindOfClass:[self class]]) {
        return [self isEqualToOperation:(MobileRequestOperation*)object];
    } else {
        return [super isEqual:object];
    }
}

- (BOOL)isEqualToOperation:(MobileRequestOperation*)operation
{
    return ([self.module isEqualToString:operation.module] &&
            [self.command isEqualToString:operation.command] &&
            [self.parameters isEqualToDictionary:operation.parameters]);
}

- (NSUInteger)hash
{
    NSUInteger hash = [self.module hash];
    hash ^= [self.command hash];
    hash ^= [self.parameters hash];
    
    for (NSString *key in self.parameters) {
        hash ^= [key hash];
        hash ^= [[self.parameters objectForKey:key] hash];
    }
    
    return hash;
}

#pragma mark - Lifecycle Methods
- (BOOL)isConcurrent {
    return YES;
}

- (void)start {
    NSURLRequest *request = [self urlRequest];
    
    if ([NSURLConnection canHandleRequest:request]) {
        self.initialRequest = request;
        self.requestData = nil;
        self.requestError = nil;
        
        self.isExecuting = YES;
        self.isFinished = NO;
        
        [self retain];
        [self main];
    }
}

- (void)main {
    if ([NSThread isMainThread]) {
        [NSThread detachNewThreadSelector:@selector(main)
                                 toTarget:self
                               withObject:nil];
        return;
    }
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    self.operationRunLoop = [NSRunLoop currentRunLoop];
    self.runLoopTimer = [[[NSTimer alloc] initWithFireDate:[NSDate distantFuture]
                                                 interval:0.0
                                                   target:self
                                                 selector:nil
                                                 userInfo:nil
                                                  repeats:NO] autorelease];
    [self.operationRunLoop addTimer:self.runLoopTimer
                            forMode:NSDefaultRunLoopMode];
    [self transitionToState:MobileRequestStateOK
            willSendRequest:self.initialRequest];
    
    // Without this (unless we are on the main run loop) the
    // NSURLConnections will never be processed
    [self.operationRunLoop run];
    [pool drain];
}

- (void)finish {
/*    MobileRequestLoginViewController *loginViewController = self.loginViewController;
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        if (loginViewController) {
            [loginViewController hideActivityView];
            [rootViewController dismissModalViewControllerAnimated:YES];
        }
    });
    
    
    // Wait for the animation to complete and clear the modalViewController
    // property otherwise the backed up blocks might stumble over it
    while ([rootViewController modalViewController] != nil) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
    }*/
    
    self.loginViewController = nil;
    self.activeRequest = nil;
    self.connection = nil;
    self.initialRequest = nil;
    self.operationRunLoop = nil;
    self.requestState = MobileRequestStateOK;
    self.touchstoneUser = nil;
    self.touchstonePassword = nil;
    
    [self.runLoopTimer invalidate];
    self.runLoopTimer = nil;
    
    [gSecureStateTracker resumeQueue];
    
    
    // This may not be completely necessary since the operation
    // should be running on it's own thread but there may be
    // cases where the -(void)finish method is called on the main
    // thread (instead of the operation's thread) and it shouldn't
    // block.
    NSData *jsonData = [[self.requestData copy] autorelease];
    NSError *error = [[self.requestError copy] autorelease];
    self.requestData = nil;
    self.requestError = nil;
    dispatch_queue_t parseQueue = dispatch_queue_create("edu.mit.mobile.json-parse", 0);
    dispatch_async(parseQueue, ^(void) {
        id jsonResult = nil;
        NSError *jsonError = error;
        
        if (jsonError == nil) {
            jsonResult = [MITJSON objectWithJSONData:jsonData
                                               error:&jsonError];
#ifdef DEBUG
            if (jsonError)
            {
                NSString *data = [[[NSString alloc] initWithData:jsonData
                                                        encoding:NSUTF8StringEncoding] autorelease];
                DLog(@"JSON failed on data:\n-----\n%@\n-----",data);
            }
#endif
        }
        
        [self dispatchCompleteBlockWithResult:((jsonError == nil) ? jsonResult : jsonData)
                                        error:jsonError];
        
        self.isExecuting = NO;
        self.isFinished = YES;
    });
    dispatch_release(parseQueue);
    [self release];
}

- (void)cancel {
    [super cancel];

    self.requestState = MobileRequestStateCanceled;
    
    if (self.connection) {
        [self.connection cancel];
    } else {
        self.requestData = nil;
        self.requestError = [NSError errorWithDomain:MobileWebErrorDomain
                                                code:NSUserCancelledError
                                            userInfo:nil];
        [self finish];
    }
}


#pragma mark - Dynamic setters/getters
- (BOOL)isExecuting {
    return _isExecuting;
}

- (void)setIsExecuting:(BOOL)isExecuting {
    if (isExecuting != _isExecuting) {
        [self willChangeValueForKey:@"isExecuting"];
        _isExecuting = isExecuting;
        [self didChangeValueForKey:@"isExecuting"];
    }
}

- (BOOL)isFinished {
    return _isFinished;
}

- (void)setIsFinished:(BOOL)isFinished {
    if (isFinished != _isFinished) {
        [self willChangeValueForKey:@"isFinished"];
        _isFinished = isFinished;
        [self didChangeValueForKey:@"isFinished"];
    }
}


#pragma mark - Public Methods
- (NSURLRequest*)urlRequest {
    if (self.connection) {
        return self.initialRequest;
    } else {
        return [self buildURLRequest];
    }
}


- (void)authenticateUsingUsername:(NSString*)username password:(NSString*)password
{
    if ([username length] && [password length])
    {
        self.presetCredentials = YES;
        self.touchstoneUser = username;
        self.touchstonePassword = password;
    }
    else
    {
        self.presetCredentials = NO;
        self.touchstoneUser = nil;
        self.touchstonePassword = nil;
    }
}


#pragma mark - Private Methods
- (BOOL)authenticationRequired {
    NSDictionary *authItem = nil;
    if (self.presetCredentials == NO) {
        authItem = MobileKeychainFindItem(MobileLoginKeychainIdentifier, YES);
        
        if (authItem) {
            self.touchstoneUser = [authItem objectForKey:(id)kSecAttrAccount];
            self.touchstonePassword = [authItem objectForKey:(id)kSecValueData];
        }
    }
    
    BOOL promptForAuth = (authItem == nil);
    promptForAuth = promptForAuth || ([self.touchstoneUser length] == 0);
    promptForAuth = promptForAuth || ([self.touchstonePassword length] == 0);
    
    if (self.presetCredentials)
    {
        return NO;
    }
    else
    {
        return promptForAuth;
    }
}


- (NSURLRequest*)buildURLRequest {
    NSMutableString *urlString = [NSMutableString stringWithString:[MITMobileWebGetCurrentServerURL() absoluteString]];
    
    if ([urlString hasSuffix:@"/"] == NO) {
        [urlString appendString:@"/"];
    }
        
    [urlString appendFormat:@"?module=%@&command=%@",
                            [self.module urlEncodeUsingEncoding:NSUTF8StringEncoding],
                            [self.command urlEncodeUsingEncoding:NSUTF8StringEncoding]];
    
    NSMutableArray *params = [NSMutableArray arrayWithCapacity:[self.parameters count]];
    
    for (NSString *key in self.parameters) {
        NSString *value = [self.parameters objectForKey:key];
        
        if (!([[NSNull null] isEqual:value] || ([value length] == 0))) {
            NSString *param = [NSString stringWithFormat:@"%@=%@",
                               [key urlEncodeUsingEncoding:NSUTF8StringEncoding useFormURLEncoded:YES],
                               [value urlEncodeUsingEncoding:NSUTF8StringEncoding useFormURLEncoded:YES]];
            [params addObject:param];
        }
    }
    
    NSMutableURLRequest *request = nil;
    NSString *paramString = [params componentsJoinedByString:@"&"];
    
    if (self.usePOST) {
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                          cachePolicy:NSURLRequestReloadIgnoringCacheData
                                      timeoutInterval:5.0];
        [request setHTTPMethod:@"POST"];
        [request setHTTPBody:[paramString dataUsingEncoding:NSUTF8StringEncoding]];
        [request setValue:@"application/x-www-form-urlencoded"
       forHTTPHeaderField:@"Content-Type"];
    } else {
        if ([paramString length] > 0) {
            [urlString appendFormat:@"&%@",paramString];
        }
        
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                          cachePolicy:NSURLRequestReloadIgnoringCacheData
                                      timeoutInterval:5.0];
        [request setHTTPMethod:@"GET"];
    }
    
    return request; 
}

- (void)dispatchCompleteBlockWithResult:(id)jsonResult error:(NSError*)error {
    if (self.completeBlock) {
        dispatch_sync(dispatch_get_main_queue(), ^(void) {
            self.completeBlock(self,jsonResult,error);
        });
    }
}

- (void)displayLoginPrompt
{
    [self displayLoginPrompt:NO];
}

- (void)displayLoginPrompt:(BOOL)forceDisplay {
    if (self.loginViewController == nil) {
        dispatch_async(dispatch_get_main_queue(), ^ {
            if ([self authenticationRequired] || forceDisplay) {
                UIWindow *mainWindow = [[UIApplication sharedApplication] keyWindow];
                MobileRequestLoginViewController *loginView = [[[MobileRequestLoginViewController alloc] initWithUsername:self.touchstoneUser
                                                                                                                 password:self.touchstonePassword] autorelease];
                loginView.delegate = self;

                UINavigationController *loginNavController = [[[UINavigationController alloc] initWithRootViewController:loginView] autorelease];
                loginNavController.navigationBar.barStyle = UIBarStyleBlack;
                
                //[MobileRequestOperation clearAuthenticatedSession];
                
                [[mainWindow rootViewController] presentModalViewController:loginNavController
                                                                   animated:YES];
                self.loginViewController = loginView;
            } else {
                [gSecureStateTracker dispatchAuthenticationBlock];
            }
        });
    }
}

- (void)transitionToState:(MobileRequestState)state
          willSendRequest:(NSURLRequest*)request
{
    
    MobileRequestState prevState = self.requestState;
    self.requestState = state;
    
    if (request)
    {
        if (request.URL == nil)
        {
            NSMutableString *errorString = [NSMutableString string];
            [errorString appendString:@"Unable to send request: nil URL requested"];
            [errorString appendFormat:@"\n\tTransition: [%@]->[%@]",
             [MobileRequestOperation descriptionForState:prevState],
             [MobileRequestOperation descriptionForState:state]];
            [errorString appendFormat:@"\n\tURL: %@", self.activeRequest.URL];
            ELog(@"%@",errorString);
        }
        
        DLog(@"Transition:\n\t'%@' -> '%@'",
             [MobileRequestOperation descriptionForState:prevState],
             [MobileRequestOperation descriptionForState:state]);
        DLog(@"\tFor URL:\n\t\t:%@", request.URL);
        
        NSMutableURLRequest *mutableRequest = [[request mutableCopy] autorelease];
        mutableRequest.timeoutInterval = 10.0;
        self.activeRequest = mutableRequest;
        self.requestData = nil;
        self.connection = [[[NSURLConnection alloc] initWithRequest:mutableRequest
                                                           delegate:self
                                                   startImmediately:NO] autorelease];
        [self.connection scheduleInRunLoop:self.operationRunLoop
                                   forMode:NSDefaultRunLoopMode];
        [self.connection start];
    }
}

#pragma mark - NSURLConnectionDelegate
#pragma mark -- Response Handling
- (NSURLRequest *)connection:(NSURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)redirectResponse
{
    if (redirectResponse) {
        DLog(@"Redirecting to '%@'", request.URL);
        
        BOOL wayfRedirect = [[[request.URL host] lowercaseString] isEqualToString:@"wayf.mit.edu"];
        
        if (wayfRedirect) {
            if (self.requestState == MobileRequestStateOK) {
                self.requestState = MobileRequestStateWAYF;
            } else if (self.requestState == MobileRequestStateAuthOK) {
                // Authentication failed, abort the request
                self.requestState = MobileRequestStateAuthError;
                return nil;
            }
        } else if (self.requestState == MobileRequestStateAuthOK) {
            NSMutableURLRequest *newRequest = [[self.initialRequest mutableCopy] autorelease];
            newRequest.URL = [request URL];
            request = newRequest;
        }
    }
    
    self.activeRequest = request;
    return request;
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    if (self.requestData) {
        [self.requestData setLength:0];
    } else {
        self.requestData = [NSMutableData data];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (self.requestData) {
        [self.requestData appendData:data];
    } else {
        self.requestData = [NSMutableData data];
    }
    
}

- (void)connection:(NSURLConnection *)connection
   didSendBodyData:(NSInteger)bytesWritten
 totalBytesWritten:(NSInteger)totalBytesWritten
totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    if (self.progressBlock) {
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            self.progressBlock(bytesWritten,totalBytesWritten,totalBytesExpectedToWrite);
        });
    }
}


#pragma mark -- State Dependent methods
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    self.connection = nil;
    
    switch (self.requestState) {
        case MobileRequestStateWAYF:
        {
            if (self.loginViewController == nil) {
                [gSecureStateTracker suspendQueue];
                if (gSecureStateTracker.authenticationBlock == nil) {
                    [gSecureStateTracker addBlockToQueue:^(BOOL canceled) {
                        if (canceled) {
                            // Authentication is required but the user canceled
                            // the last authentication attempt and the timeout has
                            // not been triggered yet. Abort the request.
                            [self cancel];
                            return;
                        } else {
                            // Authentication is required and this is the first request
                            // to attempt to authenticate. Pop up the login view and
                            // get ready to (attempt) to continue the request once the
                            // queue is resumed
                            [gSecureStateTracker suspendQueue];
                            gSecureStateTracker.authenticationBlock = ^{
                                NSString *idp = nil;
                                NSRange range = [self.touchstoneUser rangeOfString:@"@"];
                                BOOL useMitIdp = [self.touchstoneUser hasSuffix:@"@mit.edu"];
                                useMitIdp = useMitIdp || (range.location == NSNotFound);
                                
                                if (useMitIdp) {
                                    idp = @"https://idp.mit.edu/shibboleth";
                                } else {
                                    idp = @"https://idp.touchstonenetwork.net/shibboleth-idp";
                                }
                                
                                NSString *body = [NSString stringWithFormat:@"user_idp=%@",[idp urlEncodeUsingEncoding:NSUTF8StringEncoding
                                                                                                     useFormURLEncoded:YES]];
                                
                                NSMutableURLRequest *wayfRequest = [NSMutableURLRequest requestWithURL:[self.activeRequest URL]];
                                [wayfRequest setHTTPMethod:@"POST"];
                                [wayfRequest setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
                                [self transitionToState:MobileRequestStateIDP
                                        willSendRequest:wayfRequest];
                            };
                            
                            [self displayLoginPrompt];
                        }
                    }];
                } else {
                    [gSecureStateTracker addBlockToQueue:^(BOOL canceled) {
                        if (canceled) {
                            // Authentication is required but the user canceled
                            // the last authentication attempt and the timeout has
                            // not been triggered yet. Abort the request.
                            [self cancel];
                            return;
                        } else {
                            // Authentication is required but there is already a login
                            // request ahead of this request. Since access to the credentials
                            // isn't global and they may not be saved (they are discarded
                            // immediately after a authentication attempt) we will need to
                            // re-issue the initial request and hope the cookie works.
                            [self transitionToState:MobileRequestStateOK
                                    willSendRequest:self.initialRequest];
                        }
                    }];
                }
                [gSecureStateTracker resumeQueue];
            }
            break;
        }
        
            
        case MobileRequestStateIDP:
        {
            NSString *method = [[[[self.activeRequest URL] pathComponents] lastObject] lowercaseString];
            
            if ([method isEqualToString:@"userpassword"] || [method isEqualToString:@"mit"] || [method isEqualToString:@"usernamepassword"])
            {
                TouchstoneAuthResponse *tsResponse = [[[TouchstoneAuthResponse alloc] initWithResponseData:self.requestData] autorelease];
                if (tsResponse.error) {
                    if (tsResponse.error.code == MobileWebInvalidLoginError) {
                        if (self.presetCredentials)
                        {
                            NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                                 code:NSURLErrorUserAuthenticationRequired
                                                             userInfo:nil];
                            [self connection:connection
                            didFailWithError:error];
                        }
                        else
                        {
                            self.touchstonePassword = nil;
                            if (self.loginViewController == nil)
                            {
                                [self displayLoginPrompt:YES];
                            }
                            else
                            {
                                dispatch_sync(dispatch_get_main_queue(), ^(void) {
                                    [self.loginViewController authenticationDidFailWithError:@"Please enter a valid username and password"
                                                                                   willRetry:YES];
                                });
                            }
                        }
                    } else {
                        [self connection:connection
                        didFailWithError:tsResponse.error];
                    }
                }
                else
                {
                    NSString *tsUsername = [self.touchstoneUser stringByReplacingOccurrencesOfString:@"@mit.edu"
                                                                                          withString:@""
                                                                                             options:NSCaseInsensitiveSearch
                                                                                               range:NSMakeRange(0, [self.touchstoneUser length])];

                    NSString *body = [NSString stringWithFormat:@"%@=%@&%@=%@",
                                      [@"j_username" urlEncodeUsingEncoding:NSUTF8StringEncoding],
                                      [tsUsername urlEncodeUsingEncoding:NSUTF8StringEncoding useFormURLEncoded:YES],
                                      [@"j_password" urlEncodeUsingEncoding:NSUTF8StringEncoding],
                                      [self.touchstonePassword urlEncodeUsingEncoding:NSUTF8StringEncoding useFormURLEncoded:YES]];
                                      
                    DLog(@"Got POST URL fragment: %@", tsResponse.postURLPath);
                    NSMutableURLRequest *wayfRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:tsResponse.postURLPath
                                                                                                  relativeToURL:[self.activeRequest URL]]];
                    [wayfRequest setHTTPMethod:@"POST"];
                    [wayfRequest setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES]];
                    [wayfRequest setValue:@"application/x-www-form-urlencoded"
                       forHTTPHeaderField:@"Content-Type"];
                    
                    [self transitionToState:MobileRequestStateIDP
                            willSendRequest:wayfRequest];
                }
            }
            else if ([method isEqualToString:@"sso"])
            {
                SAMLResponse *samlResponse = [[[SAMLResponse alloc] initWithResponseData:self.requestData] autorelease];
                if (samlResponse.error) {
                    if (samlResponse.error.code == MobileWebInvalidLoginError) {
                        if (self.presetCredentials)
                        {
                            NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                                 code:NSURLErrorUserAuthenticationRequired
                                                             userInfo:nil];
                            [self connection:connection
                            didFailWithError:error];
                        }
                        else
                        {
                            self.touchstonePassword = nil;
                            if (self.loginViewController == nil)
                            {
                                [self displayLoginPrompt:YES];
                            }
                            else
                            {
                                dispatch_async(dispatch_get_main_queue(), ^(void) {
                                    [self.loginViewController authenticationDidFailWithError:@"Please enter a valid username and password"
                                                                                   willRetry:YES];
                                });
                            }
                        }
                    } else {
                        [self connection:connection
                        didFailWithError:samlResponse.error];
                    }
                } else {
                    self.touchstoneUser = nil;
                    self.touchstonePassword = nil;
                    gSecureStateTracker.authenticationBlock = nil;

                    dispatch_async(dispatch_get_main_queue(), ^(void) {
                        [self.loginViewController authenticationDidSucceed];
                    });
                    
                    NSMutableString *body = [NSMutableString stringWithFormat:@"%@=%@",
                                             [@"SAMLResponse" urlEncodeUsingEncoding:NSUTF8StringEncoding],
                                             [samlResponse.samlResponse urlEncodeUsingEncoding:NSUTF8StringEncoding useFormURLEncoded:YES]];
                    
                    if (samlResponse.relayState) {
                        [body appendFormat:@"&%@=%@",
                         [@"RelayState" urlEncodeUsingEncoding:NSUTF8StringEncoding],
                         [samlResponse.relayState urlEncodeUsingEncoding:NSUTF8StringEncoding useFormURLEncoded:YES]];
                    } else {
                        [body appendFormat:@"&%@=%@",
                         [@"TARGET" urlEncodeUsingEncoding:NSUTF8StringEncoding],
                         [samlResponse.target urlEncodeUsingEncoding:NSUTF8StringEncoding useFormURLEncoded:YES]];
                    }
                    
                    
                    NSMutableURLRequest *wayfRequest = [NSMutableURLRequest requestWithURL:samlResponse.postURL];
                    [wayfRequest setHTTPMethod:@"POST"];
                    [wayfRequest setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
                    [wayfRequest setValue:@"application/x-www-form-urlencoded"
                       forHTTPHeaderField:@"Content-Type"];
                    
                    [self transitionToState:MobileRequestStateAuthOK
                            willSendRequest:wayfRequest];
                }
            }
            break;
        }
           
            
        case MobileRequestStateOK:
        case MobileRequestStateAuthOK:
        case MobileRequestStateCanceled:
        case MobileRequestStateAuthError:
        {
            [self finish];
            break;
        }
    }
}
         
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    self.requestData = nil;
    if (self.requestError == nil) {
        self.requestError = error;
    }
    
    gSecureStateTracker.authenticationBlock = nil;
    
    [self finish];
}


#pragma mark - MobileRequestLoginView Delegate Methods
-(void)loginRequest:(MobileRequestLoginViewController *)view didEndWithUsername:(NSString *)username password:(NSString *)password shouldSaveLogin:(BOOL)saveLogin {
    NSString *chompedUser = [username stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    self.touchstoneUser = chompedUser;
    self.touchstonePassword = password;

    if (saveLogin)
    {
        MobileKeychainSetItem(MobileLoginKeychainIdentifier, username, password);
    }
    else
    {
        NSDictionary *mobileCredentials = MobileKeychainFindItem(MobileLoginKeychainIdentifier, NO);

        if ([mobileCredentials objectForKey:kSecAttrAccount])
        {
            MobileKeychainSetItem(MobileLoginKeychainIdentifier, username, @"");
        }
        else
        {
            MobileKeychainDeleteItem(MobileLoginKeychainIdentifier);
        }
    }
    
    [gSecureStateTracker dispatchAuthenticationBlock];
}

- (void)cancelWasPressedForLoginRequest:(MobileRequestLoginViewController *)view {
    [gSecureStateTracker userCanceledAuthentication];
    [self cancel];
}
@end
